#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== OpenClaw Setup ==="
echo ""

# Copy config if not exists
if [ ! -f "$PROJECT_DIR/openclaw.config.json" ]; then
  cp "$PROJECT_DIR/openclaw.config.example.json" "$PROJECT_DIR/openclaw.config.json"
  echo "Created openclaw.config.json from example."
  echo "  Edit openclaw.config.json to set your models and API keys."
  echo ""
fi

# Generate all environment configs
bash "$SCRIPT_DIR/generate-config.sh"

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Next steps:"
echo "  1. Edit openclaw.config.json to configure models, keys, and environments"
echo "  2. Run: ./scripts/generate-config.sh  (after any config change)"
echo "  3. Check model readiness: ./scripts/init-models.sh [dev|beta|prod]"
echo "  4. Start services: COMPOSE_PROFILES=dev docker compose up -d"
echo ""
echo "Environments:"
echo "  dev   — COMPOSE_PROFILES=dev docker compose up -d"
echo "  beta  — COMPOSE_PROFILES=beta docker compose up -d"
echo "  prod  — COMPOSE_PROFILES=prod docker compose up -d"
echo ""
