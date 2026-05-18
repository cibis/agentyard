# Connecting opencode to Paperclip

This document records the exact steps to point an existing Paperclip agent (in the MINT organisation) at the opencode container via SSH, using the `opencode_local` adapter. Repeat these steps on a new machine or after a full tear-down.

---

## Prerequisites

- opencode is running and healthy:
  ```powershell
  docker compose ps opencode   # State should be "running (healthy)"
  ```
- SSH access to opencode works non-interactively:
  ```powershell
  ssh opencode -o BatchMode=yes -o ConnectTimeout=5 exit
  # should exit silently with code 0
  ```
  SSH config (`~/.ssh/config`) must have the `opencode` host alias pointing to `localhost:2223` with key `~/.ssh/id_opencode` (no passphrase).
- Paperclip is running on the host at `http://localhost:3100`
- You have a board-member API key (Paperclip UI → **Settings → API Keys**)
- The agent you want to wire up already exists in Paperclip (no invite flow needed — just a PATCH)

---

## Step 1 — Verify SSH key has no passphrase

The opencode container requires non-interactive SSH. If the key has a passphrase, the adapter will hang.

```powershell
ssh-keygen -y -P "" -f C:\Users\i8329\.ssh\id_opencode | Out-Null
if ($?) { "OK — no passphrase" } else { "ERROR — key has a passphrase; regenerate without one" }
```

---

## Step 2 — Discover the company ID and agent ID

Fetch the full agent list. Every agent record includes `companyId` — all agents in a single-tenant Paperclip instance share one company.

```powershell
$apiKey = "<board-member-api-key>"

$agents = Invoke-WebRequest -Uri "http://localhost:3100/api/agents" `
    -Headers @{ Authorization = "Bearer $apiKey" } `
    -UseBasicParsing | Select-Object -ExpandProperty Content | ConvertFrom-Json

$agents | Select-Object id, name, adapterType, status
$companyId = $agents[0].companyId
$companyId   # save this

# Find the target agent ID (e.g. "Full Stack Developer"):
$agentId = ($agents | Where-Object { $_.name -eq "Full Stack Developer" }).id
$agentId   # verify before proceeding
```

---

## Step 3 — Check for an existing SSH environment

Paperclip stores SSH connection details as reusable *environments*. Check if one already exists for opencode:

```powershell
$envs = Invoke-WebRequest `
    -Uri "http://localhost:3100/api/companies/$companyId/environments?driver=ssh" `
    -Headers @{ Authorization = "Bearer $apiKey" } `
    -UseBasicParsing | Select-Object -ExpandProperty Content | ConvertFrom-Json

$envs | Select-Object id, name, driver
```

If an environment named **"OpenCode SSH"** (or equivalent) already appears, note its `id` and skip to Step 5.

---

## Step 4 — Create the SSH environment

```powershell
$privateKey = Get-Content C:\Users\i8329\.ssh\id_opencode -Raw

$envBody = @{
    name   = "OpenCode SSH"
    driver = "ssh"
    config = @{
        host                  = "127.0.0.1"
        port                  = 2223
        username              = "root"
        remoteWorkspacePath   = "/workspace"
        privateKey            = $privateKey
        strictHostKeyChecking = $false
    }
} | ConvertTo-Json -Depth 5

$newEnv = Invoke-WebRequest `
    -Uri "http://localhost:3100/api/companies/$companyId/environments" `
    -Method POST `
    -Headers @{ Authorization = "Bearer $apiKey" } `
    -ContentType "application/json" `
    -Body $envBody `
    -UseBasicParsing

$envId = ($newEnv.Content | ConvertFrom-Json).id
$envId   # save this
```

Expected: HTTP 201 with a JSON body containing `id`, `name: "OpenCode SSH"`, `driver: "ssh"`.

**Why `127.0.0.1` and not `localhost`?** Paperclip runs on the host and makes the SSH connection directly — no Docker networking involved. `127.0.0.1:2223` is the host-side port mapped from the opencode container.

**Why `strictHostKeyChecking: false`?** The container's host key changes on every rebuild. Disabling strict checking prevents failures after `docker compose up -d --build opencode`.

---

## Step 5 — PATCH the agent to opencode_local

```powershell
$body = @{
    adapterType          = "opencode_local"
    replaceAdapterConfig = $true
    adapterConfig        = @{
        model                      = "anthropic/claude-haiku-4-5-20251001"
        cwd                        = "/workspace"
        dangerouslySkipPermissions = $true
    }
    defaultEnvironmentId = $envId
} | ConvertTo-Json -Depth 5

$result = Invoke-WebRequest -Uri "http://localhost:3100/api/agents/$agentId" `
    -Method PATCH `
    -Headers @{ Authorization = "Bearer $apiKey" } `
    -ContentType "application/json" `
    -Body $body `
    -UseBasicParsing

$result.Content | ConvertFrom-Json | Select-Object id, name, adapterType, defaultEnvironmentId
```

Expected: HTTP 200 with `adapterType: "opencode_local"` and `defaultEnvironmentId` matching `$envId`.

**adapterConfig fields:**

| Field | Value | Notes |
|-------|-------|-------|
| `model` | `anthropic/claude-haiku-4-5-20251001` | Must be `provider/model` format — `anthropic/` prefix required |
| `cwd` | `/workspace` | Working directory inside the opencode container |
| `dangerouslySkipPermissions` | `true` | Required for unattended/headless runs; skips interactive permission prompts |

---

## Step 6 — Verify in the Paperclip UI

Open Paperclip UI → **Agents** → **Full Stack Developer** → **Settings** and confirm:
- Adapter type: `opencode_local`
- Environment: **OpenCode SSH**
- Model: `anthropic/claude-haiku-4-5-20251001`

---

## Step 7 — Send a test task

Dispatch a small task from Paperclip to the Full Stack Developer agent (e.g. "List files in /workspace"). Then verify:

```powershell
# Watch opencode activity
docker logs opencode --tail 30 --follow
```

You should see `opencode run` invoked via SSH. The result appears in the Paperclip task thread.

---

## What survives what

| Scenario | SSH environment | Agent adapter config |
|---|---|---|
| `docker compose restart opencode` | ✓ (stored in Paperclip DB) | ✓ (stored in Paperclip DB) |
| `docker compose up -d --build opencode` | ✓ | ✓ — but SSH host key changes; `strictHostKeyChecking: false` handles this |
| `docker compose down` + `up` | ✓ | ✓ |
| New machine, repo cloned | ✓ if Paperclip DB is backed up | ✓ if Paperclip DB is backed up |
| Paperclip DB wiped | ✗ — redo Steps 3–5 | ✗ — redo Steps 3–5 |

The SSH environment and agent config live in Paperclip's database, not in this repo. On a new machine you must redo Steps 3–5 (the SSH private key at `~/.ssh/id_opencode` must also be present).

---

## Result

- Agent name: **Full Stack Developer**
- Organisation: **MINT**
- Adapter type: `opencode_local`
- SSH environment: **OpenCode SSH** (`127.0.0.1:2223`, user `root`)
- Remote workspace: `/workspace`
- Model: `anthropic/claude-haiku-4-5-20251001`

---

## Troubleshooting

**"SSH key has passphrase" / adapter hangs on connect**
Regenerate the key without a passphrase:
```powershell
ssh-keygen -t ed25519 -f C:\Users\i8329\.ssh\id_opencode -N ""
# Then copy the new public key into the container:
$pub = Get-Content C:\Users\i8329\.ssh\id_opencode.pub
docker exec opencode sh -c "echo '$pub' >> /root/.ssh/authorized_keys"
```

**"model not found" / `provider/model` format error**
The `model` field must be `provider/model` — e.g. `anthropic/claude-haiku-4-5-20251001`. A plain model ID without the provider prefix will be rejected.

**"connection refused" on port 2223**
Confirm the opencode container is running and the port is mapped:
```powershell
docker compose ps opencode
# Should show: 0.0.0.0:2223->22/tcp
```

**SSH host key changed after container rebuild**
The environment is configured with `strictHostKeyChecking: false`, so this is handled automatically. If you see host key errors anyway, clear `~/.ssh/known_hosts` entries for `[127.0.0.1]:2223`.
