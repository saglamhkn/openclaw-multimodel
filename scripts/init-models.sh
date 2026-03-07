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
    target_ctx = dmr_cfg.get("context-size", 65536)
    keep_alive = dmr_cfg.get("keep-alive", -1)
    base_model = dmr_cfg.get("base-model", "")

    # Get list of available models
    try:
        result = subprocess.run(
            ["docker", "model", "list"],
            capture_output=True, text=True, timeout=10
        )
        model_list_output = result.stdout
    except Exception:
        model_list_output = ""

    print("  Docker Model Runner:")
    for model_full in dmr_models:
        model_id = model_full.split("/", 1)[1]  # e.g. "qwen3-coder:65k"

        # Derive base model from config or model_id
        model_base = base_model or model_id.split(":")[0]  # e.g. "qwen3-coder"

        # Check if base model exists (needed for packaging)
        base_exists = model_base in model_list_output
        tagged_exists = model_id in model_list_output

        if not base_exists and not tagged_exists:
            print(f"    [MISSING]  {model_base} — base model not found")
            errors.append(f"Run: docker model pull {model_base}")
            continue

        # Parse current context size from model list output
        current_ctx = None
        for line in model_list_output.split("\n"):
            if model_id in line:
                # Parse context column from docker model list output
                parts = line.split()
                for p in parts:
                    try:
                        val = int(p)
                        if val >= 1024:  # context sizes are >= 1024
                            current_ctx = val
                    except ValueError:
                        continue

        if current_ctx == target_ctx:
            print(f"    [READY]    {model_id} — context-size={current_ctx}")
        else:
            # Use docker model package to create variant with correct context
            # (docker model configure is broken — llama.cpp ignores stored values)
            print(f"    [PACKAGE]  {model_id} — packaging with context-size={target_ctx} from {model_base}")
            try:
                result = subprocess.run(
                    ["docker", "model", "package",
                     "--from", model_base,
                     "--context-size", str(target_ctx),
                     model_id],
                    capture_output=True, text=True, timeout=120
                )
                if result.returncode == 0:
                    print(f"    [READY]    {model_id} — context-size={target_ctx}")
                else:
                    print(f"    [ERROR]    {model_id} — package failed: {result.stderr.strip()}")
                    errors.append(f"Run: docker model package --from {model_base} --context-size {target_ctx} {model_id}")
            except Exception as e:
                print(f"    [ERROR]    {model_id} — package failed: {e}")
                errors.append(f"Run: docker model package --from {model_base} --context-size {target_ctx} {model_id}")

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
