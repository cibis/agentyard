# agentyard — Claude Code Session Context

## What This Is

A local self-hosted AI orchestration stack running in Docker on this Windows 11 machine. Three components work together:

- **openclaw** — Node.js AI agent/gateway (port 18789). Accepts tasks from Paperclip, runs them using AWS Bedrock or Anthropic models, has built-in web search (Brave) and a skill system. Web preview at `http://localhost:9080` (agent starts any server on container port 9080).
- **opencode** — Bun-based coding agent (SSH on port 2223). A sandboxed coding environment reachable via SSH. Uses Anthropic Claude Haiku by default. Web preview at `http://localhost:9081` — served content follows the convention in `skills/opencode/SKILL.md` (all files under `/exchange/outbox/opencode/serve/`, registry at `serve-process.json`, auto-restarts on container restart).
- **paperclip** — Orchestrator running on the host (not in Docker). Routes tasks to openclaw/opencode agents.

Model providers: **AWS Bedrock** (primary) and **Anthropic** (secondary). No local Ollama.

## Current State: Fully Operational

Both Docker containers are healthy and running.

```
openclaw   healthy   0.0.0.0:18789->18789/tcp, 0.0.0.0:9080->9080/tcp
opencode   healthy   0.0.0.0:2223->22/tcp, 0.0.0.0:9081->9081/tcp
```

### Version pins and known constraints

- **openclaw is pinned to commit `2949171fcc` (v2026.5.3)** — detached HEAD in `../openclaw`. Reason: Paperclip's openclaw-gateway adapter hardcodes `PROTOCOL_VERSION = 3` in `../paperclip/packages/adapters/openclaw-gateway/src/server/execute.ts`. openclaw ≥ 2026.5.17 requires protocol v4. Do not run `git pull` or `git checkout main` in `../openclaw` without first updating the adapter or it will break all openclaw agents.
- **opencode Dockerfile uses `oven/bun:1.3.14`** — required by opencode's build script (`bun@^1.3.14`). Do not downgrade.
- **opencode SSH `authorized_keys` is written by `docker-compose.yml`** — no manual setup needed. The startup command uses `printf` (not `echo`) to write the key cleanly on every boot, surviving `--force-recreate`.

## Key Files

| File | Purpose |
|------|---------|
| `docker-compose.yml` | Defines both services, networks, volumes |
| `.env` | All secrets (Brave API key, SSH passwords, gateway token, Anthropic key, AWS creds) |
| `config/openclaw.json` | openclaw config: Bedrock + Anthropic providers, gateway auth, agent defaults |
| `config/opencode.jsonc` | opencode config: Anthropic provider, Haiku as default model |
| `skills/yahoo-finance/SKILL.md` | Custom skill teaching openclaw to use Yahoo Finance API |
| `skills/opencode/SKILL.md` | opencode serve conventions — paths, serve-process.json schema, prompt templates; mounted into opencode at `/workspace/serve-conventions.md` |
| `skills/conventions/SKILL.md` | Canonical path reference for all agents (inbox/outbox/scratch per agent); mounted into opencode at `/workspace/conventions.md` |
| `skills/file-exchange/SKILL.md` | Full file exchange rules and prompt templates for openclaw; also mounted into opencode at `/workspace/file-exchange-conventions.md` |
| `shared/` | File exchange data directory bind-mounted into both containers at `/exchange` |
| `shared/workspace/openclaw/stock-watch-analyst/AGENTS.md` | Stock Watch Analyst agent identity and task instructions |
| `shared/workspace/openclaw/financial-research-analyst/AGENTS.md` | Financial Research Analyst agent identity and task instructions |
| `shared/workspace/opencode/AGENTS.md` | FullStack Dev (opencode) domain context and portal architecture |
| `shared/inbox/openclaw/approved_stocks.md` | Active watchlist for the Stock Watch Analyst (human-editable) |
| `shared/inbox/openclaw/screening_criteria.md` | Screening filters and thresholds for the Financial Research Analyst (human-editable) |
| `docs/ops-reference.md` | Full debugging and ops reference: Paperclip API, DB, containers, discovery patterns |
| `docs/examples/` | Reusable task templates: portal build, routine setup, bootstrap checklist |
| `docs/paperclip-adapter-dev-reference.md` | **Adapter dev reference**: full `ServerAdapterModule` interface, all REST API endpoints with exact paths/bodies, wake context shape (`context.paperclipWake`), session persistence pattern, env vars, networking URLs — read this before building any new adapter or custom agent |

## Models

| Model | Provider | Used by | Purpose |
|-------|----------|---------|---------|
| `claude-haiku-4-5-20251001` | Anthropic | openclaw (default), opencode (default) | Primary agent model |

openclaw default: `anthropic/claude-haiku-4-5-20251001`
opencode default: `anthropic/claude-haiku-4-5-20251001`

## Web Preview Ports

Agents can serve files or web UIs by starting an HTTP server on the container's preview port. The same port number is used on both the host and container — no remapping.

| Agent | Container port | Host URL |
|-------|---------------|----------|
| openclaw | 9080 | `http://localhost:9080` |
| opencode | 9081 | `http://localhost:9081` |

Example (inside opencode container via SSH):
```sh
python3 -m http.server 9081 --directory /workspace
# then open http://localhost:9081 in your browser
```

## Credentials & Access

- **openclaw gateway token**: see `OPENCLAW_GATEWAY_TOKEN` in `.env`
- **Anthropic API key**: see `ANTHROPIC_API_KEY` in `.env`
- **AWS credentials**: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION=us-east-1` in `.env`
- **opencode SSH**: `ssh opencode` (key auth, `~/.ssh/id_opencode`, no passphrase)
- **opencode SSH password fallback**: see `OPENCODE_SSH_PASS` in `.env`
- **openclaw SSH password**: see `OPENCLAW_SSH_PASS` in `.env` (no SSH exposed for openclaw)

SSH config is at `~/.ssh/config`:
```
Host opencode
    HostName localhost
    Port 2223
    User root
    IdentityFile ~/.ssh/id_opencode
    StrictHostKeyChecking no
```

## Common Commands

```powershell
# From the agentyard project root

# Start everything
docker compose up -d

# Check status
docker compose ps

# View logs
docker logs openclaw --tail 50
docker logs opencode --tail 50

# Restart a service
docker compose restart openclaw
docker compose restart opencode

# Stop everything
docker compose down

# Rebuild and restart (after Dockerfile changes)
docker compose up -d --build openclaw
docker compose up -d --build opencode

# SSH into opencode
ssh opencode

# Test openclaw gateway
curl http://localhost:18789/healthz

# Test Anthropic connectivity from container
docker exec openclaw sh -c "curl -s https://api.anthropic.com/v1/models -H 'x-api-key: $ANTHROPIC_API_KEY' | head -c 200"
```

## Architecture Decisions (Important)

### openclaw — Version pin (IMPORTANT)
openclaw source at `../openclaw` is on a **detached HEAD at commit `2949171fcc`** (v2026.5.3). Do not `git pull` or `git checkout main`. If you need to upgrade, first update `PROTOCOL_VERSION` in `../paperclip/packages/adapters/openclaw-gateway/src/server/execute.ts` to match the new version's `MIN_CLIENT_PROTOCOL_VERSION` in `../openclaw/src/gateway/protocol/version.ts`.

### openclaw — Never modify the Dockerfile
openclaw's Dockerfile at `../openclaw/Dockerfile` must not be modified. The correct ways to extend openclaw:
1. **Web search**: Brave plugin is built-in, auto-enabled when `BRAVE_API_KEY` env var is set.
2. **New capabilities**: Create a `SKILL.md` file under `skills/<skill-name>/SKILL.md`. These are mounted at `/app/skills/agentyard/` inside the container and scanned recursively. See `skills/yahoo-finance/SKILL.md` as an example.
3. **MCP servers**: Add to `config/openclaw.json` under `mcpServers` if needed (but verify the npm package exists first).

### openclaw config schema
The `config/openclaw.json` uses openclaw's strict Zod schema. Key valid root keys:
- `gateway` — gateway binding, auth, mode
- `models.providers.<name>` — provider definition; each model entry needs `id` AND `name`
- `agents.defaults` — default model, sandbox mode
- `mcpServers` — MCP server definitions (optional)

Provider notes:
- Anthropic: set `"models"` list; API key comes from `ANTHROPIC_API_KEY` env var automatically. No `api` field needed (auto-set to `anthropic-messages`).
- Bedrock: set `"api": "bedrock-converse-stream"`, `"auth": "aws-sdk"`, `"baseUrl"`. AWS creds come from `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` env vars.

Invalid root keys include `"agent"` (it's `agents`), and `baseURL` (it's `baseUrl`).

### opencode — Custom Dockerfile
opencode has no upstream Dockerfile. The one at `../opencode/Dockerfile` was created for this project. It uses a multi-stage Bun build. The binary ends up at `/usr/local/bin/opencode` in the runtime stage.

### SSH key for opencode
The key `~/.ssh/id_opencode` must NOT have a passphrase (non-interactive use). The current key was regenerated without a passphrase after discovering the original was encrypted.

The public key is baked into `docker-compose.yml` — the startup command writes it to `/root/.ssh/authorized_keys` using `printf` on every container boot. **Never use `echo` or PowerShell piping to write SSH keys** — they produce UTF-8 BOM characters that break SSH key parsing. If you regenerate the key, update the `printf` line in the opencode `command` block in `docker-compose.yml` with the new public key.

### Shared file exchange
Both containers mount:
- `./shared` → `/exchange` (host bind mount, for file-based agent communication)
- Docker volume `agent-exchange` → `/agent-exchange` (container-to-container exchange)

Directory layout under `shared/` (i.e. `/exchange/` inside containers):

| Path                                      | Purpose                                                  |
|-------------------------------------------|----------------------------------------------------------|
| `inbox/openclaw/`                         | Tasks and input files sent to openclaw                   |
| `inbox/openclaw/approved_stocks.md`       | Active watchlist — human-editable                        |
| `inbox/openclaw/screening_criteria.md`    | Screening filters and thresholds — human-editable        |
| `inbox/opencode/`                         | Tasks and input files sent to opencode                   |
| `outbox/openclaw/`                        | Final results produced by openclaw                       |
| `outbox/opencode/`                        | Final results produced by opencode                       |
| `outbox/opencode/serve/`                  | opencode web server: server.js, www/, serve-process.json |
| `scratch/openclaw/`                       | Ephemeral work-in-progress files for openclaw            |
| `scratch/opencode/`                       | Ephemeral work-in-progress files for opencode            |
| `workspace/openclaw/<agent>/AGENTS.md`    | Per-agent workspace instructions (mounted read-only)     |
| `workspace/opencode/AGENTS.md`            | opencode domain context (mounted at /workspace/AGENTS.md)|

Prompt templates and path-translation rules for every agent × use-case are in `skills/file-exchange/SKILL.md`.

## openclaw Config Reference

```json
{
  "gateway": {
    "mode": "local",
    "bind": "lan",
    "port": 18789,
    "auth": { "mode": "token" }
  },
  "models": {
    "providers": {
      "anthropic": {
        "models": [
          { "id": "claude-haiku-4-5-20251001", "name": "Claude Haiku 4.5" }
        ]
      }
    }
  },
  "agents": {
    "defaults": {
      "model": "anthropic/claude-haiku-4-5-20251001",
      "sandbox": { "mode": "off" }
    }
  }
}
```

## Environment Variables (.env)

```
BRAVE_API_KEY=<brave search key>
OPENCLAW_SSH_PASS=<unused, kept for reference>
OPENCODE_SSH_PASS=<opencode root password>
OPENCLAW_GATEWAY_TOKEN=<gateway bearer token>
ANTHROPIC_API_KEY=<anthropic api key>
AWS_ACCESS_KEY_ID=<aws access key>
AWS_SECRET_ACCESS_KEY=<aws secret key>
AWS_REGION=us-east-1
AWS_DEFAULT_REGION=us-east-1
AWS_REGION_NAME=us-east-1
```

## Paperclip (Host Orchestrator)

Located at `../paperclip`. Runs on the host (not in Docker). Its `.env` configures:
```
ANTHROPIC_API_KEY=<anthropic api key>
AWS_ACCESS_KEY_ID=<aws access key>
AWS_SECRET_ACCESS_KEY=<aws secret key>
AWS_REGION=us-east-1
AWS_DEFAULT_REGION=us-east-1
AWS_REGION_NAME=us-east-1
PAPERCLIP_EXCHANGE_DIR=<absolute-path-to-agentyard>\shared
PAPERCLIP_INBOX_DIR=<absolute-path-to-agentyard>\shared\inbox
PAPERCLIP_OUTBOX_DIR=<absolute-path-to-agentyard>\shared\outbox
```

Agents must be registered in Paperclip's UI pointing to:
- openclaw: `http://localhost:18789` with token from `OPENCLAW_GATEWAY_TOKEN` in `.env`
- opencode: SSH via `ssh opencode`

## Volumes

| Volume | Purpose |
|--------|---------|
| `agentyard_openclaw-workspace` | openclaw persistent state (`/root/.openclaw/`) |
| `agentyard_opencode-workspace` | opencode workspace (`/workspace`) |
| `agentyard_agent-exchange` | container-to-container file exchange |

## Source Repos

| Repo | Location |
|------|----------|
| openclaw | `../openclaw` |
| opencode | `../opencode` |
| paperclip | `../paperclip` |
| agentyard (this) | `.` |
