"""Wire the generated Synapse and mautrix-meta configs together (run by setup.sh)."""
import re
import secrets
import sys
from pathlib import Path

import yaml

DOMAIN = "localhost"
ROOT = Path(__file__).resolve().parent
user = sys.argv[1].lower()  # Matrix localparts must be lowercase


def put(cfg: dict, dotted: str, value) -> None:
    """Set a key that must already exist in the generated config.

    Failing loudly beats silently adding a key the bridge would ignore
    (that's how a stale `network.mode` slipped in).
    """
    node = cfg
    *parents, leaf = dotted.split(".")
    for key in parents:
        if not isinstance(node, dict) or key not in node:
            sys.exit(f"patch_configs: '{dotted}' not found in generated config.yaml "
                     f"(missing '{key}'); the bridge config format changed")
        node = node[key]
    if not isinstance(node, dict) or leaf not in node:
        sys.exit(f"patch_configs: '{dotted}' not found in generated config.yaml; "
                 "the bridge config format changed")
    node[leaf] = value


# --- double-puppeting registration: makes messages you send from your phone
#     show up as *you* instead of a "ghost" copy of you.
dp_path = ROOT / "synapse" / "doublepuppet.yaml"
if dp_path.exists():
    dp = yaml.safe_load(dp_path.read_text())
else:
    dp = {
        "id": "doublepuppet",
        "url": None,
        "as_token": secrets.token_hex(32),
        "hs_token": secrets.token_hex(32),
        "sender_localpart": secrets.token_hex(8),
        "rate_limited": False,
        "namespaces": {"users": [{"regex": f"@.*:{re.escape(DOMAIN)}", "exclusive": False}]},
    }
    dp_path.write_text(yaml.safe_dump(dp, sort_keys=False))
    dp_path.chmod(0o600)

# --- synapse
hs_path = ROOT / "synapse" / "homeserver.yaml"
hs = yaml.safe_load(hs_path.read_text())
hs["app_service_config_files"] = ["/meta/registration.yaml", "/data/doublepuppet.yaml"]
hs_path.write_text(yaml.safe_dump(hs, sort_keys=False))

# --- mautrix-meta
meta_path = ROOT / "meta" / "config.yaml"
cfg = yaml.safe_load(meta_path.read_text())
put(cfg, "homeserver.address", "http://synapse:8008")
put(cfg, "homeserver.domain", DOMAIN)
put(cfg, "appservice.address", "http://mautrix-meta:29319")
put(cfg, "appservice.hostname", "0.0.0.0")
put(cfg, "appservice.port", 29319)
put(cfg, "database.type", "sqlite3-fk-wal")
put(cfg, "database.uri", "file:/data/mautrix-meta.db?_txlock=immediate")
put(cfg, "bridge.permissions", {"*": "relay", DOMAIN: "user", f"@{user}:{DOMAIN}": "admin"})
put(cfg, "double_puppet.secrets", {DOMAIN: f"as_token:{dp['as_token']}"})
put(cfg, "backfill.enabled", True)
put(cfg, "backfill.max_initial_messages", 50)
meta_path.write_text(yaml.safe_dump(cfg, sort_keys=False))

print(":: configs patched")
