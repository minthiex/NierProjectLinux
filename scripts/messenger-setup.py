#!/usr/bin/env python3
"""usage: messenger-setup.py      JSON in $SETUP_PAYLOAD: {"username": "...", "password": "...", "replace": false}
Sets up the Messenger of the NieR screen (Messenger.qml → SET UP MESSENGER), replacing what fbtui's setup did:
  1. the bridge recipe (docker-compose.yml + patch_configs.py) in $PROJECTNIER_BRIDGE_DIR
     (default ~/.local/share/fbtui-src/bridge): configs and the bridge registration are generated only if missing
  2. the containers are started (docker compose up -d) and Synapse is waited for
  3. the Matrix account is created through Synapse's shared-secret registration (an existing one is fine), then
     logged in: the token goes to ~/.config/fbtui/session.json (mode 600). An existing login is never replaced
     unless "replace" is true (then it is backed up to ~/backups first)
  4. the chat with the bridge bot is found or created: there you send "login" to connect Facebook
Progress: one JSON line per step {"step": "..."}; last line {"ok": true, "user_id", "bot", "bot_room"}
or {"error": "...", "code": "exists|docker|recipe|password|username|other"}. Needs only docker and python3 (the
config patcher runs inside the Synapse image, which has PyYAML)."""
import hashlib
import hmac
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

HOME = Path.home()
BRIDGE = Path(os.environ.get("PROJECTNIER_BRIDGE_DIR") or HOME / ".local/share/fbtui-src/bridge")
SESSION = HOME / ".config/fbtui/session.json"
# never "localhost": it resolves to ::1 first, Synapse listens on IPv4. Another address only for tests (a second bridge)
HS = os.environ.get("PROJECTNIER_MATRIX_URL", "http://127.0.0.1:8008").rstrip("/")
SYNAPSE_IMG = "matrixdotorg/synapse:latest"
META_IMG = "dock.mau.dev/mautrix/meta:latest"
DOMAIN = "localhost"


def say(**kw):
    print(json.dumps(kw), flush=True)


def fail(msg, code="other"):
    say(error=msg, code=code)
    sys.exit(0)


def step(text):
    say(step=text)


def run(args, **kw):
    return subprocess.run(args, capture_output=True, text=True, **kw)


def http(method, path, body=None, token=None, timeout=20):
    req = urllib.request.Request(HS + path, method=method,
                                 data=None if body is None else json.dumps(body).encode())
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", "Bearer " + token)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read() or b"{}")
        except ValueError:
            return e.code, {}
    except (urllib.error.URLError, OSError):
        return 0, {}


def ids():
    import pwd
    u = os.getuid()
    return u, pwd.getpwuid(u).pw_gid           # primary group (like setup.sh: not the docker group under sg)


def meta_fix_perms():
    u, g = ids()
    run(["docker", "run", "--rm", "--entrypoint", "chown", "-v", f"{BRIDGE}/meta:/data", META_IMG, "-R", f"{u}:{g}", "/data"])


def bridge_ready():
    """configs, registration and containers (only what is missing is made)"""
    u, g = ids()
    env = BRIDGE / ".env"
    if not env.exists():
        env.write_text(f"HOST_UID={u}\nHOST_GID={g}\n")
    (BRIDGE / "synapse").mkdir(exist_ok=True)
    (BRIDGE / "meta").mkdir(exist_ok=True)
    fresh = False
    if not (BRIDGE / "synapse/homeserver.yaml").exists():
        step("Generating the Matrix server's settings")
        r = run(["docker", "run", "--rm", "-v", f"{BRIDGE}/synapse:/data", "-e", f"UID={u}", "-e", f"GID={g}",
                 "-e", f"SYNAPSE_SERVER_NAME={DOMAIN}", "-e", "SYNAPSE_REPORT_STATS=no", SYNAPSE_IMG, "generate"])
        if not (BRIDGE / "synapse/homeserver.yaml").exists():
            fail("could not generate the Synapse config: " + (r.stderr or r.stdout).strip()[-300:], "docker")
        fresh = True
    if not (BRIDGE / "meta/config.yaml").exists():
        step("Generating the Facebook bridge's settings")
        run(["docker", "run", "--rm", "-v", f"{BRIDGE}/meta:/data", "-e", f"UID={u}", "-e", f"GID={g}", META_IMG])
        meta_fix_perms()
        if not (BRIDGE / "meta/config.yaml").exists():
            fail("the bridge config was not created (docker logs may say why)", "docker")
        fresh = True
    hs_text = (BRIDGE / "synapse/homeserver.yaml").read_text()
    if fresh or "app_service_config_files" not in hs_text:
        step("Connecting the bridge to the Matrix server")
        r = run(["docker", "run", "--rm", "--user", f"{u}:{g}", "-v", f"{BRIDGE}:/w", "--entrypoint", "python",
                 SYNAPSE_IMG, "/w/patch_configs.py", os.environ["NIER_USER"]])
        if r.returncode != 0:
            fail("patching the configs failed: " + (r.stderr or r.stdout).strip()[-300:])
    if not (BRIDGE / "meta/registration.yaml").exists():
        step("Registering the bridge")
        run(["docker", "run", "--rm", "-v", f"{BRIDGE}/meta:/data", "-e", f"UID={u}", "-e", f"GID={g}", META_IMG])
        meta_fix_perms()
        if not (BRIDGE / "meta/registration.yaml").exists():
            fail("the bridge registration was not created", "docker")
    step("Starting the containers")
    r = run(["docker", "compose", "up", "-d"], cwd=BRIDGE)
    if r.returncode != 0:
        fail("docker compose up failed: " + (r.stderr or r.stdout).strip()[-300:], "docker")
    step("Waiting for the Matrix server")
    for _ in range(60):
        if http("GET", "/_matrix/client/versions")[0] == 200:
            return
        time.sleep(2)
    fail("the Matrix server did not come up in 2 minutes (docker logs fbtui-synapse)", "docker")


def register(user, password):
    """shared-secret registration: the password never appears on a command line"""
    m = re.search(r'^registration_shared_secret:\s*["\']?([^"\'\n]+)', (BRIDGE / "synapse/homeserver.yaml").read_text(), re.M)
    if not m:
        fail("no registration_shared_secret in homeserver.yaml")
    st, d = http("GET", "/_synapse/admin/v1/register")
    if st != 200 or "nonce" not in d:
        fail("the Matrix server refused registration (shared-secret registration is off?)")
    mac = hmac.new(m.group(1).encode(), digestmod=hashlib.sha1)
    mac.update(b"\x00".join([d["nonce"].encode(), user.encode(), password.encode(), b"notadmin"]))
    st, r = http("POST", "/_synapse/admin/v1/register",
                 {"nonce": d["nonce"], "username": user, "password": password, "admin": False, "mac": mac.hexdigest()})
    if st == 200:
        return "created"
    if r.get("errcode") == "M_USER_IN_USE":
        return "exists"
    if r.get("errcode") in ("M_INVALID_USERNAME", "M_EXCLUSIVE"):
        fail("that user name cannot be used: " + r.get("error", ""), "username")
    fail("registration failed: " + r.get("error", f"HTTP {st}"))


def bridge_bot():
    m = re.search(r'^\s+bot:\s*\n(?:\s+.*\n)*?\s+username:\s*(\S+)', (BRIDGE / "meta/config.yaml").read_text(), re.M)
    return f"@{m.group(1) if m else 'facebookbot'}:{DOMAIN}"


def bot_room(token, me, bot):
    """the direct chat with the bridge bot (m.direct), or a new one named so the Messenger list treats it as the bridge's"""
    st, direct = http("GET", f"/_matrix/client/v3/user/{urllib.request.quote(me)}/account_data/m.direct", token=token)
    st2, joined = http("GET", "/_matrix/client/v3/joined_rooms", token=token)
    joined = set(joined.get("joined_rooms", [])) if st2 == 200 else set()
    if st == 200:
        for rid in direct.get(bot, []):
            if rid in joined:
                return rid
    st, r = http("POST", "/_matrix/client/v3/createRoom", {"invite": [bot], "is_direct": True, "preset": "trusted_private_chat",
                                                            "name": "Facebook bridge"}, token=token)
    if st != 200:
        fail("could not open a chat with the bridge bot: " + r.get("error", f"HTTP {st}"))
    rid = r["room_id"]
    d = direct if isinstance(direct, dict) and not direct.get("errcode") else {}
    d.setdefault(bot, []).append(rid)
    http("PUT", f"/_matrix/client/v3/user/{urllib.request.quote(me)}/account_data/m.direct", d, token=token)
    return rid


def main():
    try:
        p = json.loads(os.environ.get("SETUP_PAYLOAD", "{}"))
    except ValueError:
        p = {}
    user = str(p.get("username", "")).strip().lower().lstrip("@").split(":")[0]
    password = str(p.get("password", ""))
    if not re.fullmatch(r"[a-z0-9._=/-]{1,64}", user or "!"):
        fail("pick a user name: lowercase letters, digits and . _ - only", "username")
    if len(password) < 8:
        fail("pick a password of at least 8 characters (it stays on this computer)", "password")
    if SESSION.exists() and not p.get("replace"):
        fail("Messenger is already set up (" + str(SESSION) + ")", "exists")
    os.environ["NIER_USER"] = user

    if not shutil.which("docker"):
        fail("Messenger needs Docker: install docker and docker compose, then try again", "docker")
    if run(["docker", "info"]).returncode != 0:
        fail("Docker is not running or you may not use it: start it (systemctl start docker) and add yourself to "
             "the docker group, then log in again", "docker")
    if not (BRIDGE / "docker-compose.yml").exists() or not (BRIDGE / "patch_configs.py").exists():
        fail(f"the bridge recipe is missing: {BRIDGE} needs docker-compose.yml and patch_configs.py", "recipe")

    bridge_ready()
    step("Creating your Matrix account")
    how = register(user, password)
    step("Logging in" + (" (the account already existed)" if how == "exists" else ""))
    st, r = http("POST", "/_matrix/client/v3/login", {"type": "m.login.password",
                                                      "identifier": {"type": "m.id.user", "user": user},
                                                      "password": password, "initial_device_display_name": "ProjectNier"})
    if st != 200 or "access_token" not in r:
        fail("wrong password for @" + user + ":" + DOMAIN if st == 403 else "login failed: " + r.get("error", f"HTTP {st}"),
             "password" if st == 403 else "other")
    token, me = r["access_token"], r["user_id"]
    step("Opening the chat with the bridge bot")
    bot = bridge_bot()
    room = bot_room(token, me, bot)

    if SESSION.exists():
        bk = HOME / "backups" / ("session.json." + time.strftime("%Y%m%d-%H%M%S"))
        bk.parent.mkdir(exist_ok=True)
        shutil.copy2(SESSION, bk)
        os.chmod(bk, 0o600)
    SESSION.parent.mkdir(parents=True, exist_ok=True)
    tmp = SESSION.with_name(SESSION.name + ".tmp")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as fh:
        json.dump({"homeserver": HS.replace("://127.0.0.1", "://localhost"), "user_id": me, "device_id": r.get("device_id", ""),
                   "access_token": token}, fh)
    os.replace(tmp, SESSION)
    say(ok=True, user_id=me, bot=bot, bot_room=room)


if __name__ == "__main__":
    main()
