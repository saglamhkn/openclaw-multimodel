#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== OpenClaw Multi-Model Setup ==="
echo ""

# Copy .env if not exists
if [ ! -f "$PROJECT_DIR/.env" ]; then
  cp "$PROJECT_DIR/.env.example" "$PROJECT_DIR/.env"
  echo "Created .env from .env.example - edit it with your API keys."
fi

# Source .env
source "$PROJECT_DIR/.env"

# Set default provider if not configured
PROVIDER="${ACTIVE_PROVIDER:-ollama}"
echo "Active provider: $PROVIDER"

# Switch to the configured provider
bash "$SCRIPT_DIR/switch-provider.sh" "$PROVIDER"

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Next steps:"
echo "  1. Edit .env with your API keys (for gemini/claude)"
echo "  2. Start services:  docker compose up -d"
echo "  3. Pull Ollama model: docker exec openclaw-ollama ollama pull llama3.3"
echo "  4. Open gateway:  http://localhost:18789"
echo "  5. Switch provider: ./scripts/switch-provider.sh <ollama|gemini|claude>"
