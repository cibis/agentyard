# opencode — Agentyard Project Conventions

These conventions apply to every session. Follow them for all file and serve tasks.

---

## File Exchange

Shared directory is mounted at `/exchange` (host: `<agentyard>/shared/`).

### Your assigned paths

| Purpose    | Path                           |
|------------|--------------------------------|
| **Inbox**  | `/exchange/inbox/opencode/`    |
| **Outbox** | `/exchange/outbox/opencode/`   |
| **Scratch**| `/exchange/scratch/opencode/`  |

Always use these paths unless a task explicitly names a different one. Never use relative paths.

### Rules
- Read input from your inbox (`/exchange/inbox/opencode/`).
- Write all final results to your outbox (`/exchange/outbox/opencode/`).
- Use scratch for temp/intermediate files; clean up when done.
- When delegating to another agent, write to their inbox (`/exchange/inbox/<agent>/`).
- Always use full absolute paths.

---

## Serving HTML / HTTP Content

When a task requires browser-accessible output, follow these conventions exactly.

### CRITICAL — read before doing anything

- **Never start a server outside `/exchange/outbox/opencode/serve/`.**
  No `python3 -m http.server`, no `npx serve`, no servers in `/workspace/`, `/root/`, or elsewhere.
  The only permitted server on port 9081 is `/exchange/outbox/opencode/serve/server.js`.

- **The container auto-starts `server.js` on every restart.**
  Always check if the server is already running before starting it:
  ```bash
  node -e "const d=require('/exchange/outbox/opencode/serve-process.json'); process.kill(d.server.pid,0)" 2>/dev/null \
    && echo "already running" || echo "not running"
  ```
  Only start it if the check says "not running".

- **Always start in background mode — never foreground.**
  Use `& disown` so the process survives after the session ends. Never run `node server.js` without `&`.
  ```bash
  node /exchange/outbox/opencode/serve/server.js &
  SERVER_PID=$!
  disown $SERVER_PID
  ```

### Directory layout

```
/exchange/outbox/opencode/
  serve/
    www/
      <service-name>/    ← static files (HTML, JS, CSS, assets)
    server.js            ← single Node.js HTTP server for all services
  serve-process.json     ← registry of the server process + all services
```

### Port
Always serve on port **9081** (`http://localhost:9081` on the host).

### Default server.js (Node.js built-ins only, no npm needed)

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

### serve-process.json schema

```json
{
  "server": { "cmd": "node /exchange/outbox/opencode/serve/server.js", "port": 9081, "pid": 0, "started_at": "" },
  "services": [
    { "name": "<name>", "type": "static", "description": "...", "path": "/<name>", "dir": "/exchange/outbox/opencode/serve/www/<name>", "url": "http://localhost:9081/<name>", "created_at": "" }
  ]
}
```

### Serve workflow (first time)

1. Write files to `/exchange/outbox/opencode/serve/www/<service-name>/`
2. Create `server.js` if it doesn't exist
3. Create `serve-process.json` with the server block and a services entry
4. Check if server is already running. If NOT: start in background — `node /exchange/outbox/opencode/serve/server.js & SERVER_PID=$! && disown $SERVER_PID` — then write PID into `serve-process.json`. If already running: skip.
5. Confirm: `"Serving at http://localhost:9081/<service-name>"`

### Adding a second service

1. Write new files to `/exchange/outbox/opencode/serve/www/<new-service-name>/`
2. Append a new entry to `services[]` in `serve-process.json`
3. If `server.js` needs custom routing: update it, restart (kill old PID, start fresh), update `server.pid` and `server.started_at`
4. If pure static: no restart needed
