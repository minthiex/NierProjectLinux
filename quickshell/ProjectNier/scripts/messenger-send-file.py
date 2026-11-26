#!/usr/bin/env python3
"""usage: messenger-send-file.py <room id> <file>
Sends a file into a Messenger chat: uploads it to the local Matrix server (the bridge passes it on to Facebook) and
posts it as a picture, video, audio or file message. The login comes from ~/.config/fbtui/session.json (never from
the command line, where `ps` would show it). Prints one JSON line: {"ok": true} or {"error": "..."}."""
import json
import mimetypes
import os
import struct
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

SESSION = os.path.join(os.path.expanduser("~"), ".config", "fbtui", "session.json")
LIMIT = 100 * 1024 * 1024        # Facebook refuses bigger attachments anyway


def done(d):
    print(json.dumps(d))
    sys.exit(0 if d.get("ok") else 1)


def image_size(path):
    """(w, h) of a PNG, GIF or JPEG from its header, else (0, 0)"""
    try:
        with open(path, "rb") as f:
            head = f.read(26)
            if head[:8] == b"\x89PNG\r\n\x1a\n":
                return struct.unpack(">II", head[16:24])
            if head[:6] in (b"GIF87a", b"GIF89a"):
                return struct.unpack("<HH", head[6:10])
            if head[:2] == b"\xff\xd8":
                f.seek(2)
                while True:
                    b = f.read(1)
                    while b and b != b"\xff":
                        b = f.read(1)
                    while b == b"\xff":
                        b = f.read(1)
                    if not b:
                        break
                    if b[0] in (0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF):
                        f.read(3)
                        h, w = struct.unpack(">HH", f.read(4))
                        return w, h
                    seg = struct.unpack(">H", f.read(2))[0]
                    f.seek(seg - 2, 1)
    except (OSError, struct.error):
        pass
    return 0, 0


def request(method, url, token, data=None, ctype="application/json"):
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", "Bearer " + token)
    if data is not None:
        req.add_header("Content-Type", ctype)
    try:
        with urllib.request.urlopen(req, timeout=300) as r:
            return json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        try:
            msg = json.loads(e.read()).get("error") or str(e)
        except ValueError:
            msg = str(e)
        done({"error": msg})
    except OSError as e:
        done({"error": "offline (%s)" % e})


def main():
    if len(sys.argv) != 3:
        done({"error": "usage: messenger-send-file.py <room id> <file>"})
    room, path = sys.argv[1], sys.argv[2]
    if not os.path.isfile(path):
        done({"error": "not a file: " + path})
    size = os.path.getsize(path)
    if size == 0:
        done({"error": "the file is empty"})
    if size > LIMIT:
        done({"error": "too big (%d MB; at most %d MB)" % (size >> 20, LIMIT >> 20)})
    try:
        with open(SESSION, encoding="utf-8") as f:
            s = json.load(f)
        hs = str(s["homeserver"]).rstrip("/").replace("://localhost", "://127.0.0.1")
        token = s["access_token"]
    except (OSError, ValueError, KeyError):
        done({"error": "no Messenger login"})

    name = os.path.basename(path)
    mime = mimetypes.guess_type(name)[0] or "application/octet-stream"
    with open(path, "rb") as f:
        data = f.read()
    up = request("POST", hs + "/_matrix/media/v3/upload?filename=" + urllib.parse.quote(name), token, data, mime)
    uri = up.get("content_uri")
    if not uri:
        done({"error": "the upload was refused"})

    kind = mime.split("/")[0]
    msgtype = {"image": "m.image", "video": "m.video", "audio": "m.audio"}.get(kind, "m.file")
    info = {"mimetype": mime, "size": size}
    if msgtype == "m.image":
        w, h = image_size(path)
        if w and h:
            info.update(w=w, h=h)
    body = {"msgtype": msgtype, "body": name, "url": uri, "info": info}
    txn = "nierfile%d_%d" % (int(time.time() * 1000), os.getpid())
    request("PUT", "%s/_matrix/client/v3/rooms/%s/send/m.room.message/%s" % (hs, urllib.parse.quote(room, safe=""), txn),
            token, json.dumps(body).encode())
    done({"ok": True, "name": name})


if __name__ == "__main__":
    main()
