#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$PROJECT_DIR/openclaw.config.json"

ENV_NAME="${1:-dev}"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: openclaw.config.json not found."
  echo "  Run ./scripts/setup.sh or copy openclaw.config.example.json to openclaw.config.json"
  exit 1
fi

if ! command -v clawhub &>/dev/null; then
  echo "Error: clawhub CLI not found. Install it with: npm install -g clawhub"
  exit 1
fi

echo "=== Installing ClawHub Skills for [$ENV_NAME] ==="

python3 << PYEOF
import json, os, subprocess, sys

config_path = "$CONFIG_FILE"
env_name = "$ENV_NAME"
project_dir = "$PROJECT_DIR"

with open(config_path) as f:
    cfg = json.load(f)

skills_global = cfg.get("skills", {})
install_dir = skills_global.get("installDir", "workspace")

env_cfg = cfg.get("environments", {}).get(env_name)
if not env_cfg:
    print(f"Error: environment '{env_name}' not found in config")
    sys.exit(1)

env_skills = env_cfg.get("skills", {})
if not env_skills:
    print("No skills configured for this environment.")
    sys.exit(0)

enabled = {slug: sc for slug, sc in env_skills.items() if sc.get("enabled", False)}
if not enabled:
    print("No enabled skills found.")
    sys.exit(0)

# Build clawhub install flags
skills_dir = os.path.join(project_dir, "skills") if install_dir == "workspace" else os.path.expanduser("~/.openclaw/skills")
os.makedirs(skills_dir, exist_ok=True)

base_cmd = ["clawhub", "install"]
if install_dir == "workspace":
    base_cmd.extend(["--dir", skills_dir])

env = os.environ.copy()
env["CLAWHUB_DISABLE_TELEMETRY"] = "1"

print(f"Install dir: {skills_dir}")
print(f"Skills to install: {', '.join(enabled.keys())}")
print()

failed = []
for slug in enabled:
    cmd = base_cmd + [slug]
    print(f"  Installing {slug}...")
    result = subprocess.run(cmd, env=env, capture_output=True, text=True)
    if result.returncode != 0:
        stderr = result.stderr.strip()
        if "already installed" in stderr.lower():
            print(f"    Already installed")
        else:
            print(f"    FAILED: {stderr}")
            failed.append(slug)
    else:
        print(f"    OK")

print()
if failed:
    print(f"Warning: {len(failed)} skill(s) failed to install: {', '.join(failed)}")
    sys.exit(1)
else:
    print(f"All {len(enabled)} skill(s) installed successfully.")
PYEOF
