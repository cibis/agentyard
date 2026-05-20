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

### Test setup — Stock Advisory Portal

The bootstrap process in [docs/examples/bootstrap.md](docs/examples/bootstrap.md) was run end-to-end as a reference test. The CEO agent delegated the portal build task to the Full Stack Developer agent (opencode), which autonomously built and deployed a 6-screen **Stock Advisory Portal** at `http://localhost:9081/stock-portal/`:

- **Alert Dashboard** — reads latest `daily-alert-*.md` report from openclaw outbox
- **Watchlist Manager** — reads `approved_stocks.md` (28 active tickers on first deploy)
- **Approval Queue** — reads pending board approvals from Paperclip
- **Screening Reports** — lists all `weekly-screen-*.md` files
- **Portfolio Tracker** — tracks positions and performance
- **Earnings Calendar** — upcoming earnings for watchlist tickers

The portal is served by `server.js` (Node.js built-ins only, no npm) with 8 API routes, registered as `stock-portal` in `serve-process.json`. The Paperclip task (MIN-9) closed automatically once the agent verified the portal was accessible and posted the URL as a comment.

![MIN-9 closed by CEO agent](docs/screenshots/min9-paperclip-done.jpg)
![Stock Advisory Portal — Watchlist Manager](docs/screenshots/stock-portal-watchlist.jpg)

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

All four repos must exist as **sibling directories** under a common parent. `docker-compose.yml` and Paperclip launch commands reference them as `../openclaw`, `../opencode`, and `../paperclip`.

```
parent-dir/
├── agentyard/   ← git clone https://github.com/cibis/agentyard
├── openclaw/    ← git clone https://github.com/cibis/openclaw
├── opencode/    ← git clone https://github.com/cibis/opencode
└── paperclip/   ← git clone https://github.com/cibis/paperclip
```

```powershell
# From the parent directory that will contain all repos
git clone https://github.com/cibis/agentyard
git clone https://github.com/cibis/openclaw
git clone https://github.com/cibis/opencode    # default branch: dev
git clone https://github.com/cibis/paperclip
```

All three sibling repos are forks with agentyard-specific patches on top of their upstream default branch:

| Fork | Upstream | Patches on branch |
|---|---|---|
| [cibis/openclaw](https://github.com/cibis/openclaw) | [openclaw/openclaw](https://github.com/openclaw/openclaw) | `main` |
| [cibis/opencode](https://github.com/cibis/opencode) | [anomalyco/opencode](https://github.com/anomalyco/opencode) | `dev` |
| [cibis/paperclip](https://github.com/cibis/paperclip) | [paperclipai/paperclip](https://github.com/paperclipai/paperclip) | `master` |

To pick up a future upstream release for any fork, fetch from `upstream` and rebase:
```powershell
# openclaw (main) / opencode (dev)
git fetch upstream && git rebase upstream/main   # or upstream/dev for opencode

# paperclip
git fetch upstream && git rebase upstream/master
```

---

## Quick start

```powershell
# 1. Copy and fill in secrets
cp .env.example .env   # edit with your API keys

# 2. Build and start the agent containers
docker compose up -d --build

# 3. Verify both containers are healthy
docker compose ps

# 4. Generate the SSH key for opencode (one-time, no passphrase)
#    The public key in docker-compose.yml must match — see Architecture Decisions below
ssh-keygen -t ed25519 -C "opencode-key" -f "$env:USERPROFILE\.ssh\id_opencode" -N '""'
# Copy the public key output to the printf line in docker-compose.yml (opencode command block)
# Then add to ~/.ssh/config:
#   Host opencode
#       HostName localhost
#       Port 2223
#       User root
#       IdentityFile ~/.ssh/id_opencode
#       StrictHostKeyChecking no

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
│   ├── opencode.jsonc        # opencode provider config
│   └── openclaw-workspace/
│       └── AGENTS.md         # Base workspace instructions for all openclaw agents
├── skills/
│   ├── yahoo-finance/SKILL.md      # Yahoo Finance skill (openclaw)
│   ├── opencode/SKILL.md           # Serve conventions (mounted into opencode)
│   ├── conventions/SKILL.md        # Path conventions (mounted into opencode)
│   └── file-exchange/SKILL.md      # File exchange rules (openclaw + opencode)
├── shared/                   # Bind-mounted into both containers at /exchange
│   ├── inbox/openclaw/
│   │   ├── approved_stocks.md      # Active watchlist (human-editable)
│   │   └── screening_criteria.md   # Screening filters (human-editable)
│   ├── outbox/               # Agents write results here
│   ├── scratch/              # Ephemeral working files
│   └── workspace/
│       ├── openclaw/
│       │   ├── stock-watch-analyst/AGENTS.md
│       │   └── financial-research-analyst/AGENTS.md
│       └── opencode/
│           └── AGENTS.md           # FullStack Dev domain context
└── docs/
    ├── ops-reference.md      # Stack debugging and ops reference
    ├── setup.md              # Full setup guide
    ├── interfaces.md         # API and interface reference
    └── examples/
        ├── bootstrap.md                    # First-run checklist
        ├── paperclip-task-build-portal.md  # Portal build task template
        └── paperclip-task-setup-routines.md # Routine setup task template
```

---

## Adding skills to openclaw

Drop a `SKILL.md` file under `skills/<name>/SKILL.md` — no restart needed. The skill is live-mounted at `/app/skills/agentyard/` inside the container and scanned on every request.

See [skills/yahoo-finance/SKILL.md](skills/yahoo-finance/SKILL.md) for a working example.

---

## Architecture decisions

### openclaw version pin
`../openclaw` is pinned to commit `2949171fcc` (v2026.5.3, protocol v3) because Paperclip's openclaw-gateway adapter hardcodes protocol v3. Upgrading openclaw past v2026.5.4 breaks all agent connections until the Paperclip adapter is updated to match. Check `../paperclip/packages/adapters/openclaw-gateway/src/server/execute.ts` (`PROTOCOL_VERSION`) vs `../openclaw/src/gateway/protocol/version.ts` (`MIN_CLIENT_PROTOCOL_VERSION`) before upgrading.

### opencode SSH authorized_keys
The SSH public key for opencode is baked into the startup command in `docker-compose.yml`. It is written using `printf` on every container boot, so `--force-recreate` does not break SSH access. If you regenerate `~/.ssh/id_opencode`, update the `printf` line in the opencode `command` block and rebuild/recreate the container. Never use `echo` or PowerShell piping to write SSH keys — BOM characters break key parsing.

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
- **LangGraph.js-powered agents** — new agents implemented with [LangGraph.js](https://github.com/langchain-ai/langgraphjs) for structured, graph-based agentic workflows with explicit state machines and controlled execution flow, replacing ad-hoc prompt chaining.

---

## Documentation

- [docs/ops-reference.md](docs/ops-reference.md) — stack debugging and ops reference (Paperclip API, DB, containers)
- [docs/setup.md](docs/setup.md) — step-by-step setup from scratch
- [docs/interfaces.md](docs/interfaces.md) — API reference for all components
- [docs/examples/](docs/examples/) — reusable Paperclip task templates and bootstrap checklist
