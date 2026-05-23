# Agentyard Ops Reference

How to inspect, query, and interact with every layer of the agentyard stack from a Claude Code session on the host machine. All values are discovered dynamically — no hardcoded IDs or paths.

---

## Stack at a Glance

| Service | Location | Host port(s) | Purpose |
|---------|----------|-------------|---------|
| Paperclip | `../paperclip` (host process) | 3100 (API) | Orchestrator — routes tasks to agents |
| openclaw | Docker container `openclaw` | 18789 (gateway), 9080 (web preview) | openclaw agent runner — receives tasks from Paperclip via gateway protocol |
| opencode | Docker container `opencode` | 2223 (SSH), 9081 (web preview) | Coding agent — SSH-accessible sandbox |
| PostgreSQL | host process | 5432 | Paperclip's backing database |

**Inter-container networking:** both containers share Docker network `agent-net`. openclaw reaches opencode as `http://opencode:9081`. Paperclip (host) reaches openclaw as `http://localhost:18789`. Containers reach Paperclip as `http://host.docker.internal:3100`.

**File exchange:** `./shared/` on host is mounted at `/exchange/` in both containers. Agents read from `/exchange/inbox/<agent>/` and write to `/exchange/outbox/<agent>/`.

---

## Discovery Pattern

Always use this order:

1. Read `.env` for ports, tokens, credentials
2. Read `docker-compose.yml` for container names, volume mounts, port mappings
3. Query live APIs / run `docker logs` for runtime state
4. Query the database only when no API endpoint exists

**Key config files:**

| File | Purpose |
|------|---------|
| `.env` | All secrets — API keys, SSH passwords, gateway token |
| `docker-compose.yml` | Container definitions, volume mounts, port mappings |
| `config/openclaw.json` | openclaw model providers, gateway auth, agent defaults |
| `config/opencode.jsonc` | opencode model config (Anthropic Haiku) |
| `../paperclip/.env` | Paperclip server config — DATABASE_URL, exchange dirs |

---

## Paperclip API

**Base URL:** read from `.env` → `PAPERCLIP_API_URL`, or default `http://localhost:3100`

**Auth mode:** `local_trusted` — no authentication header required for any request from the host. Agents running inside containers authenticate via `Authorization: Bearer $PAPERCLIP_API_KEY` (auto-injected short-lived JWT).

**Source:** `../paperclip/server/src/routes/` — read here when you need to find an undocumented endpoint or debug a 404.

### Step 0 — Discover the company ID

Always discover the company ID from the API rather than hardcoding it.

```powershell
$companies = Invoke-RestMethod "http://localhost:3100/api/companies"
$company = $companies | Where-Object { $_.issuePrefix -eq "MIN" }
$companyId = $company.id
```

### List agents

```powershell
$agents = Invoke-RestMethod "http://localhost:3100/api/companies/$companyId/agents"
$agents | ForEach-Object { "$($_.nameKey) — adapter: $($_.adapterType) — id: $($_.id)" }
```

**MINT system agents and their adapter types:**

| nameKey | Adapter type | Runs on |
|---------|-------------|---------|
| `ceo` | `claude_local` | Paperclip host process (Claude Sonnet) |
| `stock-watcher` | `openclaw_gateway` | openclaw container |
| `financial-research-analyst` | `openclaw_gateway` | openclaw container |
| `full-stack-developer` | `opencode_local` | opencode container via SSH |

### List issues

```powershell
# All recent issues
$result = Invoke-RestMethod "http://localhost:3100/api/companies/$companyId/issues?limit=20"
$result.issues | ForEach-Object { "$($_.identifier) [$($_.status)] $($_.title)" }

# Filter by status
$blocked = (Invoke-RestMethod "http://localhost:3100/api/companies/$companyId/issues?status=blocked&limit=20").issues

# Search by text
$found = (Invoke-RestMethod "http://localhost:3100/api/companies/$companyId/issues?q=portal&limit=10").issues
```

**Issue status values:** `backlog`, `todo`, `in_progress`, `in_review`, `blocked`, `done`, `cancelled`

### Get a specific issue

```powershell
# By issue ID (UUID)
Invoke-RestMethod "http://localhost:3100/api/issues/{issueId}"

# By identifier (e.g. MIN-7) — list then filter
$issues = (Invoke-RestMethod "http://localhost:3100/api/companies/$companyId/issues?limit=50").issues
$issue = $issues | Where-Object { $_.identifier -eq "MIN-7" }
```

### Get issue comments

```powershell
Invoke-RestMethod "http://localhost:3100/api/issues/{issueId}/comments" |
    ForEach-Object { "[$($_.authorType)] $($_.body.Substring(0, [Math]::Min(100, $_.body.Length)))" }
```

### Post a comment

```powershell
# Plain comment
$body = [PSCustomObject]@{ body = "Your comment here" } | ConvertTo-Json
Invoke-RestMethod -Method POST "http://localhost:3100/api/issues/{issueId}/comments" `
    -ContentType "application/json" -Body $body

# Comment that reopens a blocked issue (moves it back to todo and wakes the agent)
$body = [PSCustomObject]@{ body = "Root cause fixed — retrying."; reopen = $true } | ConvertTo-Json
Invoke-RestMethod -Method POST "http://localhost:3100/api/issues/{issueId}/comments" `
    -ContentType "application/json" -Body $body
```

### Update an issue (status, assignee, title, etc.)

```powershell
$body = [PSCustomObject]@{
    status = "todo"
    # Other updatable fields: title, description, priority, assigneeAgentId,
    # projectId, goalId, parentId, billingCode, blockedByIssueIds
} | ConvertTo-Json
Invoke-RestMethod -Method PATCH "http://localhost:3100/api/issues/{issueId}" `
    -ContentType "application/json" -Body $body
```

### Create an issue (manually trigger agent work)

```powershell
# Discover agent ID first
$agents = Invoke-RestMethod "http://localhost:3100/api/companies/$companyId/agents"
$agentId = ($agents | Where-Object { $_.nameKey -eq "stock-watcher" }).id

$body = [PSCustomObject]@{
    title = "stock-watcher-daily-2026-05-20"
    description = "Full task description here..."
    assigneeAgentId = $agentId
    status = "todo"
} | ConvertTo-Json
Invoke-RestMethod -Method POST "http://localhost:3100/api/companies/$companyId/issues" `
    -ContentType "application/json" -Body $body
```

### List pending board approvals

```powershell
# All approvals
Invoke-RestMethod "http://localhost:3100/api/companies/$companyId/approvals"

# Get approval details
Invoke-RestMethod "http://localhost:3100/api/approvals/{approvalId}"

# Issues linked to an approval
Invoke-RestMethod "http://localhost:3100/api/approvals/{approvalId}/issues"
```

Approvals are created by agents via `POST /api/companies/{companyId}/approvals` with type `request_board_approval`. Human owners resolve them in the Paperclip UI.

### List environments

```powershell
$envs = Invoke-RestMethod "http://localhost:3100/api/companies/$companyId/environments"
$envs | ForEach-Object { "$($_.name) — $($_.adapterType) — id: $($_.id)" }
```

**Environment adapter types:** `openclaw_gateway` (routes to openclaw), `opencode_local` (SSH into opencode), `claude_local` (Paperclip host).

### List and update secrets

```powershell
# List all secrets
$secrets = Invoke-RestMethod "http://localhost:3100/api/companies/$companyId/secrets"
$secrets | ForEach-Object { "$($_.key) — status: $($_.status) — version: $($_.latestVersion)" }

# Rotate (update) a secret value
# Note: PATCH /api/secrets/{id} only updates metadata. Use /rotate to change the value.
$secretId = ($secrets | Where-Object { $_.key -like "*ssh*private*" }).id
$key = [string](Get-Content "$env:USERPROFILE\.ssh\id_opencode" -Raw)
$body = [PSCustomObject]@{ value = $key } | ConvertTo-Json -Depth 1
Invoke-RestMethod -Method POST "http://localhost:3100/api/secrets/$secretId/rotate" `
    -ContentType "application/json" -Body $body
```

**SSH key for opencode:** stored as a Paperclip secret. If an opencode-adapter task fails with `adapter_failed` / SSH error:
1. Verify key works from host: `ssh -i ~/.ssh/id_opencode -p 2223 root@127.0.0.1 "echo connected"`
2. Find the secret: look for key matching `*ssh*private*` in the secrets list
3. Rotate it with the command above
4. Reopen the blocked issue with `reopen: true` on a comment

### List and manage routines

```powershell
# List routines
Invoke-RestMethod "http://localhost:3100/api/companies/$companyId/routines"

# Routines are created by agents via the Paperclip skill — see skills/paperclip/references/routines.md
# Each routine creates an issue on each trigger, assigned to the routine's agent
```

**MINT routines:**
- Daily stock monitor — weekday mornings → StockWatcher agent
- Weekly stock screener — Sunday evenings → Financial Research Analyst agent

### Pause / resume an agent

```powershell
$agentId = ($agents | Where-Object { $_.nameKey -eq "full-stack-developer" }).id
Invoke-RestMethod -Method POST "http://localhost:3100/api/agents/$agentId/pause"
Invoke-RestMethod -Method POST "http://localhost:3100/api/agents/$agentId/resume"
```

### Check Paperclip process (host)

Paperclip is a Node.js process running directly on the host. Check if it's running:

```powershell
# Check if port 3100 is listening
netstat -ano | Select-String "3100"

# Check Paperclip API health
Invoke-RestMethod "http://localhost:3100/api/companies"

# Source: ../paperclip
# Start: cd ../paperclip && npm run dev (or check its start command in package.json)
```

---

## PostgreSQL Database

**Connection string:** read from `../paperclip/.env` → `DATABASE_URL`

Default: `postgres://paperclip:paperclip@localhost:5432/paperclip`

**ORM:** Drizzle (not Prisma). Schema files: `../paperclip/packages/db/src/schema/`

**When to use DB vs API:** prefer the API for all reads and writes — no auth needed in `local_trusted` mode. Use the DB only when no API endpoint exists for what you need, or to inspect encrypted/internal state.

### Run a query

```powershell
$dbUrl = (Get-Content "..\paperclip\.env" | Where-Object { $_ -match "^DATABASE_URL=" }) -replace "^DATABASE_URL=",""
psql $dbUrl -c "SELECT id, name_key, adapter_type, company_id FROM agents LIMIT 10"
```

### Key tables

| Table | Key columns |
|-------|-------------|
| `companies` | `id`, `issue_prefix`, `name` |
| `agents` | `id`, `name_key`, `adapter_type`, `company_id`, `status` |
| `issues` | `id`, `identifier`, `title`, `status`, `assignee_agent_id`, `company_id` |
| `issue_comments` | `id`, `issue_id`, `body`, `author_type`, `author_agent_id` |
| `environments` | `id`, `name`, `adapter_type`, `company_id` |
| `company_secrets` | `id`, `key`, `status`, `latest_version`, `company_id` |
| `company_secret_versions` | `id`, `secret_id`, `version`, `encrypted_value` |
| `routines` | `id`, `name`, `company_id`, `agent_id` |
| `agent_runtime_state` | `agent_id`, `session_state`, `last_heartbeat_at` |
| `approvals` | `id`, `company_id`, `type`, `status`, `requested_by_agent_id` |

### Useful queries

```sql
-- All agents with their adapter type
SELECT name_key, adapter_type, status FROM agents WHERE company_id = '...' ORDER BY name_key;

-- Recent blocked issues
SELECT identifier, title, status, updated_at FROM issues
WHERE status = 'blocked' ORDER BY updated_at DESC LIMIT 10;

-- Last N comments on an issue
SELECT body, author_type, created_at FROM issue_comments
WHERE issue_id = '...' ORDER BY created_at DESC LIMIT 5;

-- Secret versions (to check if a secret was actually updated)
SELECT s.key, v.version, v.created_at
FROM company_secrets s JOIN company_secret_versions v ON v.secret_id = s.id
WHERE s.company_id = '...' ORDER BY v.created_at DESC;
```

---

## openclaw Container

**Gateway URL:** `http://localhost:18789` (read from `config/openclaw.json` if overridden)

**Gateway token:** read from `.env` → `OPENCLAW_GATEWAY_TOKEN`

No SSH exposed — use `docker exec` or `docker logs`.

### Health check

```powershell
Invoke-RestMethod "http://localhost:18789/healthz"
```

### View logs

```powershell
docker logs openclaw --tail 50
docker logs openclaw --tail 200 --since 1h

# Detailed session log inside container
$date = (Get-Date -Format "yyyy-MM-dd")
docker exec openclaw sh -c "cat /tmp/openclaw/openclaw-$date.log"
```

### Run a command inside the container

```powershell
docker exec openclaw sh -c "ls /exchange/inbox/openclaw/"
docker exec openclaw sh -c "cat /exchange/inbox/openclaw/approved_stocks.md"
docker exec openclaw sh -c "ls /exchange/outbox/openclaw/"
```

### File paths (host ↔ container)

| Host path | Container path | Notes |
|-----------|---------------|-------|
| `./shared/` | `/exchange/` | Full file exchange |
| `./shared/inbox/openclaw/` | `/exchange/inbox/openclaw/` | Agent reads approved_stocks.md, screening_criteria.md |
| `./shared/outbox/openclaw/` | `/exchange/outbox/openclaw/` | Agent writes daily-alert-*.md, weekly-screen-*.md |
| `./shared/scratch/openclaw/` | `/exchange/scratch/openclaw/` | Ephemeral work (cleaned up after tasks) |
| `./shared/workspace/openclaw/<agent>/AGENTS.md` | `/exchange/workspace/openclaw/<agent>/AGENTS.md` | Per-agent instructions (read-only mount) |
| `./skills/` | `/app/skills/agentyard/` | All skills — scanned recursively |
| `./config/openclaw-workspace/AGENTS.md` | `/root/.openclaw/workspace/AGENTS.md` | Global workspace conventions (inherited by all agents) |

**Agent instructions layering:**
1. `/root/.openclaw/workspace/AGENTS.md` — global: networking, URL translation, file exchange, skills list
2. `/exchange/workspace/openclaw/<agent>/AGENTS.md` — per-agent: role, capabilities, workflow
3. Paperclip issue description — overrides defaults for that specific run

**Adding a new skill:** create `skills/<name>/SKILL.md` on the host — it's automatically available at `/app/skills/agentyard/<name>/SKILL.md` on next container restart.

### Protocol version — critical

If you see `protocol mismatch` in `docker logs openclaw`, openclaw and Paperclip's adapter disagree on the protocol version:

- **Paperclip side:** `../paperclip/packages/adapters/openclaw-gateway/src/server/execute.ts` → look for `PROTOCOL_VERSION` constant
- **openclaw side:** `../openclaw/src/gateway/protocol/version.ts` → look for `MIN_CLIENT_PROTOCOL_VERSION` and `MAX_CLIENT_PROTOCOL_VERSION`

Last known v3-compatible openclaw commit: `2949171fcc` (2026-05-04, "perf: reduce gateway startup readiness latency")

To roll back openclaw to v3:
```powershell
git -C ../openclaw checkout 2949171fcc
docker compose build --no-cache openclaw
docker compose up -d --force-recreate openclaw
docker logs openclaw --tail 30
```

### Rebuild openclaw after any source change

```powershell
docker compose build --no-cache openclaw
docker compose up -d --force-recreate openclaw
docker compose ps
```

### openclaw model config

Model providers are in `config/openclaw.json`. To add or change a model:

```json
"models": {
  "providers": {
    "anthropic": {
      "models": [
        { "id": "claude-haiku-4-5-20251001", "name": "Claude Haiku 4.5", "maxTokens": 16384, "contextWindow": 200000 },
        { "id": "claude-sonnet-4-6", "name": "Claude Sonnet 4.6", "maxTokens": 16000, "contextWindow": 200000 }
      ]
    }
  }
}
```

Valid root keys: `gateway`, `models`, `agents`, `mcpServers`. Invalid: `agent` (must be `agents`), `baseURL` (must be `baseUrl`).

---

## opencode Container

**SSH alias:** `ssh opencode` (config in `~/.ssh/config`, key `~/.ssh/id_opencode`, no passphrase)

**SSH direct:** `ssh -i ~/.ssh/id_opencode -p 2223 -o StrictHostKeyChecking=no root@127.0.0.1`

**Web preview:** `http://localhost:9081`

**Default model:** `anthropic/claude-haiku-4-5-20251001` (set in `config/opencode.jsonc`)

### SSH into opencode

```powershell
ssh opencode
```

### Run a command via SSH (non-interactive)

```powershell
ssh opencode "ls /exchange/outbox/opencode/"
ssh opencode "cat /exchange/outbox/opencode/serve-process.json"
ssh opencode "node --version"
```

### View logs

```powershell
docker logs opencode --tail 50
docker logs opencode --tail 200 --since 1h
```

### File paths (host ↔ container)

| Host path | Container path | Notes |
|-----------|---------------|-------|
| `./shared/` | `/exchange/` | Full file exchange |
| `./shared/outbox/opencode/serve/` | `/exchange/outbox/opencode/serve/` | Web server root |
| `./shared/outbox/opencode/serve/server.js` | `/exchange/outbox/opencode/serve/server.js` | The one allowed server |
| `./shared/outbox/opencode/serve/www/` | `/exchange/outbox/opencode/serve/www/` | Static files |
| `./shared/workspace/opencode/AGENTS.md` | `/workspace/AGENTS.md` | Domain context for opencode agents |
| `./skills/opencode/SKILL.md` | `/workspace/serve-conventions.md` | Serve path conventions |
| `./skills/conventions/SKILL.md` | `/workspace/conventions.md` | Canonical exchange paths |
| `./skills/file-exchange/SKILL.md` | `/workspace/file-exchange-conventions.md` | Exchange rules |

### Serve server management

The only allowed server is `server.js` on port 9081, auto-started on container boot if it exists.

```powershell
# Check if server is running and what's registered
ssh opencode "cat /exchange/outbox/opencode/serve-process.json"

# Start server manually (if not running)
ssh opencode "node /exchange/outbox/opencode/serve/server.js &"

# Check what's listening on 9081
ssh opencode "ss -tlnp | grep 9081"

# Verify from host
Invoke-RestMethod "http://localhost:9081/stock-portal/api/watchlist"

# Verify from openclaw container
docker exec openclaw sh -c "curl -s http://opencode:9081/stock-portal/"
```

### Rebuild opencode after Dockerfile change

```powershell
docker compose build --no-cache opencode
docker compose up -d --force-recreate opencode
docker compose ps
```

---

## Docker Compose Quick Reference

All commands run from the agentyard project root:

```powershell
# Status
docker compose ps

# Logs
docker logs openclaw --tail 50
docker logs opencode --tail 50

# Restart (config change, no rebuild)
docker compose restart openclaw
docker compose restart opencode

# Recreate (volume mount change)
docker compose up -d --force-recreate openclaw
docker compose up -d --force-recreate opencode

# Rebuild from source then recreate
docker compose build --no-cache openclaw
docker compose up -d --force-recreate openclaw

# Stop everything
docker compose down

# Named volumes (persistent state)
# agentyard_openclaw-workspace → /root/.openclaw/ inside openclaw
# agentyard_opencode-workspace → /workspace inside opencode
# agentyard_agent-exchange → /agent-exchange in both (container-to-container)
```

**When to recreate vs restart:** restart suffices for `.env` changes and most config changes. Recreate (`--force-recreate`) is required when `docker-compose.yml` volume mounts change, since Docker doesn't re-apply them on plain restart.

---

## MINT System File Map

Key files the agents read and write:

| File | Agent | Read/Write |
|------|-------|-----------|
| `/exchange/inbox/openclaw/approved_stocks.md` | StockWatcher, FinancialResearchAnalyst | Read — active watchlist |
| `/exchange/inbox/openclaw/screening_criteria.md` | StockWatcher, FinancialResearchAnalyst | Read — all thresholds and filters |
| `/exchange/outbox/openclaw/daily-alert-{YYYY-MM-DD}.md` | StockWatcher | Write |
| `/exchange/outbox/openclaw/weekly-screen-{YYYY-MM-DD}.md` | FinancialResearchAnalyst | Write |
| `/exchange/scratch/openclaw/candidates.txt` | FinancialResearchAnalyst | Write (cleaned up after run) |
| `/exchange/outbox/opencode/serve/server.js` | FullStackDeveloper | Write — the portal server |
| `/exchange/outbox/opencode/serve/www/stock-portal/` | FullStackDeveloper | Write — portal static files |
| `/exchange/outbox/opencode/earnings-calendar.md` | FullStackDeveloper (on demand) | Write |

**Portal API routes** (all served by `server.js` on port 9081):
- `GET /stock-portal/api/alerts/latest`
- `GET /stock-portal/api/alerts/history`
- `GET /stock-portal/api/alerts/:date`
- `GET /stock-portal/api/watchlist`
- `GET /stock-portal/api/screening`
- `GET /stock-portal/api/screening/:date`
- `GET /stock-portal/api/portfolio`
- `GET /stock-portal/api/calendar`

---

## Common Diagnostic Sequence

When an agent task is blocked or producing unexpected output:

```powershell
# 1. Discover company and find the blocked issue
$companies = Invoke-RestMethod "http://localhost:3100/api/companies"
$companyId = ($companies | Where-Object { $_.issuePrefix -eq "MIN" }).id
$blocked = (Invoke-RestMethod "http://localhost:3100/api/companies/$companyId/issues?status=blocked&limit=10").issues
$blocked | ForEach-Object { "$($_.identifier) — $($_.title)" }

# 2. Read the last few comments for the error message
$issueId = $blocked[0].id
(Invoke-RestMethod "http://localhost:3100/api/issues/$issueId/comments") |
    Select-Object -Last 3 | ForEach-Object { $_.body }

# 3. Check which adapter the assigned agent uses
$agents = Invoke-RestMethod "http://localhost:3100/api/companies/$companyId/agents"
$agent = $agents | Where-Object { $_.id -eq $blocked[0].assigneeAgentId }
Write-Host "Adapter: $($agent.adapterType)"

# 4. Based on adapter type, check the right container
docker logs openclaw --tail 50    # for openclaw_gateway adapter
docker logs opencode --tail 50    # for opencode_local adapter

# 5. Check gateway health (for openclaw issues)
Invoke-RestMethod "http://localhost:18789/healthz"

# 6. Fix the root cause, then reopen
$body = [PSCustomObject]@{ body = "Root cause fixed — retrying."; reopen = $true } | ConvertTo-Json
Invoke-RestMethod -Method POST "http://localhost:3100/api/issues/$issueId/comments" `
    -ContentType "application/json" -Body $body
```

---

## Environment Variables Reference

Key values from `.env`:

| Variable | Used by | Purpose |
|----------|---------|---------|
| `BRAVE_API_KEY` | openclaw | Web search (Brave plugin auto-enabled when set) |
| `OPENCLAW_GATEWAY_TOKEN` | Paperclip → openclaw | Bearer token for gateway auth |
| `OPENCODE_SSH_PASS` | opencode, Paperclip | SSH password fallback (key auth preferred) |
| `ANTHROPIC_API_KEY` | openclaw, opencode, Paperclip | Anthropic model calls |
| `PAPERCLIP_API_KEY` | openclaw container | For openclaw to call back to Paperclip API |
| `PAPERCLIP_API_URL` | openclaw container | `http://host.docker.internal:3100` |

---

## Source Repos

| Repo | Location | Notes |
|------|----------|-------|
| agentyard (this) | `.` | Compose config, skills, shared files |
| openclaw | `../openclaw` | Never modify Dockerfile; extend via skills |
| opencode | `../opencode` | Custom Dockerfile, Bun-based |
| paperclip | `../paperclip` | Host orchestrator; routes source at `server/src/routes/` |
