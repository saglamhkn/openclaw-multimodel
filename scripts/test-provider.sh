#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Load .env
if [ -f "$PROJECT_DIR/.env" ]; then
  source "$PROJECT_DIR/.env"
fi

TOKEN="${OPENCLAW_GATEWAY_TOKEN:-changeme}"
GATEWAY="http://localhost:18789"

echo "=== OpenClaw Provider Test ==="
echo ""

# Check gateway health
echo "1. Checking gateway health..."
if curl -fsS "$GATEWAY/healthz" > /dev/null 2>&1; then
  echo "   Gateway: OK"
else
  echo "   Gateway: UNREACHABLE"
  echo "   Run: docker compose up -d"
  exit 1
fi

# Check Ollama health
echo "2. Checking Ollama..."
if curl -fsS "http://localhost:11434/api/tags" > /dev/null 2>&1; then
  MODELS=$(curl -s "http://localhost:11434/api/tags" | python3 -c "
import sys, json
data = json.load(sys.stdin)
models = [m['name'] for m in data.get('models', [])]
print(', '.join(models) if models else 'No models pulled')
" 2>/dev/null || echo "No models pulled")
  echo "   Ollama: OK (models: $MODELS)"
else
  echo "   Ollama: UNREACHABLE"
fi

# Show active config
echo "3. Active configuration:"
ACTIVE_CONFIG="$PROJECT_DIR/configs/active/openclaw.json"
if [ -f "$ACTIVE_CONFIG" ]; then
  PRIMARY=$(python3 -c "
import json
with open('$ACTIVE_CONFIG') as f:
    c = json.load(f)
print(c.get('agents',{}).get('defaults',{}).get('model',{}).get('primary','unknown'))
" 2>/dev/null || echo "unknown")
  echo "   Primary model: $PRIMARY"
else
  echo "   No active config. Run: ./scripts/switch-provider.sh <provider>"
fi

# Test all providers
echo ""
echo "=== Provider Status ==="

# Ollama
echo -n "  Ollama:  "
if curl -fsS "http://localhost:11434/api/tags" > /dev/null 2>&1; then
  echo "AVAILABLE"
else
  echo "NOT RUNNING"
fi

# Gemini
echo -n "  Gemini:  "
if [ -n "${GEMINI_API_KEY:-}" ]; then
  echo "KEY CONFIGURED"
else
  echo "NO API KEY"
fi

# Claude
echo -n "  Claude:  "
if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
  echo "KEY CONFIGURED"
else
  echo "NO API KEY"
fi

echo ""
echo "To switch providers: ./scripts/switch-provider.sh <ollama|gemini|claude>"
