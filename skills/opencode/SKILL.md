---
name: opencode-serve
description: Conventions for how opencode publishes browser-accessible content or HTTP APIs. Defines paths, serve-process.json schema, server.js template, and prompt templates for every use-case. Mount point inside opencode: /workspace/serve-conventions.md.
---

# opencode Serve Conventions

When a task requires output that must be accessible via browser or HTTP, opencode follows these conventions so that:
- All content is served on the pre-mapped port **9081** (`http://localhost:9081` on the host)
- A single registry file lists every published service
- The server restarts automatically when the container restarts

## CRITICAL RULES — read before doing anything

1. **Never start a server outside `/exchange/outbox/opencode/serve/`.**
   No `python3 -m http.server`, no `npx serve`, no servers in `/workspace/`, `/root/`, or anywhere else.
   The only server that may run on port 9081 is `/exchange/outbox/opencode/serve/server.js`.

2. **The container auto-starts `server.js` on every restart.**
   If `/exchange/outbox/opencode/serve/server.js` exists, the container startup script launches it automatically.
   Always check whether the server is already running before attempting to start it.

3. **Always start the server in background mode — never in the foreground.**
   Use `node ... & disown` so the process is detached from the shell session and keeps running after the session ends.
   Never run `node server.js` without `&` — it will block the session.

4. **Check before starting:**
   ```bash
   node -e "const d=require('/exchange/outbox/opencode/serve-process.json'); process.kill(d.server.pid,0)" 2>/dev/null \
     && echo "already running — do not start again" || echo "not running — safe to start"
   ```

---

## Directory Layout

```
/exchange/outbox/opencode/
  serve/
    www/
      <service-name>/    ← static files (HTML, JS, CSS, assets)
    server.js            ← single Node.js HTTP server for all services
  serve-process.json     ← registry of the server process + all services
```

All paths under `/exchange/outbox/opencode/` are also visible on the host at `<agentyard>/shared/outbox/opencode/`.

---

## serve-process.json Schema

One `server` block + a `services` array. Every published report or API gets its own entry.

```json
{
  "server": {
    "cmd": "node /exchange/outbox/opencode/serve/server.js",
    "port": 9081,
    "pid": 42,
    "started_at": "2026-05-16T15:00:00Z"
  },
  "services": [
    {
      "name": "intel-stock-dashboard",
      "type": "static",
      "description": "Intel 5-day stock price chart",
      "path": "/intel-stock",
      "dir": "/exchange/outbox/opencode/serve/www/intel-stock",
      "url": "http://localhost:9081/intel-stock",
      "created_at": "2026-05-16T15:00:00Z"
    },
    {
      "name": "portfolio-api",
      "type": "api",
      "description": "Portfolio management REST API",
      "path": "/portfolio-api",
      "dir": "/exchange/outbox/opencode/serve/www/portfolio-api",
      "url": "http://localhost:9081/portfolio-api",
      "created_at": "2026-05-16T15:05:00Z"
    }
  ]
}
```

**Rules for serve-process.json:**
- When adding a service: append to `services[]`, write the file.
- When replacing a service: update its entry in-place, write the file.
- When removing a service: delete its entry from `services[]`, write the file.
- Always keep `server.pid` and `server.started_at` current.

---

## Default Static server.js

Use this when all services are pure static files (HTML/JS/CSS). No npm install needed — uses Node.js built-ins only.

```js
const http = require('http');
const fs = require('fs');
const path = require('path');
const WWW = '/exchange/outbox/opencode/serve/www';

http.createServer((req, res) => {
  const filePath = path.join(WWW, req.url === '/' ? '/index.html' : req.url);
  fs.readFile(filePath, (err, data) => {
    if (err) { res.writeHead(404); res.end('Not found'); return; }
    const ext = path.extname(filePath);
    const types = { '.html':'text/html', '.js':'application/javascript', '.css':'text/css',
                    '.json':'application/json', '.png':'image/png', '.svg':'image/svg+xml' };
    res.writeHead(200, { 'Content-Type': types[ext] || 'application/octet-stream' });
    res.end(data);
  });
}).listen(9081, () => console.log('[serve] listening on :9081'));
```

When a service needs custom API routing, extend this file with the required routes and restart the server.

---

## Rules

### Checking if the server is already running
Always check first. The container auto-starts the server on restart, so it is often already running.
```bash
node -e "const d=require('/exchange/outbox/opencode/serve-process.json'); process.kill(d.server.pid,0)" 2>/dev/null \
  && echo "running" || echo "not running"
```

### Starting the server (only if NOT already running)
```bash
node /exchange/outbox/opencode/serve/server.js &
SERVER_PID=$!
disown $SERVER_PID
# Update pid in serve-process.json after starting
```

### Restarting the server (only after server.js changes)
```bash
# Kill the current process, then start fresh
kill $(node -e "console.log(require('/exchange/outbox/opencode/serve-process.json').server.pid)") 2>/dev/null || true
node /exchange/outbox/opencode/serve/server.js &
SERVER_PID=$!
disown $SERVER_PID
# Update pid + started_at in serve-process.json
```

---

## Prompt Templates

### First-time: create and serve new content

```
Before writing any files, read /workspace/serve-conventions.md.

1. Write all static/API files to /exchange/outbox/opencode/serve/www/<service-name>/.
2. If /exchange/outbox/opencode/serve/server.js does not exist, create the default static server from the conventions file.
3. Create /exchange/outbox/opencode/serve-process.json with the server block and a services entry for this service.
4. Check if the server is already running (the container may have auto-started it).
   If NOT running: `node /exchange/outbox/opencode/serve/server.js & SERVER_PID=$! && disown $SERVER_PID`
   Write the PID into serve-process.json server.pid.
   If ALREADY running and server.js didn't change: no action needed.
5. Confirm: "Serving at http://localhost:9081/<service-name>"
```

---

### Add a second service alongside an existing one

```
Read /workspace/serve-conventions.md.

A server may already be running. Check /exchange/outbox/opencode/serve-process.json.
1. Write new files to /exchange/outbox/opencode/serve/www/<new-service-name>/.
2. Append the new service entry to services[] in serve-process.json.
3. If server.js needs changes for custom routing: update it, restart the server,
   update server.pid and server.started_at in serve-process.json.
4. If server.js does not need changes (pure static): no restart needed.
5. Confirm: "Added service at http://localhost:9081/<new-service-name>. Total services: <N>"
```

---

### Paperclip or openclaw: list what is currently being served

```
Read /exchange/outbox/opencode/serve-process.json and list all entries in services[]
with their name, description, url, and type.
```

---

### openclaw delegating a serve task to opencode

```
1. Write the task spec to /exchange/inbox/opencode/<task-filename>.
2. Send opencode this prompt:
   "Read /workspace/serve-conventions.md and /exchange/inbox/opencode/<task-filename>.
    <describe what to build and serve>.
    Follow the serve conventions exactly. Confirm the URL and service name when done."
3. When opencode confirms, read /exchange/outbox/opencode/serve-process.json to get the service details.
```

---

### Check and report all active services (from host or openclaw)

```
Read /exchange/outbox/opencode/serve-process.json.
List each service in services[] with: name, type, description, url, created_at.
Report the server status (pid, port, started_at).
```
