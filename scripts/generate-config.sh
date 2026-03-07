#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
export CONFIG_FILE="$PROJECT_DIR/openclaw.config.json"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: openclaw.config.json not found."
  echo "  Run ./scripts/setup.sh or copy openclaw.config.example.json to openclaw.config.json"
  exit 1
fi

# Generate .env.<env> and configs/active/<env>/openclaw.json for each environment
python3 << 'PYEOF'
import json, os, sys, shutil, re

project_dir = os.environ["PROJECT_DIR"]
config_path = os.environ["CONFIG_FILE"]

with open(config_path) as f:
    cfg = json.load(f)

environments = cfg.get("environments", {})
if not environments:
    print("Error: no 'environments' defined in openclaw.config.json")
    sys.exit(1)

# Shared settings
keys = cfg.get("keys", {})
gemini_key = keys.get("gemini", "")
anthropic_key = keys.get("anthropic", "")
github_key = keys.get("github", "")

def interpolate_env(env_dict):
    """Replace ${keys.foo} references with actual key values."""
    result = {}
    for k, v in env_dict.items():
        if isinstance(v, str):
            def replacer(m):
                return keys.get(m.group(1), "")
            result[k] = re.sub(r'\$\{keys\.([^}]+)\}', replacer, v)
        else:
            result[k] = v
    return result

gateway = cfg.get("gateway", {})
gateway_token = gateway.get("token", "changeme")
gateway_port = gateway.get("port", 18789)

openclaw_cfg = cfg.get("openclaw", {})
openclaw_image = openclaw_cfg.get("image", "ghcr.io/openclaw/openclaw:latest")

telegram = cfg.get("telegram", {})
telegram_enabled = telegram.get("enabled", False)
telegram_token = telegram.get("token", "")

if telegram_enabled and not telegram_token:
    print("Warning: telegram.enabled is true but telegram.token is empty")

skills_global = cfg.get("skills", {})
skills_install_dir = skills_global.get("installDir", "workspace")

agent_global = cfg.get("agent", {})
agent_timeout = agent_global.get("timeoutSeconds", 300)
agent_typing_interval = agent_global.get("typingIntervalSeconds", 300)

for env_name, env_cfg in environments.items():
    models = env_cfg.get("models", {})
    primary = models.get("primary", "")
    fallback = models.get("fallback", [])
    if isinstance(fallback, str):
        fallback = [fallback]

    if not primary:
        print(f"Warning: environments.{env_name}.models.primary is empty, skipping")
        continue

    # Validate provider prefix
    provider = primary.split("/")[0]
    valid_providers = ("ollama", "google", "anthropic", "docker-model-runner")
    if provider not in valid_providers:
        print(f"Error: environments.{env_name}.models.primary must start with one of: {', '.join(valid_providers)}")
        print(f"  Got: {primary}")
        sys.exit(1)

    # Warn about missing keys
    if provider == "google" and not gemini_key:
        print(f"Warning: [{env_name}] uses Google but keys.gemini is empty")
    if provider == "anthropic" and not anthropic_key:
        print(f"Warning: [{env_name}] uses Anthropic but keys.anthropic is empty")

    all_models = [primary] + fallback

    # Check provider usage
    models_use_dmr = any(m.startswith("docker-model-runner/") for m in all_models)
    models_use_ollama = any(m.startswith("ollama/") for m in all_models)
    ollama_env = env_cfg.get("ollama", {})
    ollama_mode = ollama_env.get("mode", "native")
    ollama_port = ollama_env.get("port", 11434)
    ollama_image = ollama_env.get("image", "ollama/ollama:latest")
    ollama_memory = ollama_env.get("memory", "4g")
    ollama_is_native = ollama_mode == "native"

    # --- Generate .env.<env> ---
    env_lines = [
        f"# AUTO-GENERATED for '{env_name}' — DO NOT EDIT",
        f"# Edit openclaw.config.json and run ./scripts/generate-config.sh",
        "",
        f"OPENCLAW_IMAGE={openclaw_image}",
        f"OPENCLAW_GATEWAY_TOKEN={gateway_token}",
        f"GATEWAY_PORT={gateway_port}",
        "",
        f"GEMINI_API_KEY={gemini_key}",
        f"ANTHROPIC_API_KEY={anthropic_key}",
        "",
        f"OLLAMA_IMAGE={ollama_image}",
        f"OLLAMA_MEMORY={ollama_memory}",
        f"OLLAMA_PORT={ollama_port}",
        "",
    ]

    # MCP servers
    mcp_cfg = env_cfg.get("mcp", {})
    mcp_servers = mcp_cfg.get("servers", {})
    has_docker_mcp = False

    for srv_name, srv in mcp_servers.items():
        if not srv.get("enabled", False):
            continue
        if srv.get("type") == "docker":
            has_docker_mcp = True
            safe_name = srv_name.upper().replace("-", "_")
            env_lines.append(f"MCP_{safe_name}_IMAGE={srv.get('image', '')}")
            resolved = interpolate_env(srv.get("env", {}))
            for ek, ev in resolved.items():
                env_lines.append(f"MCP_{safe_name}_{ek}={ev}")
    if has_docker_mcp:
        env_lines.append("")

    profiles = []
    if models_use_ollama and not ollama_is_native:
        profiles.append("ollama")
    if has_docker_mcp:
        profiles.append("mcp")
    env_lines.append(f"COMPOSE_PROFILES={','.join(profiles)}")

    env_path = os.path.join(project_dir, f".env.{env_name}")
    with open(env_path, "w") as f:
        f.write("\n".join(env_lines) + "\n")

    # --- Resolve context window size ---
    # For local models (Docker Model Runner, Ollama), context size must be explicit
    # because OpenClaw doesn't have them in its built-in model catalog.
    # Cloud providers (Google, Anthropic) are in the catalog and don't need this.
    context_tokens = None
    if models_use_dmr:
        dmr_cfg = env_cfg.get("docker-model-runner", {})
        context_tokens = dmr_cfg.get("context-size")
    elif models_use_ollama:
        context_tokens = ollama_env.get("context-size")

    # --- Generate configs/active/<env>/openclaw.json ---
    agent_defaults = {
        "model": {
            "primary": primary,
            "fallbacks": fallback
        },
        "timeoutSeconds": agent_timeout,
        "typingIntervalSeconds": agent_typing_interval
    }

    if context_tokens:
        agent_defaults["contextTokens"] = context_tokens
        # Scale compaction to trigger early enough to avoid overflow.
        # reserveTokens: headroom before compaction triggers (40% of context)
        # keepRecentTokens: recent messages kept after summarization (30%)
        # reserveTokensFloor: gateway safety floor (matches reserveTokens)
        # memoryFlush: persist session state before compaction runs
        reserve_tokens = max(4096, int(context_tokens * 0.4))
        keep_recent = max(4096, int(context_tokens * 0.3))
        soft_threshold = max(2048, int(context_tokens * 0.1))
        agent_defaults["compaction"] = {
            "mode": "default",
            "reserveTokens": reserve_tokens,
            "reserveTokensFloor": reserve_tokens,
            "keepRecentTokens": keep_recent,
            "memoryFlush": {
                "softThresholdTokens": soft_threshold
            }
        }

    openclaw_config = {
        "agents": {
            "defaults": agent_defaults
        },
        "gateway": {
            "port": gateway_port,
            "mode": "local",
            "bind": "lan",
        }
    }

    # Telegram channel
    if telegram_enabled and telegram_token:
        openclaw_config["channels"] = {
            "telegram": {
                "enabled": True,
                "botToken": telegram_token,
                "dmPolicy": "open",
                "allowFrom": ["*"],
                "streaming": "partial",
                "groups": {
                    "*": {
                        "requireMention": True
                    }
                }
            }
        }

    # Build model providers
    providers = {}

    # Docker Model Runner
    if models_use_dmr:
        dmr_models = [m for m in all_models if m.startswith("docker-model-runner/")]
        providers["docker-model-runner"] = {
            "baseUrl": "http://model-runner.docker.internal/engines/llama.cpp/v1",
            "apiKey": "no-key-needed",
            "api": "openai-completions",
            "models": [{"id": m.split("/", 1)[1], "name": m.split("/", 1)[1].split("/")[-1]} for m in dmr_models]
        }

    # Ollama
    if models_use_ollama:
        ollama_host = "host.docker.internal" if ollama_is_native else "ollama"
        providers["ollama"] = {
            "baseUrl": f"http://{ollama_host}:{ollama_port}",
            "apiKey": "ollama-local",
            "api": "ollama",
            "models": [{"id": m.split("/", 1)[1], "name": m.split("/", 1)[1]} for m in all_models if m.startswith("ollama/")]
        }

    if providers:
        openclaw_config["models"] = {"providers": providers}

    # Skills configuration
    env_skills = env_cfg.get("skills", {})
    enabled_skills = {slug: sc for slug, sc in env_skills.items() if sc.get("enabled", False)}
    if enabled_skills:
        skills_entries = {}
        for slug, sc in enabled_skills.items():
            entry = {"enabled": True}
            skill_env = sc.get("env", {})
            if skill_env:
                entry["env"] = interpolate_env(skill_env)
            skills_entries[slug] = entry
        skills_load = {"watch": True}
        if skills_install_dir == "workspace":
            skills_load["extraDirs"] = ["/workspace/skills"]
        openclaw_config["skills"] = {
            "load": skills_load,
            "entries": skills_entries
        }

    active_dir = os.path.join(project_dir, "configs", "active", env_name)
    os.makedirs(active_dir, exist_ok=True)
    output_path = os.path.join(active_dir, "openclaw.json")
    with open(output_path, "w") as f:
        json.dump(openclaw_config, f, indent=2)
        f.write("\n")

    # --- Generate configs/active/<env>/mcporter.json (MCP server definitions) ---
    # mcporter expects "mcpServers" as the top-level key (not "servers")
    mcporter_config = {"mcpServers": {}}
    for srv_name, srv in mcp_servers.items():
        if not srv.get("enabled", False):
            continue
        srv_type = srv.get("type", "")
        resolved_env = interpolate_env(srv.get("env", {}))

        if srv_type == "docker":
            mcporter_config["mcpServers"][srv_name] = {
                "transport": "sse",
                "url": f"http://mcp-{srv_name}:8811/sse",
                "env": resolved_env
            }
        elif srv_type == "sse":
            mcporter_config["mcpServers"][srv_name] = {
                "transport": "sse",
                "url": srv.get("url", ""),
                "env": resolved_env
            }
        elif srv_type == "stdio":
            mcporter_config["mcpServers"][srv_name] = {
                "transport": "stdio",
                "command": srv.get("command", ""),
                "args": srv.get("args", []),
                "env": resolved_env
            }

    mcporter_path = os.path.join(active_dir, "mcporter.json")
    with open(mcporter_path, "w") as f:
        json.dump(mcporter_config, f, indent=2)
        f.write("\n")

    enabled_mcp = [n for n, s in mcp_servers.items() if s.get("enabled", False)]
    print(f"  [{env_name}]")
    print(f"    Primary:  {primary}")
    print(f"    Fallback: {', '.join(fallback) if fallback else 'none'}")
    print(f"    MCP:      {', '.join(enabled_mcp) if enabled_mcp else 'none'}")
    print(f"    Skills:   {', '.join(enabled_skills.keys()) if enabled_skills else 'none'}")

# Copy .env.dev as default .env (docker-compose reads .env by default)
dev_env = os.path.join(project_dir, ".env.dev")
default_env = os.path.join(project_dir, ".env")
if os.path.exists(dev_env):
    shutil.copy2(dev_env, default_env)

print("")
print(f"Generated configs for: {', '.join(environments.keys())}")
print(f"  .env → .env.dev (default)")
print(f"  Telegram: {'enabled' if telegram_enabled else 'disabled'}")
print(f"  Gateway port: {gateway_port}")
PYEOF
