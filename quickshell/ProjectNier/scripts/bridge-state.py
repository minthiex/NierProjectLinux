#!/usr/bin/env python3
"""usage: bridge-state.py [since]     (since = unix seconds of the last look; none = the whole log)
State of the Messenger bridge for the health light (Health.qml), one JSON line:
  {"containers": {"fbtui-synapse": "running", "fbtui-meta": "running"},
   "login": "CONNECTED" | "TRANSIENT_DISCONNECT" | "BAD_CREDENTIALS" | "LOGGED_OUT" | ... | "" (no new state),
   "at": <unix seconds of this look>}
"login" is the newest bridge state mautrix-meta logged ("Sent new bridge state"): its connection to Facebook.
Only that field is read from the log; message text is never looked at."""
import json
import re
import subprocess
import sys
import time

CONTAINERS = ("fbtui-synapse", "fbtui-meta")


def run(args):
    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=20, errors="replace")
    except (OSError, subprocess.TimeoutExpired):
        return None


def main():
    at = int(time.time())
    states = {c: "" for c in CONTAINERS}
    r = run(["docker", "inspect", "-f", "{{.Name}} {{.State.Status}}", *CONTAINERS])
    if r is not None:
        for line in r.stdout.splitlines():
            p = line.strip().lstrip("/").split(" ")
            if len(p) == 2 and p[0] in states:
                states[p[0]] = p[1]

    login = ""
    if states["fbtui-meta"] == "running":
        args = ["docker", "logs"]
        if len(sys.argv) > 1 and sys.argv[1].isdigit():
            args += ["--since", sys.argv[1]]
        r = run(args + ["fbtui-meta"])
        if r is not None:
            dec = json.JSONDecoder()
            ansi = re.compile(r"\x1b\[[0-9;]*m")                 # the log is coloured
            for line in (r.stdout + r.stderr).splitlines():
                if "bridge state" not in line:
                    continue
                line = ansi.sub("", line)
                i = line.find("bridge_state={")
                if i < 0 or "Sent new bridge state" not in line:
                    continue
                try:
                    d, _ = dec.raw_decode(line, i + len("bridge_state="))
                except ValueError:
                    continue
                if isinstance(d, dict) and d.get("state_event"):
                    login = str(d["state_event"])          # lines are in time order: the last one wins
    print(json.dumps({"containers": states, "login": login, "at": at}))


if __name__ == "__main__":
    main()
