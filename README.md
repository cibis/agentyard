# agentyard

A self-hosted AI agent orchestration stack that pairs [Paperclip](https://github.com/paperclipai/paperclip) with sandboxed [openclaw](https://github.com/openclawai/openclaw) and [opencode](https://github.com/sst/opencode) agents running in Docker.

The stack keeps agents fully isolated from the host while giving them the internet access, tool skills, and file exchange they need to do real work. In this configuration it is wired up as an **AI investment advisor** — capable of live market research, stock price lookups, web search, financial analysis, and generating custom reports or UI dashboards.

---

## What it does

```
┌─ Host ─────────────────────────────────────────┐
│  Paperclip (orchestrator)  ←→  Browser UI      │
│         ↕ HTTP / SSH                           │
│  ┌── Docker ──────────────────────────────┐    │
│  │  openclaw  ←→  AWS Bedrock / Anthropic │    │
│  │  opencode  ←→  Anthropic               │    │
│  │  shared /exchange volume               │    │
│  └────────────────────────────────────────┘    │
└────────────────────────────────────────────────┘
```

- **Paperclip** runs on the host as the orchestration layer — manages agents, assigns goals, tracks costs, governs actions.
- **openclaw** is an HTTP agent gateway in Docker. Uses AWS Bedrock (Amazon Nova 2 Lite, primary) and Anthropic Claude (secondary). Ships with built-in Brave web search. Custom skills extend it without modifying the image.
- **opencode** is a Bun-based coding agent in Docker, accessible over SSH. Builds and runs code, produces files, generates custom reports and UIs.

Both containers run with full internal permissions (root, all Linux capabilities except `SYS_ADMIN`) but **zero host access** — no host PID namespace, no Docker socket, no host filesystem beyond a single scoped exchange directory.

---

## Use cases

The architecture is general-purpose — any task that benefits from sandboxed agents with internet access. This repo is configured for **investment advisory**:

| Capability | How it works |
|---|---|
| Live stock quotes & OHLCV data | Yahoo Finance skill (curl/node, no API key needed) |
| Web research & news | Brave Search built-in plugin (auto-enabled via `BRAVE_API_KEY`) |
| Financial analysis & reports | openclaw reasons over data; opencode generates code/documents |
| Custom UI dashboards | opencode builds and serves a web app on the preview port |
| Portfolio tracking | File exchange between agents and Paperclip via `/exchange` |

---

## Architecture

| Component | Role | Access |
|---|---|---|
| Paperclip | Orchestrator, UI, cost tracking | Host — `http://localhost:3100` |
| openclaw | Agent gateway, research, analysis | Docker — `http://localhost:18789` |
| opencode | Coding agent, report/UI builder | Docker — SSH `ssh opencode`, UI `http://localhost:9081` |

**Model providers:** AWS Bedrock (primary) · Anthropic (secondary). No local LLM required.

---

## Prerequisites

- Docker Desktop for Windows
- Node.js 20+ and pnpm 9.15+
- API keys: Anthropic, AWS Bedrock (IAM), Brave Search (free tier)

### Required repos

This project builds openclaw, opencode, and paperclip from source. All three must be cloned as **sibling directories** next to `agentyard`:

```
parent-dir/
├── agentyard/     ← this repo
├── openclaw/      ← git clone https://github.com/openclawai/openclaw
├── opencode/      ← git clone https://github.com/sst/opencode
└── paperclip/     ← git clone https://github.com/paperclipai/paperclip
```

```powershell
# From the parent directory that contains agentyard
git clone https://github.com/openclawai/openclaw
git clone https://github.com/sst/opencode
git clone https://github.com/paperclipai/paperclip
```

The `docker-compose.yml` build contexts and Paperclip launch commands all reference these as `../openclaw`, `../opencode`, and `../paperclip`.

---

## Quick start

```powershell
# 1. Copy and fill in secrets
cp .env.example .env   # edit with your API keys

# 2. Build and start the agent containers
docker compose up -d --build

# 3. Verify both containers are healthy
docker compose ps

# 4. Set up SSH access to opencode
ssh-keygen -t ed25519 -C "opencode-key" -f "$env:USERPROFILE\.ssh\id_opencode" -N '""'
$pubkey = (Get-Content "$env:USERPROFILE\.ssh\id_opencode.pub" -Raw).Trim()
docker exec opencode sh -c "echo '$pubkey' > /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys"

# 5. Start Paperclip on the host
cd ..\paperclip && pnpm install && pnpm dev
```

Then open **http://localhost:3100** and register the agents:
- openclaw → `http://localhost:18789`, token from `OPENCLAW_GATEWAY_TOKEN` in `.env`
- opencode → SSH command `ssh opencode`

---

## Project layout

```
agentyard/
├── docker-compose.yml        # Container definitions (relative paths — portable)
├── .env                      # Secrets (never commit this)
├── config/
│   ├── openclaw.json         # openclaw gateway + model config
│   └── opencode.jsonc        # opencode provider config
├── skills/
│   └── yahoo-finance/
│       └── SKILL.md          # Yahoo Finance skill (mounted into openclaw)
├── shared/                   # Bind-mounted into both containers at /exchange
│   ├── inbox/                # Drop files here for agents to read
│   ├── outbox/               # Agents write results here
│   └── workspace/            # Collaborative working area
└── docs/
    ├── SETUP.md              # Full setup guide
    └── INTERFACES.md         # API and interface reference
```

---

## Adding skills to openclaw

Drop a `SKILL.md` file under `skills/<name>/SKILL.md` — no restart needed. The skill is live-mounted at `/app/skills/agentyard/` inside the container and scanned on every request.

See [skills/yahoo-finance/SKILL.md](skills/yahoo-finance/SKILL.md) for a working example.

---

## Ports

| Port | Service | Purpose |
|---|---|---|
| `18789` | openclaw | Gateway API + Control UI |
| `9080` | openclaw | Web preview (container port 8080) |
| `2223` | opencode | SSH terminal |
| `9081` | opencode | Web UI + preview |
| `3100` | paperclip (host) | Board UI + REST API |

---

## Security model

Agents have **full permissions inside their container** and **zero access outside it**:

- Root user, all Linux capabilities except `SYS_ADMIN`
- Seccomp and AppArmor unconfined (agents need to run arbitrary code)
- No host PID/IPC namespace, no Docker socket, no `/var/run/docker.sock`
- Only one host directory is exposed: `./shared` → `/exchange` (scoped file exchange)
- Outbound internet via Docker bridge NAT (required for Bedrock/Anthropic APIs)

---

## Roadmap

- **Custom agents in Paperclip** — first-party agents built and registered directly in Paperclip, alongside the existing openclaw/opencode setup.
- **Custom adapters** — purpose-built adapters to connect agents to external data sources, APIs, and services beyond the current skill system.
- **LangGraph.js-powered agents** — new agents implemented with [LangGraph.js](https://github.com/langchain-ai/langgraphjs) for structured, graph-based agentic workflows with explicit state machines and controlled execution flow, replacing ad-hoc prompt chaining.

---

## Documentation

- [docs/SETUP.md](docs/SETUP.md) — step-by-step setup from scratch
- [docs/INTERFACES.md](docs/INTERFACES.md) — API reference for all components
