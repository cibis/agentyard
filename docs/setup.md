# Paperclip + OpenCode + OpenClaw — Local AI Stack Setup

---

## Goals

This plan sets up a fully self-hosted AI orchestration stack on a Windows machine with 64 GB RAM. The goals are:

1. **Run Paperclip AI as the orchestrator** — the "company" that manages agents, assigns tasks, tracks costs, and enforces governance. Built from source and run directly on the Windows host.

2. **Run OpenCode and OpenClaw as sandboxed agents** — both built from source and containerised in Docker. Paperclip dispatches work to them via the openclaw gateway and SSH.

3. **Use AWS Bedrock and Anthropic as model providers** — no local LLM required. openclaw defaults to Amazon Nova 2 Lite via Bedrock; opencode defaults to Claude Haiku 4.5 via Anthropic.

4. **Enforce a strict sandbox security model:**
   - Agents have full permissions *inside* their containers (root, all capabilities, no syscall filtering)
   - Agents have *zero* access to the host machine (no host namespaces, no host filesystem, no Docker socket)
   - Agents have full outbound internet access
   - The host and containers communicate over controlled, explicit channels

5. **Everything built from source** — no pre-built binaries beyond Node.js and Docker itself.

6. **Equip agents with internet search and financial data:**
   - **Brave Search** — openclaw has a built-in Brave plugin. Auto-enabled when `BRAVE_API_KEY` env var is set. No Dockerfile changes needed.
   - **Yahoo Finance** — implemented as a `SKILL.md` file mounted into openclaw's skill directory. The agent reads the skill and uses curl/node to call Yahoo Finance REST endpoints directly. No npm package, no MCP server.

7. **Enable structured file exchange between Paperclip and the sandboxed agents:**
   - A designated exchange directory on the host (`.\shared\`) is bind-mounted into both containers at `/exchange`
   - Paperclip (on host) reads and writes files at `.\shared\`
   - Agents read and write files at `/exchange` inside their containers
   - A separate named Docker volume (`agent-exchange` → `/agent-exchange`) enables direct agent-to-agent file passing without routing through the host

---

## Architecture

```
Windows Host
├── Paperclip AI                    (port 3100, Node.js on host)
├── .\shared\    ← Exchange zone (host side)
│   ├── inbox\                      ← Paperclip drops files here for agents
│   ├── outbox\                     ← Agents drop files here for Paperclip
│   └── workspace\                  ← Collaborative working area
└── Docker Engine
    ├── Network: agent-net          (bridge — NAT internet, isolated from host namespaces)
    ├── agent-exchange volume       (named Docker volume — agent ↔ agent only, not host)
    ├── openclaw container          (port 18789 → gateway + Control UI, 9080 → web preview)
    │   ├── Full in-container permissions (root, cap ALL-SYS_ADMIN, seccomp off)
    │   ├── Reaches internet via bridge NAT → AWS Bedrock + Anthropic APIs
    │   ├── /exchange  → .\shared\  (host ↔ agent files)
    │   ├── /agent-exchange → agent-exchange volume     (agent ↔ agent files)
    │   ├── Built-in Brave Search plugin (auto-enabled by BRAVE_API_KEY env var)
    │   └── /app/skills/agentyard/ → ./skills/ (custom skill SKILL.md files)
    └── opencode container          (port 9081 → web preview, 2223 → SSH)
        ├── Full in-container permissions (root, cap ALL-SYS_ADMIN, seccomp off)
        ├── Reaches internet via bridge NAT → Anthropic API
        ├── /exchange  → .\shared\  (host ↔ agent files)
        └── /agent-exchange → agent-exchange volume     (agent ↔ agent files)
```

### How Components Communicate

| From | To | Method |
|---|---|---|
| Paperclip (host) | OpenClaw (container) | `http://localhost:18789` via mapped port |
| Browser (host) | OpenClaw Control UI | `http://localhost:18789` — built-in web dashboard |
| Browser (host) | OpenClaw web preview | `http://localhost:9080` — agent starts any server on container port 8080 |
| Browser (host) | OpenCode web preview | `http://localhost:9081` — agent starts any server on container port 8080 |
| SSH client (host) | OpenCode terminal | `ssh opencode` → `ssh root@localhost -p 2223` |
| docker exec | OpenClaw terminal | `docker exec -it openclaw bash` |
| docker exec | OpenCode TUI | `docker exec -it opencode opencode` |
| OpenClaw (container) | AWS Bedrock | `https://bedrock-runtime.us-east-1.amazonaws.com` (outbound HTTPS) |
| OpenClaw (container) | Anthropic API | `https://api.anthropic.com` (outbound HTTPS) |
| OpenCode (container) | Anthropic API | `https://api.anthropic.com` (outbound HTTPS) |
| Paperclip (host) | AWS Bedrock / Anthropic | Direct outbound HTTPS from host |
| Paperclip → Agents (files) | `.\shared\inbox\` | Bind mount → `/exchange/inbox/` in containers |
| Agents → Paperclip (files) | `/exchange/outbox/` in containers | Bind mount → `.\shared\outbox\` on host |
| OpenClaw ↔ OpenCode (files) | `/agent-exchange/` in both containers | Shared named Docker volume |
| Brave Search (openclaw built-in plugin) | Brave Search API | HTTPS outbound via bridge NAT |
| Yahoo Finance (curl/node via SKILL.md) | Yahoo Finance REST API | HTTPS outbound via bridge NAT |
| Containers | Internet | Docker bridge NAT |

---

## Security Model

### What agents CAN do (inside their container)
- Run as root
- Use all Linux capabilities except `SYS_ADMIN`
- Make any syscall the kernel supports (seccomp unconfined)
- Fork unlimited processes
- Use large shared memory segments
- Reach the internet (required for Bedrock/Anthropic API calls)
- Read and write files in `/exchange` — a single, scoped bind mount to the exchange directory only
- Read and write files in `/agent-exchange` — a Docker volume shared between agents, not accessible from the host

### What agents CANNOT do (host isolation)
- See or signal host processes (`pid: host` is omitted — own PID namespace only)
- Access host shared memory or IPC (`ipc: private`)
- Control the host Docker daemon (no `/var/run/docker.sock` mount)
- Read or write any host path outside `/exchange`
- Bind to host network interfaces (bridge only)
- Remap UID 0 to host root (`userns_mode: host` is omitted)
- Load kernel modules or escape via cgroup breakout (`SYS_ADMIN` is dropped)

---

## Prerequisites

### 1 — Verify Node.js and install pnpm

```powershell
node --version   # 20+ sufficient (stack runs in Docker with node:24)
npm install -g pnpm@latest
pnpm --version   # Must be 9.15+
```

### 2 — Verify Docker is running

```powershell
docker --version
docker ps
```

### 3 — Clone the required repos

This project builds openclaw, opencode, and paperclip **from source**. They must be cloned as sibling directories next to `agentyard`:

```
parent-dir/
├── agentyard/     ← this repo
├── openclaw/      ← required: agent gateway
├── opencode/      ← required: coding agent
└── paperclip/     ← required: orchestrator
```

From the **parent directory** that contains `agentyard`:

```powershell
git clone https://github.com/openclawai/openclaw
git clone https://github.com/sst/opencode
git clone https://github.com/paperclipai/paperclip
```

Verify all three are present:

```powershell
Test-Path ..\openclaw\Dockerfile        # openclaw repo
Test-Path ..\paperclip\package.json     # paperclip repo
Test-Path ..\opencode\packages\opencode  # opencode repo
```

---

## Step 1 — Create the Workspace Directory and Exchange Dirs

Clone or create the `agentyard` project directory, then from within it:

```powershell
mkdir config
mkdir shared
mkdir shared\inbox
mkdir shared\outbox
mkdir shared\workspace
mkdir skills
mkdir skills\yahoo-finance
```

---

## Step 1.5 — Obtain API Keys

### Anthropic API Key
1. Go to **https://console.anthropic.com/**
2. Create an account and generate an API key (looks like `sk-ant-api03-...`)

### AWS Bedrock Access
1. Create an IAM user with `AmazonBedrockFullAccess` policy (or scoped to specific models)
2. Generate access keys: `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`
3. Ensure the us-east-1 region has model access enabled in the AWS Bedrock console

### Brave Search API Key (required for openclaw web search)
1. Go to **https://brave.com/search/api/**
2. Create a free account and get an API key (looks like `BSA...`)
3. Free tier: **2,000 queries/month**, no credit card required

### Yahoo Finance — No API Key Required

Yahoo Finance data is fetched directly via public REST endpoints using curl/node inside the container.

---

## Step 2 — Create the .env File

Create `.env` in the project root:

```env
BRAVE_API_KEY=BSAyour-key-here

# SSH password for opencode container terminal access
OPENCLAW_SSH_PASS=change_me_openclaw
OPENCODE_SSH_PASS=change_me_opencode

# Gateway auth token for openclaw (generate with: openssl rand -hex 20)
OPENCLAW_GATEWAY_TOKEN=your-token-here

# Anthropic API
ANTHROPIC_API_KEY=sk-ant-api03-your-key-here

# AWS Bedrock
AWS_ACCESS_KEY_ID=your-access-key-id
AWS_SECRET_ACCESS_KEY=your-secret-access-key
AWS_REGION=us-east-1
AWS_DEFAULT_REGION=us-east-1
AWS_REGION_NAME=us-east-1
```

**Never commit this file to version control.**

---

## Step 3 — Build OpenClaw from Source

### IMPORTANT: Do NOT modify the openclaw Dockerfile

openclaw's Dockerfile at `../openclaw/Dockerfile` must not be changed. All capability extensions go through:
- **Brave Search**: built-in plugin, auto-enabled by `BRAVE_API_KEY` env var
- **Yahoo Finance and other tools**: `SKILL.md` files mounted into `/app/skills/`
- **MCP servers**: `mcpServers` section in `config/openclaw.json` (only if the npm package actually exists)

### 3a — Build the Docker image

```powershell
cd ..\openclaw
docker build -t openclaw:local .
```

### 3b — Create openclaw's runtime config

Create `.\config\openclaw.json`:

```json
{
  "gateway": {
    "mode": "local",
    "bind": "lan",
    "port": 18789,
    "auth": {
      "mode": "token"
    }
  },
  "models": {
    "providers": {
      "amazon-bedrock": {
        "api": "bedrock-converse-stream",
        "auth": "aws-sdk",
        "baseUrl": "https://bedrock-runtime.us-east-1.amazonaws.com",
        "models": [
          { "id": "us.amazon.nova-2-lite-v1:0", "name": "Amazon Nova 2 Lite" }
        ]
      },
      "anthropic": {
        "models": [
          { "id": "claude-haiku-4-5-20251001", "name": "Claude Haiku 4.5" }
        ]
      }
    }
  },
  "agents": {
    "defaults": {
      "model": "amazon-bedrock/us.amazon.nova-2-lite-v1:0",
      "sandbox": {
        "mode": "off"
      }
    }
  }
}
```

**Config schema notes:**
- Root key is `models.providers` (not `agent` or `provider`)
- Provider URL is `baseUrl` (not `baseURL`)
- Each model entry requires both `id` AND `name`
- Auth mode must be `"token"` for LAN binding (not `"trusted"`)
- `gateway.mode: "local"` is required
- Gateway token comes from `OPENCLAW_GATEWAY_TOKEN` env var
- Anthropic API key comes from `ANTHROPIC_API_KEY` env var (no need to set in config)
- AWS credentials come from `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` env vars

---

## Step 4 — Build OpenCode from Source

OpenCode has no upstream Dockerfile. Use the one in this repo (or create it at `../opencode/Dockerfile`):

```dockerfile
# Build stage: compile opencode binary using Bun
FROM oven/bun:1.3.13 AS builder

WORKDIR /build

# Build tools required for native addons (tree-sitter-powershell, node-pty, etc.)
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 make g++ git && \
    rm -rf /var/lib/apt/lists/*

COPY . .
RUN bun install --frozen-lockfile

WORKDIR /build/packages/opencode
RUN bun run script/build.ts --single --skip-embed-web-ui

# Runtime stage
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates git curl ripgrep bash nodejs npm openssh-server procps && \
    rm -rf /var/lib/apt/lists/*

COPY --from=builder /build/packages/opencode/dist/opencode-linux-x64/bin/opencode /usr/local/bin/opencode
RUN chmod +x /usr/local/bin/opencode

RUN mkdir -p /var/run/sshd /root/.ssh /workspace/.opencode && \
    chmod 700 /root/.ssh && \
    sed -i 's|#PermitRootLogin prohibit-password|PermitRootLogin yes|' /etc/ssh/sshd_config && \
    sed -i 's|#PasswordAuthentication yes|PasswordAuthentication yes|' /etc/ssh/sshd_config && \
    sed -i 's|UsePAM yes|UsePAM no|' /etc/ssh/sshd_config

WORKDIR /workspace

EXPOSE 22

CMD ["/bin/bash", "-c", "echo \"root:${OPENCODE_SSH_PASS:-opencode}\" | chpasswd && /usr/sbin/sshd -D"]
```

Build it:
```powershell
cd ..\opencode
docker build -t opencode:local .
# Takes 5-15 minutes on first run (Bun compilation of native addons)
```

### Create opencode's runtime config

Create `.\config\opencode.jsonc`:

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "anthropic": {},
    "amazon-bedrock": {
      "options": {
        "region": "us-east-1"
      }
    }
  },
  "model": "anthropic/claude-haiku-4-5-20251001"
}
```

Credentials come from env vars: `ANTHROPIC_API_KEY` for Anthropic, `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` for Bedrock.

---

## Step 5 — Add Yahoo Finance Skill

Create `.\skills\yahoo-finance\SKILL.md`:

```markdown
---
name: yahoo-finance
description: Get real-time stock quotes, historical OHLCV data, financial statements, analyst ratings, and market summaries from Yahoo Finance.
---

# Yahoo Finance Skill

Retrieve live and historical financial data from Yahoo Finance. No API key required.

## Commands

### Real-time Quote

\`\`\`bash
curl -s "https://query1.finance.yahoo.com/v8/finance/chart/AAPL?interval=1d&range=1d" \
  -H "User-Agent: Mozilla/5.0" | \
  node -e "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); \
    const r=d.chart.result[0]; const m=r.meta; \
    console.log(JSON.stringify({symbol:m.symbol,price:m.regularMarketPrice,currency:m.currency},null,2))"
\`\`\`

## Parameters

| Parameter | Values |
|---|---|
| interval | 1m 5m 15m 1h 1d 1wk 1mo |
| range | 1d 5d 1mo 3mo 6mo 1y 2y 5y max |

Replace AAPL with any ticker. node is available in the container.
```

---

## Step 6 — Create the Docker Compose File

Create `docker-compose.yml` in the project root:

```yaml
networks:
  agent-net:
    driver: bridge

volumes:
  openclaw-workspace:
  opencode-workspace:
  agent-exchange:

services:

  openclaw:
    image: openclaw:local
    build:
      context: ../openclaw
    container_name: openclaw
    restart: unless-stopped
    networks:
      - agent-net
    ports:
      - "18789:18789"   # Gateway + Control UI
      - "9080:8080"     # Web preview
    extra_hosts:
      - "host.docker.internal:host-gateway"
    dns:
      - 8.8.8.8
      - 1.1.1.1
    env_file:
      - .env
    environment:
      - BRAVE_API_KEY=${BRAVE_API_KEY}
      - OPENCLAW_CONFIG_PATH=/config/openclaw.json
      - OPENCLAW_ALLOW_ROOT=1
      - OPENCLAW_GATEWAY_TOKEN=${OPENCLAW_GATEWAY_TOKEN}
      - ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
      - AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
      - AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
      - AWS_REGION=${AWS_REGION}
      - AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION}
      - AWS_REGION_NAME=${AWS_REGION_NAME}
    user: root
    ...
    volumes:
      - ./config/openclaw.json:/config/openclaw.json:ro
      - ./skills:/app/skills/agentyard:ro
      - openclaw-workspace:/root/.openclaw/workspace
      - ./shared:/exchange
      - agent-exchange:/agent-exchange

  opencode:
    image: opencode:local
    build:
      context: ../opencode
    container_name: opencode
    ...
    environment:
      - BRAVE_API_KEY=${BRAVE_API_KEY}
      - OPENCODE_SSH_PASS=${OPENCODE_SSH_PASS}
      - ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
      - AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
      - AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
      - AWS_REGION=${AWS_REGION}
      - AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION}
      - AWS_REGION_NAME=${AWS_REGION_NAME}
    volumes:
      - ./config/opencode.jsonc:/workspace/.opencode/opencode.jsonc:ro
      - opencode-workspace:/workspace
      - ./shared:/exchange
      - agent-exchange:/agent-exchange
```

---

## Step 7 — Build and Start the Containers

```powershell
# From the project root

# Build both images
docker compose build

# Start both containers
docker compose up -d

# Check status (both should show "healthy" after ~30 seconds)
docker compose ps
```

---

## Step 7.5 — Set Up SSH Access to OpenCode

Generate a key pair **without a passphrase** (required for non-interactive use):

```powershell
ssh-keygen -t ed25519 -C "opencode-key" -f "$env:USERPROFILE\.ssh\id_opencode" -N '""'
```

Inject the public key into the running container:

```powershell
$pubkey = (Get-Content "$env:USERPROFILE\.ssh\id_opencode.pub" -Raw).Trim()
docker exec opencode sh -c "echo '$pubkey' > /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys"
```

Add SSH config (create or append to `~/.ssh/config` — ensure no UTF-8 BOM):

```
Host opencode
    HostName localhost
    Port 2223
    User root
    IdentityFile ~/.ssh/id_opencode
    StrictHostKeyChecking no
```

Test:

```powershell
ssh opencode "echo 'SSH OK' && opencode --version"
```

**Note:** The `id_opencode` key MUST be generated without a passphrase. A passphrase-encrypted key fails non-interactively because the client cannot open `/dev/tty` to prompt for the passphrase.

**Note:** If recreating the container, re-inject the public key — the `/root/.ssh/authorized_keys` file lives in the container filesystem, not in a volume.

---

## Step 8 — Configure and Start Paperclip on the Host

```powershell
cd ..\paperclip
pnpm install
copy .env.example .env
```

Edit `..\paperclip\.env`:

```env
DATABASE_URL=postgres://paperclip:paperclip@localhost:5432/paperclip
PORT=3100
SERVE_UI=false
BETTER_AUTH_SECRET=paperclip-dev-secret

ANTHROPIC_API_KEY=sk-ant-api03-your-key-here

AWS_ACCESS_KEY_ID=your-access-key-id
AWS_SECRET_ACCESS_KEY=your-secret-access-key
AWS_REGION_NAME=us-east-1
AWS_REGION=us-east-1
AWS_DEFAULT_REGION=us-east-1

# Set these to the absolute path of the agentyard shared directory
PAPERCLIP_EXCHANGE_DIR=<path-to-agentyard>\shared
PAPERCLIP_INBOX_DIR=<path-to-agentyard>\shared\inbox
PAPERCLIP_OUTBOX_DIR=<path-to-agentyard>\shared\outbox
```

Start Paperclip:

```powershell
pnpm dev
# Wait for: API server ready at http://localhost:3100
```

---

## Step 9 — Register Agents in Paperclip

Open **http://localhost:3100** in your browser.

### Register OpenClaw

1. Go to **Org Chart → Hire Agent**
2. Adapter type: **OpenClaw**
3. Endpoint URL: `http://localhost:18789`
4. Auth token: value of `OPENCLAW_GATEWAY_TOKEN` from `.env`
5. Set a role and click **Hire**

### Register OpenCode

OpenCode is a coding sandbox accessed via SSH, not an HTTP API. Integrate as appropriate for your Paperclip version (SSH adapter or custom).

---

## Step 10 — Startup Order for Every Session

```powershell
# 1. Start Docker containers (from agentyard project root)
docker compose up -d

# 2. Re-inject SSH key if containers were recreated
$pubkey = (Get-Content "$env:USERPROFILE\.ssh\id_opencode.pub" -Raw).Trim()
docker exec opencode sh -c "echo '$pubkey' >> /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys" 2>$null

# 3. Start Paperclip
cd ..\paperclip
pnpm dev
```

---

## Port Summary

| Port (host) | Container | Purpose |
|---|---|---|
| `18789` | openclaw | Gateway + Control UI (`http://localhost:18789`) |
| `9080` | openclaw | Web preview (agent servers on port 8080) |
| `9081` | opencode | Web preview (agent servers on port 8080) |
| `2223` | opencode | SSH terminal (`ssh opencode`) |

---

## Full Verification Checklist

```powershell
# Containers running
docker compose ps
# ✓ openclaw   Up X minutes (healthy)
# ✓ opencode   Up X minutes (healthy)

# Host → openclaw gateway
curl http://localhost:18789/healthz
# ✓ 200 OK

# Internet access from containers (required for API calls)
docker exec openclaw sh -c "curl -s https://api.anthropic.com" | head -c 100
docker exec opencode sh -c "curl -s https://api.anthropic.com" | head -c 100
# ✓ Both reach Anthropic

# Bedrock connectivity from openclaw
docker exec openclaw sh -c "curl -s -o /dev/null -w '%{http_code}' https://bedrock-runtime.us-east-1.amazonaws.com/"
# ✓ 200 or 403 (403 means reachable, just needs auth)

# SSH to opencode
ssh opencode "echo 'SSH OK' && opencode --version"
# ✓ SSH OK / version string

# File exchange host → container
echo "test" | Out-File .\shared\inbox\test.txt -Encoding UTF8
docker exec openclaw sh -c "cat /exchange/inbox/test.txt"
# ✓ test

# File exchange container → host
docker exec openclaw sh -c "echo 'agent output' > /exchange/outbox/result.txt"
Get-Content .\shared\outbox\result.txt
# ✓ agent output

# Agent ↔ agent exchange
docker exec openclaw sh -c "echo 'from openclaw' > /agent-exchange/handoff.txt"
docker exec opencode sh -c "cat /agent-exchange/handoff.txt"
# ✓ from openclaw

# Brave search (openclaw built-in)
docker exec openclaw sh -c "echo $BRAVE_API_KEY" 2>&1
# ✓ Shows the key (not empty)

# Yahoo Finance skill is mounted
docker exec openclaw sh -c "cat /app/skills/agentyard/yahoo-finance/SKILL.md" 2>&1 | head -5
# ✓ Shows SKILL.md frontmatter

# Paperclip
curl http://localhost:3100/api/health
# ✓ OK
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `Refusing to bind gateway to lan without auth` | `OPENCLAW_GATEWAY_TOKEN` not set or empty | Add to `.env` and `docker compose up -d openclaw` |
| `Unrecognized key: "agent"` in openclaw logs | Wrong config format — old `"agent"` root key | Use `models.providers` structure as shown in Step 3b |
| `Invalid input: expected string, received undefined` (models) | Model entries missing `name` field | Add `"name": "..."` to each model in provider config |
| `Gateway start blocked: existing config is missing gateway.mode` | `gateway.mode` absent from config | Add `"mode": "local"` to the `gateway` block |
| openclaw container keeps restarting with "Refusing to run as root" | Missing `OPENCLAW_ALLOW_ROOT=1` | Add to environment in docker-compose.yml |
| SSH to opencode: `Permission denied (publickey,password)` | Key has a passphrase — can't sign non-interactively | Regenerate key without passphrase: `ssh-keygen ... -N '""'` |
| SSH to opencode fails after container recreate | `authorized_keys` is in container filesystem | Re-inject public key after each recreate |
| openclaw `"bind": "lan"` rejected without auth | Auth mode is `"trusted"` — not valid for LAN | Change `gateway.auth.mode` to `"token"` |
| `docker compose build` fails on Bun download | Network timeout | Re-run — Docker layer caching resumes from where it stopped |
| opencode healthcheck fails (`ss` not found) | `iproute2` not installed | Use `pgrep -x sshd` as the healthcheck command instead |
| `docker ps` shows `unhealthy` | Container startup crash | Run `docker logs openclaw` or `docker logs opencode` |
| Brave search returns 401 | Invalid API key | Check `BRAVE_API_KEY` in `.env` |
| Brave search returns 429 | Free tier quota exceeded (2000/month) | Wait for quota reset or upgrade plan |
| Agent cannot write to `/exchange` | Docker Desktop file sharing not enabled | Add the project's parent directory in Docker Desktop → Settings → Resources → File Sharing |
| SSH config causes parse error (`no argument after keyword`) | Config file has UTF-8 BOM | Rewrite `~/.ssh/config` using `printf` in bash, not PowerShell `Out-File` |
| Bedrock calls return 403 | IAM user lacks Bedrock permissions | Add `AmazonBedrockFullAccess` policy or scope to specific model ARNs |
| Bedrock calls return connection refused | Wrong region | Ensure `AWS_REGION=us-east-1` in `.env` and model is available in that region |
| Anthropic calls return 401 | Invalid API key | Check `ANTHROPIC_API_KEY` in `.env` |

## Security Decision Reference

The following settings were **deliberately omitted** from the Docker Compose file:

| Setting | Why omitted |
|---|---|
| `privileged: true` | Grants access to all host block devices |
| `pid: host` | Container can see and signal every host process |
| `ipc: host` | Container can read and write host shared memory |
| `userns_mode: host` | Makes UID 0 inside = UID 0 on host |
| `network_mode: host` | Eliminates network boundary |
| `/var/run/docker.sock` mount | Full host Docker control — trivially exploitable for escape |
| `/:/host` volume | Full host filesystem access |

The following was **deliberately included** as a scoped exception:

| Setting | Why included | Why it is safe |
|---|---|---|
| `.\shared:/exchange` | Paperclip ↔ agent file exchange | Exposes only one specific directory. No executables, credentials, or sensitive config inside. |

---

## Skills System (openclaw)

openclaw scans for `SKILL.md` files recursively under `/app/skills/`. Custom skills are mounted as a subdirectory alongside bundled skills:

```
/app/skills/
├── brave/           ← bundled
├── canvas/          ← bundled
└── agentyard/       ← ./skills/ (mounted :ro)
    └── yahoo-finance/
        └── SKILL.md
```

Each `SKILL.md` has YAML frontmatter (`name`, `description`) followed by markdown documentation including bash/curl/node commands the agent can run. The agent reads the skill documentation and executes the commands directly — no separate MCP server process needed.

To add a new skill:
1. Create `skills/<skill-name>/SKILL.md` in the project root
2. No container rebuild or restart needed (volume mount is live)

---

*Platform: Windows 11 Pro, 64 GB RAM, Docker Desktop, Git Bash*
*Repos: openclaw · opencode · paperclip — expected as sibling directories alongside agentyard*
*Model providers: AWS Bedrock (Nova 2 Lite, primary) · Anthropic (Claude Haiku 4.5, secondary)*
