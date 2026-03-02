# OpenClaw Multi-Model

Run [OpenClaw](https://github.com/openclaw/openclaw) with switchable LLM providers: **Ollama** (local), **Google Gemini**, or **Anthropic Claude**.

Includes a devcontainer for one-click local development.

## Quick Start

```bash
# 1. Clone and enter the project
git clone https://github.com/hakansaglam/openclaw-multimodel.git
cd openclaw-multimodel

# 2. Copy env and add your API keys
cp .env.example .env
# Edit .env with your keys

# 3. Run setup
./scripts/setup.sh

# 4. Start services
docker compose up -d

# 5. Pull a local model (for Ollama provider)
docker exec openclaw-ollama ollama pull llama3.3

# 6. Open the gateway
open http://localhost:18789
```

## Switching Providers

```bash
# Switch to local Ollama
./scripts/switch-provider.sh ollama

# Switch to Google Gemini
./scripts/switch-provider.sh gemini

# Switch to Anthropic Claude
./scripts/switch-provider.sh claude

# Restart to apply
docker compose restart openclaw-gateway
```

## Testing

```bash
# Check all provider statuses
./scripts/test-provider.sh

# Pull all preconfigured Ollama models
./scripts/pull-ollama-models.sh
```

## Devcontainer (VSCode)

1. Open this folder in VSCode
2. Press `Ctrl+Shift+P` > "Dev Containers: Reopen in Container"
3. Everything starts automatically (Ollama + OpenClaw)

## Project Structure

```
.
├── .devcontainer/          # VSCode devcontainer config
│   └── devcontainer.json
├── configs/                # Provider configurations
│   ├── ollama.json         # Ollama (local) config
│   ├── gemini.json         # Google Gemini config
│   ├── claude.json         # Anthropic Claude config
│   └── active/             # Currently active config (gitignored)
├── scripts/
│   ├── setup.sh            # Initial project setup
│   ├── switch-provider.sh  # Switch between providers
│   ├── test-provider.sh    # Test provider connectivity
│   └── pull-ollama-models.sh # Download Ollama models
├── docker-compose.yml      # All services
├── .env.example            # Environment template
└── README.md
```

## Provider Details

| Provider | API Key Required | Cost | Latency | Best For |
|----------|-----------------|------|---------|----------|
| Ollama   | No              | Free | Depends on hardware | Privacy, offline use, experimentation |
| Gemini   | Yes (`GEMINI_API_KEY`) | Pay per token | Low | Fast responses, large context |
| Claude   | Yes (`ANTHROPIC_API_KEY`) | Pay per token | Low | Complex reasoning, code generation |

## Configuration

Each provider config is a JSON file in `configs/`. The active config gets symlinked to `configs/active/openclaw.json` which is mounted into the OpenClaw container.

You can customize models by editing the JSON files. For example, to change the Ollama model:

```json
{
  "agents": {
    "defaults": {
      "model": {
        "primary": "ollama/your-model-name"
      }
    }
  }
}
```

## Requirements

- Docker & Docker Compose v2
- 4GB+ RAM (for Ollama with local models)
- API keys for cloud providers (Gemini/Claude)
