# OpenClaw Multi-Model

Run [OpenClaw](https://github.com/openclaw/openclaw) with your choice of LLM provider: **Docker Model Runner** (local GPU), **Google Gemini**, **Anthropic Claude**, or **Ollama**. Supports **MCP (Model Context Protocol)** for tool use (GitHub, filesystem, etc.).

Everything is controlled from a single config file: `openclaw.config.json`.

> **Full setup guide:** See [docs/SETUP.md](docs/SETUP.md) for step-by-step instructions per provider including API key setup, model selection, and troubleshooting.

## Quick Start

```bash
git clone https://github.com/saglamhkn/openclaw-multimodel.git
cd openclaw-multimodel
./scripts/setup.sh
```

Edit `openclaw.config.json` — configure your environments:

```json
{
  "environments": {
    "dev": {
      "models": {
        "primary": "docker-model-runner/ai/qwen3-coder",
        "fallback": []
      },
      "docker-model-runner": {
        "context-size": 32768,
        "keep-alive": -1
      }
    },
    "beta": {
      "models": {
        "primary": "google/gemini-2.5-flash",
        "fallback": ["google/gemini-2.5-pro"]
      }
    },
    "prod": {
      "models": {
        "primary": "google/gemini-2.5-flash",
        "fallback": ["google/gemini-2.5-pro"]
      }
    }
  },
  "keys": {
    "gemini": "your-key-here",
    "anthropic": ""
  }
}
```

Then generate and start:

```bash
./scripts/generate-config.sh
./scripts/init-models.sh dev
COMPOSE_PROFILES=dev docker compose up -d
```

## Environments

| Environment | Profile | Provider | Deployment |
|-------------|---------|----------|------------|
| dev | `COMPOSE_PROFILES=dev` | Docker Model Runner (local GPU) | Mac / local |
| beta | `COMPOSE_PROFILES=beta` | Google Gemini | DigitalOcean |
| prod | `COMPOSE_PROFILES=prod` | Google Gemini | DigitalOcean |

Start any environment:

```bash
COMPOSE_PROFILES=dev docker compose up -d    # local dev
COMPOSE_PROFILES=beta docker compose up -d   # beta
COMPOSE_PROFILES=prod docker compose up -d   # production
```

## Configuration

Everything lives in `openclaw.config.json`. Shared settings (`keys`, `gateway`, `openclaw`, `telegram`) apply to all environments. Per-environment model settings go inside `environments.<env>`.

After any change, regenerate and restart:

```bash
./scripts/generate-config.sh
COMPOSE_PROFILES=dev docker compose up -d
```

The script produces `.env.<env>` files (for docker-compose) and `configs/active/<env>/openclaw.json` (for OpenClaw runtime) for each environment.

## Model Initialization

Check model readiness for any environment:

```bash
./scripts/init-models.sh dev    # check dev models
./scripts/init-models.sh beta   # check beta models
./scripts/init-models.sh prod   # check prod models
```

This script automatically:
- **Docker Model Runner**: checks model exists, configures context-size, unloads stale models
- **Google/Anthropic**: validates API keys are set
- **Ollama**: checks if models are pulled, offers to download missing ones

## MCP Servers (Tool Use)

Give your LLM access to external tools like GitHub via MCP. Supports Docker containers (local dev), stdio subprocesses (production), and remote SSE endpoints.

```json
{
  "environments": {
    "dev": {
      "mcp": {
        "servers": {
          "github": {
            "enabled": true,
            "type": "docker",
            "image": "ghcr.io/github/github-mcp-server",
            "env": { "GITHUB_PERSONAL_ACCESS_TOKEN": "${keys.github}" }
          }
        }
      }
    }
  },
  "keys": { "github": "ghp_your-token" }
}
```

```bash
./scripts/generate-config.sh
COMPOSE_PROFILES=dev,mcp docker compose up -d
./scripts/test-mcp.sh dev
```

See [docs/SETUP.md](docs/SETUP.md) for full MCP setup including production (stdio) and remote (SSE) configurations.

## Telegram Bot

Chat with ClawBot via Telegram — uses OpenClaw's built-in Telegram channel (grammY).

1. Create a bot with [@BotFather](https://t.me/BotFather) on Telegram
2. Add to `openclaw.config.json`: `"telegram": { "enabled": true, "token": "123456:ABC-DEF..." }`
3. Regenerate and start: `./scripts/generate-config.sh && COMPOSE_PROFILES=dev docker compose up -d`

## Testing

```bash
./scripts/test-provider.sh dev    # test dev provider connectivity
./scripts/test-provider.sh beta   # test beta
./scripts/test-mcp.sh dev         # test MCP server connectivity
```

## Devcontainer (VSCode)

1. Open this folder in VSCode
2. Press `Ctrl+Shift+P` > "Dev Containers: Reopen in Container"
3. Services start automatically based on your config

## Project Structure

```
.
├── .devcontainer/                  # VSCode devcontainer config
├── configs/active/                 # Generated runtime configs (gitignored)
│   ├── dev/openclaw.json
│   ├── beta/openclaw.json
│   └── prod/openclaw.json
├── scripts/
│   ├── setup.sh                    # Initial project setup
│   ├── generate-config.sh          # Generate per-env configs
│   ├── init-models.sh              # Universal model readiness + auto-configure
│   ├── test-provider.sh            # Test provider connectivity
│   └── test-mcp.sh                 # Test MCP server connectivity
├── openclaw.config.example.json    # Config template (committed)
├── openclaw.config.json            # Your config (gitignored, has API keys)
├── docker-compose.yml              # All services with dev/beta/prod profiles
└── README.md
```

## Provider Details

| Provider | API Key | Cost | Best For |
|----------|---------|------|----------|
| Docker Model Runner | No | Free | Local GPU inference (Mac Metal) |
| Ollama   | No      | Free | Privacy, offline, experimentation |
| Gemini   | `keys.gemini` | Pay per token | Fast responses, large context |
| Claude   | `keys.anthropic` | Pay per token | Complex reasoning, code generation |

## Requirements

- Docker & Docker Compose v2
- Docker Desktop with Model Runner (for local GPU inference)
- API keys for cloud providers (Gemini/Claude)
