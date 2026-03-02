# Setup Guide

Step-by-step instructions for setting up OpenClaw with your preferred LLM provider.

---

## Prerequisites

Before you begin, make sure you have:

- **Docker Desktop** (Mac/Windows) or **Docker Engine + Compose v2** (Linux)
- **4GB+ RAM** available (8GB recommended if running local models)
- **Git** installed

```bash
# Verify Docker is installed
docker --version
docker compose version
```

---

## Step 1: Clone and Configure

```bash
git clone https://github.com/saglamhkn/openclaw-multimodel.git
cd openclaw-multimodel
cp .env.example .env
```

Now open `.env` in your editor. The only required change is picking your provider — follow **one** of the three guides below.

---

## Option A: Local Models with Ollama (Free, Private, No API Key)

Best if you want full privacy, no cloud dependency, and zero cost. Runs entirely on your machine.

### 1. Configure `.env`

```bash
ACTIVE_PROVIDER=ollama
OLLAMA_MODEL=llama3.3
```

That's it — no API key needed.

### 2. Start Services

```bash
./scripts/setup.sh
docker compose up -d
```

### 3. Pull a Model

The Ollama container starts empty. You need to pull at least one model:

```bash
# Recommended general-purpose model
docker exec openclaw-ollama ollama pull llama3.3

# Or for coding tasks
docker exec openclaw-ollama ollama pull qwen2.5-coder:32b

# Or pull all preconfigured models at once
./scripts/pull-ollama-models.sh
```

### 4. Verify

```bash
# Check Ollama is running and has models
curl http://localhost:11434/api/tags

# Check OpenClaw gateway
curl http://localhost:18789/healthz
```

### Available Ollama Models

| Model | Size | Best For |
|-------|------|----------|
| `llama3.3` | ~4GB | General purpose, good balance |
| `qwen2.5-coder:32b` | ~18GB | Code generation, debugging |
| `deepseek-r1:14b` | ~9GB | Reasoning, complex tasks |

To use a different model, edit `configs/ollama.json`:

```json
{
  "agents": {
    "defaults": {
      "model": {
        "primary": "ollama/YOUR_MODEL_NAME"
      }
    }
  }
}
```

Then restart: `docker compose restart openclaw-gateway`

### Hardware Requirements

| Model Size | RAM Needed | GPU Recommended |
|-----------|------------|-----------------|
| 7B params | 8GB | No (CPU ok, slower) |
| 14B params | 16GB | Yes |
| 32B params | 32GB | Yes (NVIDIA) |

---

## Option B: Google Gemini API

Best if you want fast responses, large context windows, and Google's latest models.

### 1. Get Your API Key

1. Go to [Google AI Studio](https://aistudio.google.com/apikey)
2. Sign in with your Google account
3. Click **"Create API Key"**
4. Copy the key (starts with `AIza...`)

### 2. Configure `.env`

```bash
ACTIVE_PROVIDER=gemini
GEMINI_API_KEY=AIzaSy...your-key-here
GEMINI_MODEL=gemini-2.5-flash
```

### 3. Start Services

```bash
./scripts/setup.sh
docker compose up -d
```

### 4. Verify

```bash
./scripts/test-provider.sh
```

You should see:

```
Gemini:  KEY CONFIGURED
```

### Available Gemini Models

| Model | Speed | Context | Best For |
|-------|-------|---------|----------|
| `gemini-2.5-flash` | Fast | 1M tokens | Quick tasks, large documents |
| `gemini-2.5-pro` | Slower | 1M tokens | Complex reasoning |

To change the model, edit `configs/gemini.json`:

```json
{
  "agents": {
    "defaults": {
      "model": {
        "primary": "google/gemini-2.5-pro"
      }
    }
  }
}
```

### Pricing

Gemini offers a free tier with rate limits. Check [Google AI pricing](https://ai.google.dev/pricing) for current rates.

---

## Option C: Anthropic Claude API

Best if you want strong reasoning, excellent code generation, and nuanced responses.

### 1. Get Your API Key

1. Go to [Anthropic Console](https://console.anthropic.com/)
2. Create an account or sign in
3. Navigate to **API Keys**
4. Click **"Create Key"**
5. Copy the key (starts with `sk-ant-...`)

### 2. Configure `.env`

```bash
ACTIVE_PROVIDER=claude
ANTHROPIC_API_KEY=sk-ant-...your-key-here
CLAUDE_MODEL=claude-sonnet-4-5
```

### 3. Start Services

```bash
./scripts/setup.sh
docker compose up -d
```

### 4. Verify

```bash
./scripts/test-provider.sh
```

You should see:

```
Claude:  KEY CONFIGURED
```

### Available Claude Models

| Model | Speed | Best For |
|-------|-------|----------|
| `claude-sonnet-4-5` | Balanced | General use, coding, analysis |
| `claude-haiku-4-5` | Fast | Quick tasks, lower cost |
| `claude-opus-4-6` | Slower | Complex reasoning, research |

To change the model, edit `configs/claude.json`:

```json
{
  "agents": {
    "defaults": {
      "model": {
        "primary": "anthropic/claude-opus-4-6"
      }
    }
  }
}
```

### Pricing

Claude requires a funded account. Check [Anthropic pricing](https://www.anthropic.com/pricing) for current rates.

---

## Switching Between Providers

You can switch providers at any time without losing data:

```bash
# Switch to Ollama
./scripts/switch-provider.sh ollama

# Switch to Gemini
./scripts/switch-provider.sh gemini

# Switch to Claude
./scripts/switch-provider.sh claude

# Restart to apply the change
docker compose restart openclaw-gateway
```

The switch script copies the matching config file to `configs/active/openclaw.json`, which is what OpenClaw reads at startup.

---

## Testing All Providers

Run the test script to see which providers are available:

```bash
./scripts/test-provider.sh
```

Example output:

```
=== Provider Status ===
  Ollama:  AVAILABLE
  Gemini:  KEY CONFIGURED
  Claude:  NO API KEY
```

---

## Using the Devcontainer (VSCode)

If you prefer developing inside a container:

1. Install the **Dev Containers** extension in VSCode
2. Open the `openclaw-multimodel` folder
3. Press `Ctrl+Shift+P` (or `Cmd+Shift+P` on Mac)
4. Select **"Dev Containers: Reopen in Container"**
5. Wait for the build — Ollama and OpenClaw start automatically
6. Open `http://localhost:18789` in your browser

The devcontainer forwards ports 18789 (OpenClaw) and 11434 (Ollama) to your host.

---

## Accessing the OpenClaw Gateway

Once running, open your browser:

```
http://localhost:18789
```

You'll need the gateway token from your `.env` file:

```bash
# Default token (change this in production!)
OPENCLAW_GATEWAY_TOKEN=changeme-generate-a-real-token
```

Generate a secure token:

```bash
openssl rand -hex 32
```

---

## Troubleshooting

### OpenClaw gateway won't start

```bash
# Check logs
docker compose logs openclaw-gateway

# Verify config is valid JSON
python3 -m json.tool configs/active/openclaw.json
```

### Ollama model runs out of memory

Use a smaller model:

```bash
docker exec openclaw-ollama ollama pull llama3.2:3b
```

Then update `configs/ollama.json` to use `ollama/llama3.2:3b`.

### API key errors (Gemini/Claude)

1. Check your `.env` file has the key with no extra spaces
2. Verify the key works directly:

```bash
# Test Gemini key
curl "https://generativelanguage.googleapis.com/v1beta/models?key=$GEMINI_API_KEY"

# Test Claude key
curl https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d '{"model":"claude-haiku-4-5","max_tokens":10,"messages":[{"role":"user","content":"hi"}]}'
```

### Container can't reach Ollama

Inside Docker, the Ollama service is at `http://ollama:11434` (not `localhost`). This is already configured in `configs/ollama.json`. If you changed it, make sure it uses the Docker service name.

### Ports already in use

```bash
# Check what's using the ports
lsof -i :18789
lsof -i :11434

# Or change ports in docker-compose.yml
ports:
  - "19000:18789"  # map to different host port
```
