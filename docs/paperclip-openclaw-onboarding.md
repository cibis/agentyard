# Connecting openclaw to Paperclip

This document records the exact steps taken to register the openclaw gateway as an agent in a Paperclip organization. Repeat these steps on a new machine or after a full tear-down.

---

## Prerequisites

- openclaw is running and healthy: `curl http://localhost:18789/healthz` returns `{"ok":true}`
- Paperclip is running on the host at `http://localhost:3100`
- You have a Paperclip invite code (e.g. `pcp_invite_ld0nllty`)
- `OPENCLAW_GATEWAY_TOKEN` is set in `.env`

---

## Step 1 — Fetch the onboarding instructions

Paperclip provides a machine-readable onboarding guide at the invite URL. Fetch it to understand required steps and locate the skill endpoint:

```powershell
Invoke-WebRequest -Uri "http://localhost:3100/api/invites/<invite-code>/onboarding.txt" -UseBasicParsing | Select-Object -ExpandProperty Content
```

Note which Paperclip base URL is reachable. For a fully local setup `http://localhost:3100` works from the host.

---

## Step 2 — Read the gateway token

The token is in `.env` as `OPENCLAW_GATEWAY_TOKEN`. Extract it:

```powershell
$token = (Get-Content c:\PROJECTS\agentyard\.env | Where-Object { $_ -match '^OPENCLAW_GATEWAY_TOKEN=' }) -replace '^OPENCLAW_GATEWAY_TOKEN=',''
```

---

## Step 3 — Test which gateway URL Paperclip can reach

Paperclip needs to connect back to openclaw over WebSocket. Use the invite's `test-resolution` endpoint to check reachability. URL-encode the candidate `ws://` URL and pass it as a query parameter:

```powershell
# Example — test ws://127.0.0.1:18789
$url = [System.Uri]::EscapeDataString("ws://127.0.0.1:18789")
Invoke-WebRequest -Uri "http://localhost:3100/api/invites/<invite-code>/test-resolution?url=$url" -UseBasicParsing | Select-Object -ExpandProperty Content
```

Candidates to try (in order):
1. `ws://127.0.0.1:18789`
2. `ws://localhost:18789`
3. `ws://host.docker.internal:18789`
4. `ws://<host-LAN-IP>:18789`

For a fully local setup where Paperclip and openclaw both run on the same host, `ws://127.0.0.1:18789` is used. The test-resolution endpoint will flag all private/loopback addresses as warnings — this is expected and safe for local deployments; proceed with `ws://127.0.0.1:18789`.

---

## Step 4 — Submit the join request

```powershell
$body = @{
    requestType = "agent"
    agentName   = "OpenClaw"
    adapterType = "openclaw_gateway"
    capabilities = "OpenClaw agent adapter"
    agentDefaultsPayload = @{
        url             = "ws://127.0.0.1:18789"
        paperclipApiUrl = "http://host.docker.internal:3100"
        headers         = @{ "x-openclaw-token" = $token }
        waitTimeoutMs   = 120000
        sessionKeyStrategy = "issue"
        role   = "operator"
        scopes = @("operator.admin")
    }
} | ConvertTo-Json -Depth 5

$response = Invoke-WebRequest -Uri "http://localhost:3100/api/invites/<invite-code>/accept" `
    -Method POST `
    -ContentType "application/json" `
    -Body $body `
    -UseBasicParsing

$response.Content | ConvertFrom-Json
```

Expected: HTTP 202 with a JSON body containing:
- `id` — the join request ID (save this)
- `claimSecret` — one-time secret for claiming the API key (save this, it expires in ~7 days)
- `status: "pending_approval"`

Paperclip generates a persistent `devicePrivateKeyPem` for stable pairing if you omit it from the payload.

---

## Step 5 — Board approval (manual)

A board member must approve the join request in the Paperclip UI before the API key can be claimed. Wait for confirmation, then proceed to Step 6.

---

## Step 6 — Claim the API key

After approval, claim the API key using the request ID and claim secret from Step 4:

```powershell
$claimBody = @{ claimSecret = "<claim-secret-from-step-4>" } | ConvertTo-Json

$claimed = Invoke-WebRequest `
    -Uri "http://localhost:3100/api/join-requests/<request-id-from-step-4>/claim-api-key" `
    -Method POST `
    -ContentType "application/json" `
    -Body $claimBody `
    -UseBasicParsing

$claimed.Content  # contains the API key (token field)
```

Save the full response JSON inside the container for reference:

```powershell
$claimed.Content | docker exec -i openclaw sh -c "cat > /root/.openclaw/workspace/paperclip-claimed-api-key.json && chmod 600 /root/.openclaw/workspace/paperclip-claimed-api-key.json"
```

---

## Step 7 — Add env vars to .env and docker-compose.yml

Append to `.env`:

```
PAPERCLIP_API_KEY=<token from claim response>
PAPERCLIP_API_URL=http://host.docker.internal:3100
```

`PAPERCLIP_API_URL` uses `host.docker.internal` (not `localhost`) so openclaw inside Docker can reach Paperclip on the host.

Add both vars to the `environment` section of the `openclaw` service in `docker-compose.yml`:

```yaml
environment:
  - PAPERCLIP_API_KEY=${PAPERCLIP_API_KEY}
  - PAPERCLIP_API_URL=${PAPERCLIP_API_URL}
```

---

## Step 8 — Install the Paperclip skill

The skill must be saved on the **host** under `skills/paperclip/SKILL.md` so it is bind-mounted into the container at `/app/skills/agentyard/paperclip/SKILL.md` and survives rebuilds. Do **not** write it inside the container.

```powershell
New-Item -ItemType Directory -Path "c:\PROJECTS\agentyard\skills\paperclip" -Force

$skill = Invoke-WebRequest -Uri "http://localhost:3100/api/invites/<invite-code>/skills/paperclip" -UseBasicParsing | Select-Object -ExpandProperty Content
$header = "<!-- PAPERCLIP_API_URL=http://host.docker.internal:3100 -->`n"
($header + $skill) | Out-File -FilePath "c:\PROJECTS\agentyard\skills\paperclip\SKILL.md" -Encoding utf8
```

The skill is ~29 KB and teaches openclaw the full Paperclip heartbeat protocol.

---

## Step 9 — Recreate openclaw to pick up the new env vars

A plain `restart` does not re-read `.env`; you must recreate the container:

```powershell
Set-Location c:\PROJECTS\agentyard
docker compose up -d openclaw
```

Verify the env vars are injected:

```powershell
docker exec openclaw sh -c "echo PAPERCLIP_API_KEY=$PAPERCLIP_API_KEY; echo PAPERCLIP_API_URL=$PAPERCLIP_API_URL"
```

Verify the skill is mounted:

```powershell
docker exec openclaw sh -c "test -f /app/skills/agentyard/paperclip/SKILL.md && echo OK"
```

Health check:

```powershell
curl http://localhost:18789/healthz
# expected: {"ok":true,"status":"live"}
```

---

## Step 10 — Commit the skill file

The skill file is not auto-generated at container startup — it must be in the repo so it is present on any new machine:

```powershell
git add skills/paperclip/SKILL.md
git commit -m "feat: add Paperclip skill for openclaw"
```

---

## What survives what

| Scenario | Skill file | API key env vars |
|---|---|---|
| `docker compose restart openclaw` | ✓ (bind mount) | ✓ (env_file) |
| `docker compose up -d --build openclaw` | ✓ (bind mount) | ✓ (env_file) |
| `docker compose down` + `up` | ✓ (bind mount) | ✓ (env_file) |
| New machine, repo cloned | ✓ if committed | ✓ if `.env` copied |
| `docker compose down -v` | ✓ (bind mount) | ✓ (env_file) |

The only thing that does **not** transfer automatically to a new machine is `.env` (which contains secrets). Copy it manually or provision the values through your secrets manager.

---

## Result

- Agent name: **OpenClaw**
- Organization: **MINT**
- Adapter type: `openclaw_gateway`
- Gateway URL (Paperclip → openclaw): `ws://127.0.0.1:18789`
- Paperclip API URL (openclaw → Paperclip): `http://host.docker.internal:3100`
- Skill mounted at: `/app/skills/agentyard/paperclip/SKILL.md`

---

## Updating an Existing Agent

If an agent is already registered in Paperclip (e.g. via the UI or a previous invite) and you need to point it at openclaw — or refresh its token/URL — use `PATCH /api/agents/:id`. No invite code is required.

### Step A — Read the gateway token

```powershell
$token = (Get-Content c:\PROJECTS\agentyard\.env | Where-Object { $_ -match '^OPENCLAW_GATEWAY_TOKEN=' }) -replace '^OPENCLAW_GATEWAY_TOKEN=',''
```

### Step B — Find the company ID and agent ID

The agents list endpoint requires the company ID. Get both in one call:

```powershell
# Step B1 — get the company ID
$companies = Invoke-WebRequest -Uri "http://localhost:3100/api/companies" `
    -Headers @{ Authorization = "Bearer <api-key>" } `
    -UseBasicParsing | Select-Object -ExpandProperty Content | ConvertFrom-Json

$companyId = $companies[0].id
$companyId   # verify

# Step B2 — list agents and find the target
$agents = Invoke-WebRequest -Uri "http://localhost:3100/api/companies/$companyId/agents" `
    -Headers @{ Authorization = "Bearer <api-key>" } `
    -UseBasicParsing | Select-Object -ExpandProperty Content | ConvertFrom-Json

$agentId = ($agents | Where-Object { $_.name -eq "OpenClaw" }).id
$agentId  # verify it looks right before patching
```

> **Note:** The agent list endpoint is `GET /api/companies/:companyId/agents`, not `GET /api/agents`. The company ID can also be read from any existing agent record's `companyId` field.

### Step C — PATCH the agent

`replaceAdapterConfig: true` tells Paperclip to swap the entire adapter config (not merge it). Use the same `adapterConfig` fields as the original join request:

```powershell
$body = @{
    adapterType          = "openclaw_gateway"
    replaceAdapterConfig = $true
    adapterConfig        = @{
        url                = "ws://127.0.0.1:18789"
        paperclipApiUrl    = "http://host.docker.internal:3100"
        headers            = @{ "x-openclaw-token" = $token }
        waitTimeoutMs      = 120000
        sessionKeyStrategy = "issue"
        role               = "operator"
        scopes             = @("operator.admin")
    }
} | ConvertTo-Json -Depth 5

$result = Invoke-WebRequest -Uri "http://localhost:3100/api/agents/$agentId" `
    -Method PATCH `
    -Headers @{ Authorization = "Bearer <api-key>" } `
    -ContentType "application/json" `
    -Body $body `
    -UseBasicParsing

$result.Content | ConvertFrom-Json | Select-Object id, name, adapterType
```

> **Multiple named agents:** If openclaw is configured with an `agents.list` (multiple personas), add `agentId = "<openclaw-agent-id>"` inside `adapterConfig` so Paperclip routes each task to the correct openclaw agent. The value must match the `id` field in the `agents.list` entry in `config/openclaw.json`.

Expected: HTTP 200 with the updated agent object showing `adapterType: "openclaw_gateway"` and the new `adapterConfig`.

### Step D — Verify in the UI

Open the Paperclip UI → **Agents** → **OpenClaw** → **Settings** and confirm the adapter type and gateway URL match what you patched.

> **Note on device keys:** Paperclip auto-generates an Ed25519 `devicePrivateKeyPem` for `openclaw_gateway` agents if one is not present and device auth is enabled. This key is persisted server-side and does not need to be supplied in the PATCH payload.
