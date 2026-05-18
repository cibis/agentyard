# AGENTS.md — openclaw (agentyard)

This is openclaw running inside a Docker container. Read this file at the start of every session.

---

## Tool selection for URLs — CRITICAL

The `web_fetch` tool blocks all private/internal IP addresses at the tool level — no config overrides this. For any URL pointing to a local service, use these alternatives:

| Target | Instead of `web_fetch` | Use |
|---|---|---|
| `http://host.docker.internal:*` | `web_fetch` | `curl -s <url>` (shell) or `browser open` |
| `http://localhost:*` (any port) | `web_fetch` | `curl -s <url>` (shell) or `browser open` |
| `http://opencode:*` | `web_fetch` | `curl -s <url>` (shell) |
| External URLs (`https://example.com`) | — | `web_fetch` is fine |

Use `web_fetch` only for public internet URLs. Use `curl` or the browser tool for anything local.

---

## Networking — CRITICAL

You are inside the `openclaw` container. `localhost` refers to **this container only**.

**Always translate URLs before using the browser tool or making HTTP requests:**

| What you want to reach | Wrong (don't use) | Correct |
|---|---|---|
| opencode web preview | `http://localhost:9081/...` | `http://host.docker.internal:9081/...` |
| opencode SSH | `localhost:2223` | `opencode:22` (same Docker network) |
| openclaw itself | — | `http://127.0.0.1:18789` |
| Any host-side port | `http://localhost:<port>` | `http://host.docker.internal:<port>` |

**Rule:** Any `localhost:<port>` URL that is not a port you started yourself → replace `localhost` with `host.docker.internal`.

---

## Rendering websites — AUTOMATIC

When the user asks to show, open, render, preview, or screenshot any URL — do it immediately without asking.

**IMPORTANT: Do NOT use the `browser` tool for this. Do NOT use `browser open`, `browser screenshot`, or `browser snapshot`. The only correct method is the vision bridge shell command below.**

Steps:
1. Translate `localhost` → `host.docker.internal` (see Networking table above)
2. Run this exact command (replace the URL):

```bash
bash /app/skills/agentyard/browser-render/vision-bridge.sh http://host.docker.internal:9081/start
```

3. The command prints one line: a markdown image reference. Include that line verbatim in your reply. Do not add any description, commentary, or other text about the screenshot.

Example reply after running vision-bridge:
```
![Screenshot](/exchange/outbox/openclaw/screenshots/screenshot-20260517-141822.png)
```

Full details: `/app/skills/agentyard/browser-render/SKILL.md`

---

## Skills

Skills are in `/app/skills/agentyard/`. Each `SKILL.md` describes how to use that capability. Read the relevant one before using any tool.

Key skills:
- `browser-render/SKILL.md` — render any URL as an inline screenshot (read this for all browser tasks)
- `conventions/SKILL.md` — file exchange paths, full networking URL table
- `system-tools/SKILL.md` — shell tools available (chromium, jq, python3, wget, etc.)
- `file-exchange/SKILL.md` — rules for reading/writing shared files with opencode
- `yahoo-finance/SKILL.md` — stock/market data via Yahoo Finance API

---

## File Exchange

Shared directory is mounted at `/exchange`.

| Purpose | Path |
|---|---|
| Your inbox | `/exchange/inbox/openclaw/` |
| Your outbox | `/exchange/outbox/openclaw/` |
| Your scratch | `/exchange/scratch/openclaw/` |
| opencode inbox | `/exchange/inbox/opencode/` |

Always use full absolute paths. Never relative paths.

---

## Browser Tool

- The browser runs headless inside this container.
- Always use `host.docker.internal` instead of `localhost` for any URL pointing to another service.
- Private network access is enabled — you can navigate to internal addresses.
- `noSandbox` is enabled — `--no-sandbox` is passed automatically; do not add it manually.

---

## Safety

- Sandbox is off — you can run shell commands freely; this container is isolated.
- No destructive host-side actions without confirmation.
- Don't exfiltrate secrets or private data.
