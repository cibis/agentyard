---
name: conventions
description: Agent file exchange conventions. Defines inbox/outbox/scratch paths for openclaw and opencode inside /exchange, and the rules for reading, writing, delegating, and using scratch space.
---

# Agent File Exchange Conventions

Shared directory mounted at `/exchange` in all containers, `<agentyard>/shared/` on the host.

## Per-agent paths

| Agent    | Inbox                        | Outbox                        | Scratch                        |
|----------|------------------------------|-------------------------------|--------------------------------|
| openclaw | `/exchange/inbox/openclaw/`  | `/exchange/outbox/openclaw/`  | `/exchange/scratch/openclaw/`  |
| opencode | `/exchange/inbox/opencode/`  | `/exchange/outbox/opencode/`  | `/exchange/scratch/opencode/`  |

## Path purposes

| Path               | Purpose                                                    |
|--------------------|------------------------------------------------------------|
| `inbox/<agent>/`   | Tasks and input files sent TO an agent                     |
| `outbox/<agent>/`  | Final results written BY an agent                          |
| `scratch/<agent>/` | Ephemeral work-in-progress files; cleared between jobs     |
| `/agent-exchange/` | Container-to-container Docker volume (not visible on host) |

## Rules

- Each agent reads from its own `inbox/` and writes final results to its own `outbox/`.
- Use `scratch/<agent>/` for temp files during a multi-step task; clean up when done.
- When one agent delegates to another, write the input to the receiving agent's `inbox/`.
- Always use full absolute paths — never relative paths.

---

## Networking — URL resolution from inside containers

`localhost` inside a container refers to **that container only**, not the host or other containers.

| Target | From host | From openclaw container | From opencode container |
|--------|-----------|------------------------|------------------------|
| openclaw gateway | `http://localhost:18789` | `http://127.0.0.1:18789` | `http://openclaw:18789` |
| openclaw web preview | `http://localhost:9080` | `http://127.0.0.1:9080` | `http://openclaw:9080` |
| opencode web preview | `http://localhost:9081` | `http://host.docker.internal:9081` | `http://127.0.0.1:9081` |
| opencode SSH | `ssh opencode` (port 2223) | `ssh -p 22 opencode` (container name) | — |
| host machine | — | `http://host.docker.internal:<port>` | `http://host.docker.internal:<port>` |

**Key rule:** When openclaw's browser tool navigates to an opencode-served page, use `http://host.docker.internal:9081/...` — never `http://localhost:9081/...`.

### Which tool to use for HTTP requests

The `web_fetch` tool blocks all private/internal IPs — no config override exists. For local services, use shell or browser instead:

| URL | Tool to use |
|---|---|
| `http://host.docker.internal:*` | `curl -s <url>` (shell) or `browser open` |
| `http://localhost:*` / `http://opencode:*` | `curl -s <url>` (shell) |
| `https://any-public-site.com` | `web_fetch` (preferred for public internet) |
