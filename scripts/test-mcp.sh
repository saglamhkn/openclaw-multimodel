#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

ENV="${1:-dev}"
CONFIG="$PROJECT_DIR/configs/active/$ENV/mcporter.json"

if [ ! -f "$CONFIG" ]; then
  echo "Error: $CONFIG not found. Run ./scripts/generate-config.sh first."
  exit 1
fi

echo "=== MCP Server Test [$ENV] ==="

python3 << PYEOF
import json, sys

with open("$CONFIG") as f:
    cfg = json.load(f)

servers = cfg.get("servers", {})
if not servers:
    print("  No MCP servers configured for this environment.")
    sys.exit(0)

for name, srv in servers.items():
    transport = srv.get("transport", "unknown")
    print(f"\n  [{name}] transport={transport}")

    if transport == "sse":
        url = srv.get("url", "")
        print(f"    URL: {url}")
        try:
            import urllib.request
            health_url = url.replace("/sse", "/health")
            req = urllib.request.urlopen(health_url, timeout=5)
            print(f"    Status: OK ({req.status})")
        except Exception as e:
            print(f"    Status: UNREACHABLE ({e})")

    elif transport == "stdio":
        cmd = srv.get("command", "")
        args = srv.get("args", [])
        print(f"    Command: {cmd} {' '.join(args)}")
        import shutil
        if shutil.which(cmd):
            print(f"    Binary: FOUND")
        else:
            print(f"    Binary: NOT FOUND (install with npm i -g {cmd})")

    env_vars = srv.get("env", {})
    for k, v in env_vars.items():
        status = "set" if v else "EMPTY"
        print(f"    {k}: {status}")

print()
PYEOF
