#!/usr/bin/env bash
set -euo pipefail

echo "=== Pulling Ollama Models ==="
echo ""

MODELS=(
  "llama3.3"
  "qwen2.5-coder:32b"
  "deepseek-r1:14b"
)

for model in "${MODELS[@]}"; do
  echo "Pulling $model..."
  docker exec openclaw-ollama ollama pull "$model" || {
    echo "  Failed to pull $model (container may not be running)"
    echo "  Run: docker compose up -d ollama"
    exit 1
  }
  echo "  Done."
  echo ""
done

echo "=== All models pulled ==="
echo "Available models:"
docker exec openclaw-ollama ollama list
