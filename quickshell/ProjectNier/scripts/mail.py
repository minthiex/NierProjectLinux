#!/usr/bin/env python3
"""Gmail helper for the NieR email window (IMAP + SMTP with an app password, standard library only).

usage:  mail.py status
        mail.py list [N]          newest N inbox messages (default 40) + unread count
        mail.py check             every account: unread count + newest unread (for badges and notices)
        mail.py get UID           one message (text body)
        mail.py seen UID          mark as read
        mail.py send              JSON in $MAIL_PAYLOAD: {to, subject, body, inReplyTo, references}
        mail.py setup             JSON in $MAIL_PAYLOAD: {address, password}  -> checks it, then adds it
        mail.py remove            JSON in $MAIL_PAYLOAD: {address}
        mail.py migrate           move the app passwords from mail.json into the keyring (verified one by one)
The account to use comes from $MAIL_ACCOUNT (default: the first saved one).
Everything is printed as one JSON object; failures are {"error": "...", "code": "auth|net|locked|other"}.
The accounts live in ~/.config/projectnier/mail.json (mode 600). An app password is either in that file or, with
{"keyring": true}, in the desktop keyring (Secret Service, here KeePassXC) under service=projectnier-mail account=<address>.
Reading the keyring never prompts: a locked database is reported as code "locked" (the window shows KEYRING LOCKED).
"""
import email
import email.policy
import imaplib
import json
import os
import re
import smtplib
import subprocess
import sys
from email.header import decode_header, make_header
from email.message import EmailMessage
from email.utils import formatdate, make_msgid, parseaddr, parsedate_to_datetime
from html.parser import HTMLParser
from pathlib import Path

CFG = Path.home() / ".config" / "projectnier" / "mail.json"
IMAP_HOST, SMTP_HOST = "imap.gmail.com", "smtp.gmail.com"
TIMEOUT = 25


def out(obj):
    sys.stdout.write(json.dumps(obj))
    sys.stdout.flush()


def fail(msg, code="other"):
    out({"error": str(msg), "code": code})
    sys.exit(0)


def read_accounts():
    """[{address, password} or {address, keyring: true}, ...]; also understands the first version's single
    {address, password}. Use password_of() to get the password of either kind."""
    try:
        c = json.loads(CFG.read_text())
    except (OSError, ValueError):
        return []
    if isinstance(c.get("accounts"), list):
        return [a for a in c["accounts"] if a.get("address") and (a.get("password") or a.get("keyring"))]
    if c.get("address") and c.get("password"):
        return [{"address": c["address"], "password": c["password"]}]
    return []


# ------------------------------------------------------------------ keyring (Secret Service over D-Bus)
KEYRING_SERVICE = "projectnier-mail"


class Locked(Exception):
    """the keyring is there but locked (or has no such entry yet): never prompt from a background check"""


def keyring_available():
    try:
        import gi
        gi.require_version("Gio", "2.0")
        from gi.repository import Gio, GLib
        bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        r = bus.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "NameHasOwner",
                          GLib.Variant("(s)", ("org.freedesktop.secrets",)), None, Gio.DBusCallFlags.NONE, 3000, None)
        return bool(r.unpack()[0])
    except Exception:
        return False


def keyring_lookup(address):
    """the stored app password; raises Locked if the database is locked or the entry is missing"""
    # only ask a keyring that already runs: a call to a missing one can make D-Bus start KWallet's daemon, which then
    # holds the name KeePassXC needs (seen 2026-11-24)
    if not keyring_available():
        raise Locked("no keyring service")
    import gi
    gi.require_version("Gio", "2.0")
    from gi.repository import Gio, GLib
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    svc, path, iface = "org.freedesktop.secrets", "/org/freedesktop/secrets", "org.freedesktop.Secret.Service"

    def call(method, args, sig):
        return bus.call_sync(svc, path, iface, method, GLib.Variant(sig, args), None,
                             Gio.DBusCallFlags.NO_AUTO_START, 10000, None).unpack()
    try:
        _, session = call("OpenSession", ("plain", GLib.Variant("s", "")), "(sv)")
        unlocked, locked = call("SearchItems", ({"service": KEYRING_SERVICE, "account": address},), "(a{ss})")
        if not unlocked:
            raise Locked("locked" if locked else "missing")
        secrets = call("GetSecrets", (unlocked[:1], session), "(aoo)")[0]
        value = secrets[unlocked[0]][2]
        return bytes(value).decode()
    except Locked:
        raise
    except Exception as e:                      # service gone, access refused ...: same as locked for the caller
        raise Locked(str(e))


def keyring_store(address, password):
    """True if the keyring now holds it (secret-tool may show the keyring's own prompt: only on user actions)"""
    try:
        r = subprocess.run(["secret-tool", "store", "--label=ProjectNier mail: " + address,
                            "service", KEYRING_SERVICE, "account", address],
                           input=password, text=True, capture_output=True, timeout=60)
        return r.returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


def keyring_clear(address):
    try:
        subprocess.run(["secret-tool", "clear", "service", KEYRING_SERVICE, "account", address],
                       capture_output=True, timeout=30)
    except (OSError, subprocess.TimeoutExpired):
        pass


def password_of(account):
    """raises Locked for a keyring account that cannot be read right now"""
    if account.get("password"):
        return account["password"]
    return keyring_lookup(account["address"])


def write_accounts(accounts):
    # written to a temporary file first and then renamed over the old one: a crash half-way never loses the logins
    CFG.parent.mkdir(parents=True, exist_ok=True)
    tmp = CFG.with_name(CFG.name + ".tmp")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as fh:
        json.dump({"accounts": accounts}, fh)
        fh.flush()
        os.fsync(fh.fileno())
    os.chmod(tmp, 0o600)
    os.replace(tmp, CFG)


def load_cfg():
    """the account named in $MAIL_ACCOUNT, or the first one"""
    accounts = read_accounts()
    if not accounts:
        fail("no login saved", "nologin")
    want = os.environ.get("MAIL_ACCOUNT", "").lower()
    a = next((x for x in accounts if x["address"].lower() == want), accounts[0])
    try:
        return a["address"], password_of(a)
    except Locked as e:
        fail("the keyring cannot be read (" + str(e) + "): open and unlock KeePassXC", "locked")


def imap_open(addr, pw, readonly=True):
    try:
        m = imaplib.IMAP4_SSL(IMAP_HOST, timeout=TIMEOUT)
        m.login(addr, pw)
    except imaplib.IMAP4.error as e:
        fail(e, "auth")
    except OSError as e:
        fail(e, "net")
    m.select("INBOX", readonly=readonly)
    return m


def dh(value):
    """decode a header that may be RFC 2047 encoded"""
    if not value:
        return ""
    try:
        return str(make_header(decode_header(value))).replace("\r", "").replace("\n", " ").strip()
    except Exception:
        return str(value)


def ts_of(date_header):
    try:
        return int(parsedate_to_datetime(date_header).timestamp() * 1000)
    except Exception:
        return 0


class Strip(HTMLParser):
    """HTML to readable text (no images, no styling)"""
    BLOCK = {"p", "div", "br", "tr", "li", "h1", "h2", "h3", "h4", "h5", "h6", "table", "blockquote"}

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.parts, self.skip = [], 0

    def handle_starttag(self, tag, attrs):
        if tag in ("style", "script", "head", "title"):
            self.skip += 1
        elif tag in self.BLOCK:
            self.parts.append("\n")
        if tag == "li":
            self.parts.append("- ")

    def handle_endtag(self, tag):
        if tag in ("style", "script", "head", "title"):
            self.skip = max(0, self.skip - 1)
        elif tag in self.BLOCK:
            self.parts.append("\n")

    def handle_data(self, data):
        if not self.skip:
            self.parts.append(data)


def html_to_text(html):
    p = Strip()
    try:
        p.feed(html)
    except Exception:
        pass
    text = "".join(p.parts).replace("\xa0", " ")
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r" *\n *", "\n", text)
    return re.sub(r"\n{3,}", "\n\n", text).strip()


# ------------------------------------------------------------------ commands
def cmd_status():
    names = [a["address"] for a in read_accounts()]
    out({"configured": bool(names), "accounts": names, "address": names[0] if names else ""})


def cmd_list(n):
    addr, pw = load_cfg()
    m = imap_open(addr, pw)
    typ, data = m.uid("SEARCH", None, "ALL")
    uids = data[0].split()[-n:] if data and data[0] else []
    typ, un = m.uid("SEARCH", None, "UNSEEN")
    unread = len(un[0].split()) if un and un[0] else 0
    items = []
    if uids:
        typ, rows = m.uid("FETCH", b",".join(uids), "(UID FLAGS BODY.PEEK[HEADER.FIELDS (FROM SUBJECT DATE)])")
        for r in rows:
            if not isinstance(r, tuple):
                continue
            meta = r[0].decode("ascii", "replace")
            uid = re.search(r"UID (\d+)", meta)
            flags = re.search(r"FLAGS \(([^)]*)\)", meta)
            if not uid:
                continue
            msg = email.message_from_bytes(r[1])
            name, address = parseaddr(dh(msg.get("From", "")))
            items.append({
                "uid": uid.group(1),
                "from": name or address,
                "address": address,
                "subject": dh(msg.get("Subject", "")) or "(no subject)",
                "ts": ts_of(msg.get("Date", "")),
                "seen": "\\Seen" in (flags.group(1) if flags else ""),
            })
    m.logout()
    items.sort(key=lambda x: x["ts"], reverse=True)
    out({"messages": items, "unread": unread})


def cmd_check():
    """every account: unread count and the newest unread messages (for the badge and new-mail notices)"""
    result = []
    for a in read_accounts():
        entry = {"address": a["address"], "unread": 0, "unseen": []}
        try:
            pw = password_of(a)
            m = imaplib.IMAP4_SSL(IMAP_HOST, timeout=TIMEOUT)
            m.login(a["address"], pw)
            m.select("INBOX", readonly=True)
            typ, un = m.uid("SEARCH", None, "UNSEEN")
            uids = un[0].split() if un and un[0] else []
            entry["unread"] = len(uids)
            newest = sorted(uids, key=int)[-5:]
            if newest:
                typ, rows = m.uid("FETCH", b",".join(newest), "(UID BODY.PEEK[HEADER.FIELDS (FROM SUBJECT)])")
                for r in rows:
                    if not isinstance(r, tuple):
                        continue
                    u = re.search(r"UID (\d+)", r[0].decode("ascii", "replace"))
                    if not u:
                        continue
                    msg = email.message_from_bytes(r[1])
                    name, address = parseaddr(dh(msg.get("From", "")))
                    entry["unseen"].append({"uid": int(u.group(1)), "from": name or address,
                                            "subject": dh(msg.get("Subject", "")) or "(no subject)"})
            m.logout()
        except Locked as e:
            entry.update(error=str(e), code="locked")
        except imaplib.IMAP4.error as e:
            entry.update(error=str(e), code="auth")
        except OSError as e:
            entry.update(error=str(e), code="net")
        result.append(entry)
    out({"accounts": result})


def cmd_get(uid):
    addr, pw = load_cfg()
    m = imap_open(addr, pw)
    typ, rows = m.uid("FETCH", uid, "(BODY.PEEK[])")
    m.logout()
    raw = next((r[1] for r in rows if isinstance(r, tuple)), None)
    if raw is None:
        fail("message not found")
    msg = email.message_from_bytes(raw, policy=email.policy.default)
    body = ""
    part = msg.get_body(preferencelist=("plain", "html"))
    if part is not None:
        try:
            body = part.get_content()
        except Exception:
            body = part.get_payload(decode=True).decode("utf-8", "replace") if part.get_payload() else ""
        if part.get_content_type() == "text/html":
            body = html_to_text(body)
    names = []
    for a in msg.iter_attachments():
        names.append(a.get_filename() or a.get_content_type())
    name, address = parseaddr(dh(msg.get("From", "")))
    reply_name, reply_addr = parseaddr(dh(msg.get("Reply-To", "")))
    out({
        "uid": uid,
        "from": name or address,
        "address": address,
        "replyTo": reply_addr or address,
        "to": dh(msg.get("To", "")),
        "cc": dh(msg.get("Cc", "")),
        "subject": dh(msg.get("Subject", "")) or "(no subject)",
        "ts": ts_of(msg.get("Date", "")),
        "messageId": str(msg.get("Message-ID", "")).strip(),
        "references": str(msg.get("References", "")).strip(),
        "body": body.replace("\r\n", "\n").strip()[:200000],
        "attachments": names,
    })


def cmd_seen(uid):
    addr, pw = load_cfg()
    m = imap_open(addr, pw, readonly=False)
    m.uid("STORE", uid, "+FLAGS", "(\\Seen)")
    m.logout()
    out({"ok": True})


def payload():
    try:
        return json.loads(os.environ.get("MAIL_PAYLOAD", ""))
    except ValueError:
        fail("bad request")


def cmd_send():
    addr, pw = load_cfg()
    p = payload()
    if not str(p.get("to", "")).strip():
        fail("no recipient")
    msg = EmailMessage()
    msg["From"] = addr
    msg["To"] = p["to"]
    msg["Subject"] = p.get("subject", "")
    msg["Date"] = formatdate(localtime=True)
    msg["Message-ID"] = make_msgid()
    if p.get("inReplyTo"):
        msg["In-Reply-To"] = p["inReplyTo"]
        msg["References"] = (p.get("references", "") + " " + p["inReplyTo"]).strip()
    msg.set_content(p.get("body", ""))
    try:
        with smtplib.SMTP_SSL(SMTP_HOST, 465, timeout=TIMEOUT) as s:
            s.login(addr, pw)
            s.send_message(msg)
    except smtplib.SMTPAuthenticationError as e:
        fail(e, "auth")
    except (OSError, smtplib.SMTPException) as e:
        fail(e, "net")
    out({"ok": True})


def cmd_setup():
    p = payload()
    addr = str(p.get("address", "")).strip()
    pw = re.sub(r"\s+", "", str(p.get("password", "")))     # Google shows app passwords in groups of four
    if "@" not in addr or not pw:
        fail("enter the address and the app password")
    try:
        m = imaplib.IMAP4_SSL(IMAP_HOST, timeout=TIMEOUT)
        m.login(addr, pw)
        m.logout()
    except imaplib.IMAP4.error as e:
        fail(e, "auth")
    except OSError as e:
        fail(e, "net")
    accounts = [a for a in read_accounts() if a["address"].lower() != addr.lower()]
    # into the keyring when there is one (checked by reading it back), else into the file as before
    if keyring_available() and keyring_store(addr, pw) and _reads_back(addr, pw):
        accounts.append({"address": addr, "keyring": True})
    else:
        accounts.append({"address": addr, "password": pw})
    write_accounts(accounts)
    out({"ok": True, "address": addr, "accounts": [a["address"] for a in accounts]})


def _reads_back(addr, pw):
    try:
        return keyring_lookup(addr) == pw
    except Locked:
        return False


def cmd_migrate():
    """every app password still in mail.json goes into the keyring; an account is only changed to {keyring: true}
    after its password reads back from the keyring unchanged. Nothing is lost if the keyring is missing or locked."""
    if not keyring_available():
        fail("no keyring service: turn on Secret Service Integration in KeePassXC", "locked")
    accounts, moved, kept = read_accounts(), 0, []
    for a in accounts:
        if not a.get("password"):
            continue
        if keyring_store(a["address"], a["password"]) and _reads_back(a["address"], a["password"]):
            a.pop("password")
            a["keyring"] = True
            moved += 1
        else:
            kept.append(a["address"])
    if moved:
        write_accounts(accounts)
    out({"ok": not kept, "moved": moved, "kept_in_file": kept})


def cmd_remove():
    addr = str(payload().get("address", "")).lower()
    for a in read_accounts():
        if a["address"].lower() == addr and a.get("keyring"):
            keyring_clear(a["address"])
    accounts = [a for a in read_accounts() if a["address"].lower() != addr]
    if accounts:
        write_accounts(accounts)
    else:
        try:
            CFG.unlink()
        except OSError:
            pass
    out({"ok": True, "accounts": [a["address"] for a in accounts]})


def main():
    a = sys.argv[1:]
    if not a:
        fail("no command")
    c = a[0]
    try:
        if c == "status":
            cmd_status()
        elif c == "list":
            cmd_list(int(a[1]) if len(a) > 1 else 40)
        elif c == "check":
            cmd_check()
        elif c == "get" and len(a) > 1:
            cmd_get(a[1])
        elif c == "seen" and len(a) > 1:
            cmd_seen(a[1])
        elif c == "send":
            cmd_send()
        elif c == "setup":
            cmd_setup()
        elif c == "remove":
            cmd_remove()
        elif c == "migrate":
            cmd_migrate()
        else:
            fail("unknown command")
    except SystemExit:
        raise
    except Exception as e:      # never leave the UI waiting on a traceback
        fail(e)


if __name__ == "__main__":
    main()
