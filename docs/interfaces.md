# Accessing openclaw, opencode, and paperclip

All interfaces assume the stack is running (`docker compose up -d` from `the agentyard project root`).

---

## openclaw

openclaw is an AI agent gateway running in Docker on port **18789**. It exposes HTTP, WebSocket, and a built-in control UI.

### Authentication

All non-probe endpoints require a bearer token:

```
Authorization: Bearer <OPENCLAW_GATEWAY_TOKEN from .env>
```

### HTTP REST / OpenAI-compatible API

Base URL: `http://localhost:18789`

| Endpoint | Method | Description |
|---|---|---|
| `/health` or `/healthz` | GET | Liveness probe — no auth required |
| `/ready` or `/readyz` | GET | Readiness probe — no auth required |
| `/v1/chat/completions` | POST | OpenAI-compatible chat completions (streaming supported) |
| `/v1/responses` | POST | OpenAI Responses API-compatible endpoint |
| `/v1/models` | GET | List available models |
| `/v1/embeddings` | POST | Embeddings endpoint |
| `/tools/invoke` | POST | Invoke a tool directly |
| `/sessions/<id>/kill` | POST | Terminate a running session |
| `/sessions/<id>/history` | GET | Retrieve session conversation history |
| `/api/chat/media/outgoing/<id>` | GET | Retrieve a managed outgoing image attachment |

**Example — health check:**
```powershell
curl http://localhost:18789/healthz
```

**Example — chat completion with Claude Haiku (default model):**
```powershell
curl -X POST http://localhost:18789/v1/chat/completions `
  -H "Authorization: Bearer $env:OPENCLAW_GATEWAY_TOKEN" `
  -H "Content-Type: application/json" `
  -d '{
    "model": "anthropic/claude-haiku-4-5-20251001",
    "messages": [{"role": "user", "content": "Hello"}],
    "stream": false
  }'
```

**Example — list models:**
```powershell
curl http://localhost:18789/v1/models `
  -H "Authorization: Bearer $env:OPENCLAW_GATEWAY_TOKEN"
```

### WebSocket

openclaw's primary real-time interface is WebSocket at the same host/port:

```
ws://localhost:18789
```

Connect with the bearer token. The WebSocket carries live agent message streams — the control UI uses this channel internally.

### Control UI (web browser)

openclaw ships a built-in chat/control UI served from its HTTP server:

- **URL:** `http://localhost:9080` (port 9080 maps to openclaw's internal port 8080)
- **Also accessible at:** `http://localhost:18789` (root path, same process)

Open in a browser to interact with the agent through a chat interface, view session history, and manage the gateway.

### From inside another Docker container

Containers on the `agent-net` network reach openclaw at:

```
http://openclaw:18789
```

### Skills (extending openclaw)

Skills are markdown files mounted at `/app/skills/agentyard/` inside the container. Add a new skill by creating `skills/<name>/SKILL.md` in this repo — no restart needed for discovery.

---

## opencode

opencode is a Bun-based coding agent running in Docker. It exposes SSH and a web UI.

### SSH (primary interface)

The recommended way to interact with opencode is SSH. A named host alias `opencode` is already configured in `~/.ssh/config`.

**Connect:**
```powershell
ssh opencode
```

This logs in as `root` using the key `~/.ssh/id_opencode` (no passphrase). The working directory inside the container is `/workspace`.

**SSH details:**
| Field | Value |
|---|---|
| Host | `localhost` |
| Port | `2223` |
| User | `root` |
| Key | `~/.ssh/id_opencode` |
| Password fallback | `OPENCODE_SSH_PASS` in `.env` |

**Run a command without an interactive session:**
```powershell
ssh opencode "ls /workspace"
```

**Copy files in/out:**
```powershell
# Host → container
scp -P 2223 myfile.py root@localhost:/workspace/

# Container → host
scp -P 2223 root@localhost:/workspace/output.txt .
```

### Web UI

opencode exposes a web UI on port **9081** (maps to internal port 8080):

- **URL:** `http://localhost:9081`

Open in a browser to interact with the coding agent via its GUI, browse workspace files, and submit tasks.

### Shared file exchange

Files can be exchanged without SSH using the bind-mounted directories:

| Host path | Container path | Purpose |
|---|---|---|
| `./shared` | `/exchange` | Host ↔ container file exchange |
| Docker volume `agent-exchange` | `/agent-exchange` | openclaw ↔ opencode container-to-container exchange |

Drop a file in `./shared` and it appears at `/exchange` inside the opencode container immediately.

### From inside another Docker container

Containers on `agent-net` reach opencode's SSH at:

```
ssh -p 22 root@opencode
```

(Port 22 is the internal SSH port; port 2223 is the host-side mapping.)

---

## paperclip

paperclip is the orchestration layer running on the **host** (not in Docker) at `../paperclip`. It provides a web UI, a REST API, and a CLI.

### Starting paperclip

From `../paperclip`:

```powershell
pnpm dev          # dev mode with file watching (API + UI)
pnpm dev:once     # dev mode, no file watching
pnpm dev:server   # server only
```

Or via CLI:

```powershell
npx paperclipai run
```

### Web UI

- **URL:** `http://localhost:3100`

The full React board UI. Use it to:
- Create and manage companies, agents, org charts
- Assign goals and tasks (issues) to agents
- Monitor heartbeats, runs, and costs
- Approve governed actions
- Manage agent budgets and routines

### REST API

Base URL: `http://localhost:3100/api`

**Health check:**
```powershell
curl http://localhost:3100/api/health
```

**List companies:**
```powershell
curl http://localhost:3100/api/companies
```

All agent-facing API requests use bearer API keys (`agent_api_keys`). Board user access is full-control. See `server/src/routes/` for the full API surface; key route groups include:

| Route prefix | Purpose |
|---|---|
| `/api/health` | Server health |
| `/api/companies` | Company CRUD |
| `/api/companies/:id/agents` | Agent management |
| `/api/companies/:id/issues` | Task / issue management |
| `/api/companies/:id/routines` | Scheduled routine management |
| `/api/companies/:id/adapters/:type/models` | Adapter model listing |
| `/api/companies/:id/adapters/:type/test-environment` | Adapter connectivity test |

### CLI

```powershell
npx paperclipai onboard      # First-time setup wizard
npx paperclipai configure    # Edit configuration
npx paperclipai run          # Start the server
npx paperclipai doctor       # Run health checks
```

Full CLI reference is in `cli/README.md`.

### Registering openclaw as an agent in paperclip

In the paperclip board UI, add an agent with:
- **Adapter type:** `openclaw` (HTTP adapter)
- **URL:** `http://localhost:18789`
- **Token:** `$env:OPENCLAW_GATEWAY_TOKEN`

### Registering opencode as an agent in paperclip

In the paperclip board UI, add an agent with:
- **Adapter type:** Process / SSH
- **Command:** `ssh opencode` (uses the pre-configured `~/.ssh/config` alias)

---

## Port summary

| Service | Host port | Protocol | Description |
|---|---|---|---|
| openclaw | 18789 | HTTP / WebSocket | Gateway API + control UI |
| openclaw | 9080 | HTTP | Alternative port → internal 8080 (control UI) |
| opencode | 2223 | SSH | Shell access to coding container |
| opencode | 9081 | HTTP | opencode web UI (internal 8080) |
| paperclip | 3100 | HTTP | Board UI + REST API |
