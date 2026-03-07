#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$PROJECT_DIR/openclaw.config.json"
ENV="${1:-dev}"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "No openclaw.config.json found. Run ./scripts/setup.sh first."
  exit 1
fi

# Extract environment config and check model readiness
python3 << PYEOF
import json, os, subprocess, sys

config_path = "$CONFIG_FILE"
env_name = "$ENV"

with open(config_path) as f:
    cfg = json.load(f)

environments = cfg.get("environments", {})
if env_name not in environments:
    print(f"Error: environment '{env_name}' not found in openclaw.config.json")
    print(f"  Available: {', '.join(environments.keys())}")
    sys.exit(1)

env_cfg = environments[env_name]
models = env_cfg.get("models", {})
primary = models.get("primary", "")
fallback = models.get("fallback", [])
if isinstance(fallback, str):
    fallback = [fallback]
all_models = [primary] + fallback

keys = cfg.get("keys", {})
telegram = cfg.get("telegram", {})
gateway = cfg.get("gateway", {})

print("")
print("  ============================================")
print(f"  OpenClaw — [{env_name}] environment")
print("  ============================================")
print("")
print(f"  Primary model:  {primary}")
print(f"  Fallbacks:      {', '.join(fallback) if fallback else 'none'}")
print(f"  Telegram bot:   {'enabled' if telegram.get('enabled') else 'disabled'}")
print(f"  Gateway port:   {gateway.get('port', 18789)}")
print("")

errors = []
warnings = []

# --- Check each provider type ---

# Docker Model Runner models
dmr_models = [m for m in all_models if m.startswith("docker-model-runner/")]
if dmr_models:
    dmr_cfg = env_cfg.get("docker-model-runner", {})
    target_ctx = dmr_cfg.get("context-size", 32768)
    keep_alive = dmr_cfg.get("keep-alive", -1)

    print("  Docker Model Runner:")
    for model_full in dmr_models:
        model_id = model_full.split("/", 1)[1]  # e.g. "ai/qwen3-coder"

        # Check if model exists
        try:
            result = subprocess.run(
                ["docker", "model", "list"],
                capture_output=True, text=True, timeout=10
            )
            model_exists = model_id in result.stdout or model_full.replace("docker-model-runner/", "") in result.stdout
        except Exception:
            model_exists = False

        if not model_exists:
            print(f"    [MISSING]  {model_id}")
            errors.append(f"Run: docker model pull {model_id}")
            continue

        # Check context-size configuration
        try:
            result = subprocess.run(
                ["docker", "model", "configure", "show", model_id],
                capture_output=True, text=True, timeout=10
            )
            show_output = result.stdout.strip()

            # Parse context-size from output
            current_ctx = None
            for line in show_output.split("\n"):
                if "context-size" in line.lower():
                    parts = line.split()
                    for p in parts:
                        try:
                            current_ctx = int(p)
                        except ValueError:
                            continue
        except Exception:
            current_ctx = None

        needs_configure = current_ctx != target_ctx

        if needs_configure:
            print(f"    [CONFIG]   {model_id} — setting context-size={target_ctx}, keep-alive={keep_alive}")
            try:
                subprocess.run(
                    ["docker", "model", "configure",
                     "--context-size", str(target_ctx),
                     "--keep-alive", str(keep_alive),
                     model_id],
                    capture_output=True, text=True, timeout=10
                )
                # Unload to force reload with new context
                subprocess.run(
                    ["docker", "model", "unload", model_id],
                    capture_output=True, text=True, timeout=10
                )
                print(f"    [READY]    {model_id} — context-size={target_ctx} (unloaded, will reload on first request)")
            except Exception as e:
                print(f"    [ERROR]    {model_id} — failed to configure: {e}")
                errors.append(f"Manually run: docker model configure --context-size {target_ctx} --keep-alive {keep_alive} {model_id}")
        else:
            print(f"    [READY]    {model_id} — context-size={current_ctx}")

    print("")

# Google models
google_models = [m for m in all_models if m.startswith("google/")]
if google_models:
    gemini_key = keys.get("gemini", "")
    print("  Google Gemini:")
    for model_full in google_models:
        model_id = model_full.split("/", 1)[1]
        if gemini_key:
            print(f"    [READY]    {model_id} — API key configured")
        else:
            print(f"    [NO KEY]   {model_id}")
            errors.append("Set keys.gemini in openclaw.config.json (get key at https://aistudio.google.com/apikey)")
    print("")

# Anthropic models
anthropic_models = [m for m in all_models if m.startswith("anthropic/")]
if anthropic_models:
    anthropic_key = keys.get("anthropic", "")
    print("  Anthropic Claude:")
    for model_full in anthropic_models:
        model_id = model_full.split("/", 1)[1]
        if anthropic_key:
            print(f"    [READY]    {model_id} — API key configured")
        else:
            print(f"    [NO KEY]   {model_id}")
            errors.append("Set keys.anthropic in openclaw.config.json (get key at https://console.anthropic.com/settings/keys)")
    print("")

# Ollama models
ollama_models = [m for m in all_models if m.startswith("ollama/")]
if ollama_models:
    ollama_cfg = env_cfg.get("ollama", {})
    ollama_mode = ollama_cfg.get("mode", "native")
    ollama_port = ollama_cfg.get("port", 11434)

    if ollama_mode == "native":
        ollama_url = f"http://localhost:{ollama_port}"
    else:
        ollama_url = f"http://ollama:{ollama_port}"

    print(f"  Ollama ({ollama_mode} mode):")

    # Check if Ollama is reachable
    try:
        import urllib.request
        req = urllib.request.Request(f"{ollama_url}/api/tags")
        with urllib.request.urlopen(req, timeout=5) as resp:
            tags = json.loads(resp.read())
            available = [m["name"] for m in tags.get("models", [])]
    except Exception:
        available = None

    if available is None:
        for model_full in ollama_models:
            model_id = model_full.split("/", 1)[1]
            print(f"    [OFFLINE]  {model_id} — Ollama not reachable at {ollama_url}")
        if ollama_mode == "native":
            errors.append("Start Ollama: brew services start ollama")
        else:
            errors.append("Start Ollama container: COMPOSE_PROFILES=ollama docker compose up -d ollama")
    else:
        for model_full in ollama_models:
            model_id = model_full.split("/", 1)[1]
            if model_id in available:
                print(f"    [READY]    {model_id}")
            else:
                print(f"    [MISSING]  {model_id}")
                if ollama_mode == "native":
                    errors.append(f"Run: ollama pull {model_id}")
                else:
                    errors.append(f"Run: docker exec openclaw-ollama ollama pull {model_id}")
    print("")

# --- Summary ---
print("  --------------------------------------------")
if errors:
    print("  ACTION REQUIRED:")
    for e in errors:
        print(f"    → {e}")
    print("")
else:
    print("  All models ready!")
    print("")
    print("  Run:  openclaw gateway run")
    print("")
PYEOF
