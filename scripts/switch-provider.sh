#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIGS_DIR="$PROJECT_DIR/configs"
ACTIVE_DIR="$CONFIGS_DIR/active"

usage() {
  echo "Usage: $0 <provider>"
  echo ""
  echo "Providers:"
  echo "  ollama   - Use local Ollama models (no API key needed)"
  echo "  gemini   - Use Google Gemini API (requires GEMINI_API_KEY in .env)"
  echo "  claude   - Use Anthropic Claude API (requires ANTHROPIC_API_KEY in .env)"
  echo ""
  echo "Example: $0 ollama"
  exit 1
}

if [ $# -ne 1 ]; then
  usage
fi

PROVIDER="$1"
CONFIG_FILE="$CONFIGS_DIR/$PROVIDER.json"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: Unknown provider '$PROVIDER'"
  echo "Available: ollama, gemini, claude"
  exit 1
fi

# Load .env if present
if [ -f "$PROJECT_DIR/.env" ]; then
  source "$PROJECT_DIR/.env"
fi

# Validate API keys for cloud providers
if [ "$PROVIDER" = "gemini" ] && [ -z "${GEMINI_API_KEY:-}" ]; then
  echo "Warning: GEMINI_API_KEY is not set in .env"
  echo "Gemini provider requires an API key to function."
  read -p "Continue anyway? [y/N] " -n 1 -r
  echo
  [[ $REPLY =~ ^[Yy]$ ]] || exit 1
fi

if [ "$PROVIDER" = "claude" ] && [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  echo "Warning: ANTHROPIC_API_KEY is not set in .env"
  echo "Claude provider requires an API key to function."
  read -p "Continue anyway? [y/N] " -n 1 -r
  echo
  [[ $REPLY =~ ^[Yy]$ ]] || exit 1
fi

# Create active config directory and copy config
mkdir -p "$ACTIVE_DIR"
cp "$CONFIG_FILE" "$ACTIVE_DIR/openclaw.json"

echo "Switched to provider: $PROVIDER"
echo "Config: $CONFIG_FILE -> $ACTIVE_DIR/openclaw.json"
echo ""
echo "To apply changes, restart OpenClaw:"
echo "  docker compose restart openclaw-gateway"
