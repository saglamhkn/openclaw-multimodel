#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$PROJECT_DIR/openclaw.config.json"
ENV="${1:-dev}"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Warning: openclaw.config.json not found, using defaults"
  GATEWAY_PORT=18789
else
  eval "$(python3 -c "
import json
with open('$CONFIG_FILE') as f:
    cfg = json.load(f)
print(f'GATEWAY_PORT={cfg.get(\"gateway\", {}).get(\"port\", 18789)}')
print(f'GEMINI_API_KEY=\"{cfg.get(\"keys\", {}).get(\"gemini\", \"\")}\"')
print(f'ANTHROPIC_API_KEY=\"{cfg.get(\"keys\", {}).get(\"anthropic\", \"\")}\"')
" 2>/dev/null)"
fi

GATEWAY="http://localhost:${GATEWAY_PORT}"

echo "=== OpenClaw Provider Test [$ENV] ==="
echo ""

# Check gateway health
echo "1. Checking gateway health..."
if curl -fsS "$GATEWAY/healthz" > /dev/null 2>&1; then
  echo "   Gateway: OK"
else
  echo "   Gateway: UNREACHABLE"
  echo "   Run: COMPOSE_PROFILES=$ENV docker compose up -d"
fi

# Check active config
echo "2. Active configuration:"
ACTIVE_CONFIG="$PROJECT_DIR/configs/active/$ENV/openclaw.json"
if [ -f "$ACTIVE_CONFIG" ]; then
  PRIMARY=$(python3 -c "
import json
with open('$ACTIVE_CONFIG') as f:
    c = json.load(f)
print(c.get('agents',{}).get('defaults',{}).get('model',{}).get('primary','unknown'))
" 2>/dev/null || echo "unknown")
  echo "   Primary model: $PRIMARY"
else
  echo "   No active config for '$ENV'. Run: ./scripts/generate-config.sh"
fi

echo ""
echo "=== Provider Status ==="

# Docker Model Runner
echo -n "  Docker Model Runner: "
if docker model list >/dev/null 2>&1; then
  echo "AVAILABLE"
  docker model list 2>/dev/null | head -10
else
  echo "NOT AVAILABLE (requires Docker Desktop with model runner)"
fi

# Gemini
echo -n "  Gemini:              "
if [ -n "${GEMINI_API_KEY:-}" ]; then
  echo "KEY CONFIGURED"
else
  echo "NO API KEY"
fi

# Claude
echo -n "  Claude:              "
if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
  echo "KEY CONFIGURED"
else
  echo "NO API KEY"
fi

# Ollama
echo -n "  Ollama:              "
if curl -fsS "http://localhost:11434/api/tags" > /dev/null 2>&1; then
  echo "AVAILABLE"
else
  echo "NOT RUNNING"
fi

echo ""
echo "Run ./scripts/init-models.sh $ENV for detailed model readiness check"
