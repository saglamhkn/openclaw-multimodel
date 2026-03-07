# Setup Guide

Step-by-step instructions for setting up OpenClaw with your preferred LLM provider.

---

## Prerequisites

- **Docker Desktop** (Mac/Windows) or **Docker Engine + Compose v2** (Linux)
- **4GB+ RAM** (only if using Ollama with local models; cloud providers need minimal RAM)
- **Git** installed

```bash
docker --version
docker compose version
```

---

## Step 1: Clone and Setup

```bash
git clone https://github.com/saglamhkn/openclaw-multimodel.git
cd openclaw-multimodel
./scripts/setup.sh
```

This creates `openclaw.config.json` from the example. Now edit it for your provider — follow **one** of the options below.

---

## Option A: Local Models with Ollama (Free, Private)

Best for full privacy, no cloud dependency, and zero cost.

### 1. Edit `openclaw.config.json`

```json
{
  "models": {
    "primary": "ollama/llama3.3",
    "fallback": ["ollama/qwen2.5-coder:32b", "ollama/deepseek-r1:14b"]
  },
  "ollama": {
    "enabled": true,
    "memory": "4g"
  }
}
```

No API keys needed.

### 2. Generate and Start

```bash
./scripts/generate-config.sh
docker compose up -d
```

### 3. Pull a Model

```bash
docker exec openclaw-ollama ollama pull llama3.3

# Or pull all preconfigured models
./scripts/pull-ollama-models.sh
```

### 4. Verify

```bash
curl http://localhost:11434/api/tags
curl http://localhost:18789/healthz
```

### Available Ollama Models

| Model | Size | Best For |
|-------|------|----------|
| `llama3.2:3b` | ~2GB | Low-resource servers |
| `llama3.3` | ~4GB | General purpose |
| `qwen2.5-coder:32b` | ~18GB | Code generation |
| `deepseek-r1:14b` | ~9GB | Reasoning |

### Adapting to Server Power

Adjust `ollama.memory` based on your hardware:

| Model Size | Config Memory | Server RAM |
|-----------|---------------|------------|
| 3B params | `"2g"` | 4GB+ |
| 7B params | `"4g"` | 8GB+ |
| 14B params | `"8g"` | 16GB+ |
| 32B params | `"16g"` | 32GB+ |

---

## Option B: Google Gemini API (No Ollama)

Best for fast responses and large context windows. Ollama does not start.

### 1. Get Your API Key

1. Go to [Google AI Studio](https://aistudio.google.com/apikey)
2. Sign in and click **"Create API Key"**
3. Copy the key (starts with `AIza...`)

### 2. Edit `openclaw.config.json`

```json
{
  "models": {
    "primary": "google/gemini-2.5-flash",
    "fallback": ["google/gemini-2.5-pro"]
  },
  "keys": {
    "gemini": "AIzaSy...your-key-here"
  }
}
```

### 3. Generate and Start

```bash
./scripts/generate-config.sh
docker compose up -d
```

### 4. Verify

```bash
./scripts/test-provider.sh
```

### Available Gemini Models

| Model | Speed | Context | Best For |
|-------|-------|---------|----------|
| `gemini-2.5-flash` | Fast | 1M tokens | Quick tasks, large documents |
| `gemini-2.5-pro` | Slower | 1M tokens | Complex reasoning |

### Pricing

Gemini offers a free tier with rate limits. Check [Google AI pricing](https://ai.google.dev/pricing) for current rates.

---

## Option C: Anthropic Claude API (No Ollama)

Best for strong reasoning, code generation, and nuanced responses. Ollama does not start.

### 1. Get Your API Key

1. Go to [Anthropic Console](https://console.anthropic.com/)
2. Navigate to **API Keys** and click **"Create Key"**
3. Copy the key (starts with `sk-ant-...`)

### 2. Edit `openclaw.config.json`

```json
{
  "models": {
    "primary": "anthropic/claude-sonnet-4-5",
    "fallback": ["anthropic/claude-haiku-4-5"]
  },
  "keys": {
    "anthropic": "sk-ant-...your-key-here"
  }
}
```

### 3. Generate and Start

```bash
./scripts/generate-config.sh
docker compose up -d
```

### 4. Verify

```bash
./scripts/test-provider.sh
```

### Available Claude Models

| Model | Speed | Best For |
|-------|-------|----------|
| `claude-sonnet-4-5` | Balanced | General use, coding, analysis |
| `claude-haiku-4-5` | Fast | Quick tasks, lower cost |
| `claude-opus-4-6` | Slower | Complex reasoning, research |

### Pricing

Claude requires a funded account. Check [Anthropic pricing](https://www.anthropic.com/pricing) for current rates.

---

## Option D: MCP Servers (Tool Use)

MCP (Model Context Protocol) lets your LLM use external tools like GitHub, filesystem access, and more. This turns text-only chat into an agentic workflow where the model can read repos, create issues, search code, etc.

MCP servers are configured per environment, supporting three transport types:

| Type | Use Case | How It Works |
|------|----------|--------------|
| `docker` | Local dev (macOS with Docker Desktop) | MCP server runs as a Docker container |
| `stdio` | Production / non-Docker environments | MCP server runs as a subprocess (e.g., `npx`) |
| `sse` | Remote MCP endpoint | Connects to an external SSE URL |

### Local Dev: Docker MCP (GitHub)

#### 1. Get a GitHub Personal Access Token

1. Go to [GitHub Settings > Developer settings > Personal access tokens](https://github.com/settings/tokens)
2. Click **"Generate new token (classic)"**
3. Select scopes: `repo`, `read:org`, `read:user`
4. Copy the token

#### 2. Edit `openclaw.config.json`

```json
{
  "environments": {
    "dev": {
      "models": { "primary": "docker-model-runner/ai/qwen3-coder" },
      "mcp": {
        "servers": {
          "github": {
            "enabled": true,
            "type": "docker",
            "image": "ghcr.io/github/github-mcp-server",
            "env": {
              "GITHUB_PERSONAL_ACCESS_TOKEN": "${keys.github}"
            }
          }
        }
      }
    }
  },
  "keys": {
    "github": "ghp_xxxxxxxxxxxx"
  }
}
```

The `${keys.github}` reference is resolved at generation time from the `keys` block.

#### 3. Generate and Start

```bash
./scripts/generate-config.sh
COMPOSE_PROFILES=dev,mcp docker compose up -d
```

#### 4. Verify

```bash
./scripts/test-mcp.sh dev
```

### Production: stdio MCP (GitHub)

For production or non-Docker environments, use `stdio` type which runs MCP servers as subprocesses:

```json
{
  "environments": {
    "prod": {
      "mcp": {
        "servers": {
          "github": {
            "enabled": true,
            "type": "stdio",
            "command": "npx",
            "args": ["-y", "@modelcontextprotocol/server-github"],
            "env": {
              "GITHUB_PERSONAL_ACCESS_TOKEN": "${keys.github}"
            }
          }
        }
      }
    }
  }
}
```

Requires Node.js/npm on the production host.

### Remote: SSE MCP

For connecting to a hosted MCP endpoint:

```json
{
  "mcp": {
    "servers": {
      "github": {
        "enabled": true,
        "type": "sse",
        "url": "https://mcp-proxy.example.com/github/sse"
      }
    }
  }
}
```

### MCP Server Config Reference

| Field | Required | Description |
|-------|----------|-------------|
| `enabled` | yes | Toggle this server on/off |
| `type` | yes | `docker`, `stdio`, or `sse` |
| `image` | docker | Docker image for the MCP server |
| `command` | stdio | Command to run (e.g., `npx`) |
| `args` | stdio | Array of command arguments |
| `url` | sse | Full SSE endpoint URL |
| `env` | optional | Environment variables; supports `${keys.XYZ}` interpolation |

---

## Changing Configuration

After editing `openclaw.config.json`, always regenerate and restart:

```bash
./scripts/generate-config.sh
docker compose up -d
```

This produces `.env` (for docker-compose) and `configs/active/openclaw.json` (for OpenClaw runtime).

---

## Telegram Bot

Chat with ClawBot via Telegram. Supports text messages, photos, and voice notes.

### 1. Create a Telegram Bot

1. Open Telegram and message [@BotFather](https://t.me/BotFather)
2. Send `/newbot` and follow the prompts
3. Copy the bot token (format: `123456:ABC-DEF...`)

### 2. Configure

Edit `openclaw.config.json`:

```json
{
  "telegram": {
    "enabled": true,
    "token": "123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11"
  }
}
```

### 3. Start

```bash
./scripts/generate-config.sh
docker compose up -d
```

The bot auto-enables the OpenClaw Chat Completions API endpoint and starts the `clawbot-telegram` container.

### Features

- **Text** — sends your message to OpenClaw, returns the AI response
- **Photos** — downloads the image and sends it as a multimodal vision request
- **Voice** — downloads the audio and forwards it to the LLM
- **Conversation memory** — maintains per-chat history (resets on container restart)
- **Commands** — `/start` (intro), `/clear` (reset history)

---

## Full Config Reference

```json
{
  "models": {
    "primary": "google/gemini-2.5-flash",
    "fallback": ["google/gemini-2.5-pro"]
  },
  "keys": {
    "gemini": "",
    "anthropic": "",
    "github": ""
  },
  "ollama": {
    "enabled": false,
    "memory": "4g",
    "image": "ollama/ollama:latest",
    "port": 11434
  },
  "gateway": {
    "token": "changeme-generate-a-real-token",
    "port": 18789
  },
  "openclaw": {
    "image": "ghcr.io/openclaw/openclaw:latest"
  },
  "telegram": {
    "enabled": false,
    "token": ""
  }
}
```

| Field | Description |
|-------|-------------|
| `models.primary` | Main model in `provider/model` format |
| `models.fallback` | Array of fallback models |
| `keys.gemini` | Google Gemini API key |
| `keys.anthropic` | Anthropic Claude API key |
| `keys.github` | GitHub Personal Access Token (for MCP) |
| `ollama.enabled` | Start Ollama service (auto-enabled if models use `ollama/`) |
| `ollama.memory` | Docker memory reservation for Ollama |
| `ollama.image` | Ollama Docker image |
| `ollama.port` | Ollama API port |
| `gateway.token` | OpenClaw gateway auth token |
| `gateway.port` | OpenClaw gateway port |
| `openclaw.image` | OpenClaw Docker image |
| `telegram.enabled` | Start the Telegram bot service |
| `telegram.token` | Telegram Bot API token from @BotFather |

---

## Using the Devcontainer (VSCode)

1. Install the **Dev Containers** extension in VSCode
2. Open the `openclaw-multimodel` folder
3. Press `Ctrl+Shift+P` > **"Dev Containers: Reopen in Container"**
4. Services start automatically based on your config
5. Open `http://localhost:18789` in your browser

---

## Accessing the OpenClaw Gateway

```
http://localhost:18789
```

You'll need the gateway token from `openclaw.config.json`:

```json
{ "gateway": { "token": "your-token-here" } }
```

Generate a secure token:

```bash
openssl rand -hex 32
```

---

## Troubleshooting

### OpenClaw gateway won't start

```bash
docker compose logs openclaw-gateway
python3 -m json.tool configs/active/openclaw.json
```

### Ollama model runs out of memory

Use a smaller model and reduce memory in config:

```json
{ "models": { "primary": "ollama/llama3.2:3b" }, "ollama": { "memory": "2g" } }
```

### API key errors (Gemini/Claude)

Check your `openclaw.config.json` has the key with no extra spaces:

```bash
# Test Gemini key
source .env && curl "https://generativelanguage.googleapis.com/v1beta/models?key=$GEMINI_API_KEY"

# Test Claude key
source .env && curl https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d '{"model":"claude-haiku-4-5","max_tokens":10,"messages":[{"role":"user","content":"hi"}]}'
```

### Container can't reach Ollama

Inside Docker, Ollama is at `http://ollama:11434` (not `localhost`). This is auto-configured by `generate-config.sh`.

### Ports already in use

Change ports in `openclaw.config.json`:

```json
{ "gateway": { "port": 19000 }, "ollama": { "port": 12434 } }
```

Then regenerate: `./scripts/generate-config.sh`
