---
name: file-exchange
description: Rules for reading input files and writing output files. Defines the correct absolute paths for this agent (openclaw) inside the shared /exchange directory, including per-agent inbox, outbox, and scratch subfolders.
---

# File Exchange Conventions — openclaw

A shared directory is mounted at `/exchange` inside this container.
The host sees the same directory at `<agentyard>/shared/`.

## This agent's assigned paths

| Purpose    | Path                           |
|------------|--------------------------------|
| **Inbox**  | `/exchange/inbox/openclaw/`    |
| **Outbox** | `/exchange/outbox/openclaw/`   |
| **Scratch**| `/exchange/scratch/openclaw/`  |

These are the **default** locations. Always use them unless the task explicitly names a different path.

---

## Full Directory Map

| Path                         | Purpose |
|------------------------------|---------|
| `/exchange/inbox/openclaw/`  | **Your inbox** — tasks and input files sent to openclaw |
| `/exchange/inbox/opencode/`  | opencode's inbox — place files here when delegating to opencode |
| `/exchange/outbox/openclaw/` | **Your outbox** — write all final result files here |
| `/exchange/outbox/opencode/` | opencode's outbox — look here for files opencode has produced |
| `/exchange/scratch/openclaw/`| **Your scratch** — ephemeral temp files during a multi-step task |
| `/exchange/scratch/opencode/`| opencode's scratch — intermediate files from opencode |
| `/agent-exchange/`           | Docker volume for container-to-container transfers, not visible on host |

---

## Path Translation for User Requests

| When a user says...           | Use this absolute path                      |
|-------------------------------|---------------------------------------------|
| `"output/foo.html"`           | `/exchange/outbox/openclaw/foo.html`        |
| `"inbox/task.json"`           | `/exchange/inbox/openclaw/task.json`        |
| `"shared/output/foo.html"`    | `/exchange/outbox/openclaw/foo.html`        |
| `"the output folder"`         | `/exchange/outbox/openclaw/`                |
| `"scratch/work.tmp"`          | `/exchange/scratch/openclaw/work.tmp`       |

Always resolve to the full absolute `/exchange/...` path before calling any file tool.
Relative paths resolve inside your sandbox workspace (`/root/.openclaw/workspace/`), not `/exchange/`.

---

## Rules

### Reading input
1. Check `/exchange/inbox/openclaw/` first.
2. If not there, check `/exchange/scratch/openclaw/`.
3. If the task says the file came from opencode, check `/exchange/outbox/opencode/`.
4. Never guess — if the file isn't found, report the exact path checked.

### Writing output
- Always write final results to `/exchange/outbox/openclaw/<filename>` using the full absolute path.
- Never use relative paths (`output/`, `./output/`, `shared/output/`, etc.).
- Name files descriptively: `<subject>-<type>-<YYYY-MM-DD>.ext`
- Confirm after writing: `"Saved to /exchange/outbox/openclaw/intc-5day-chart-2026-05-16.html"`

### Using scratch
- Use `/exchange/scratch/openclaw/` for intermediate or temp files during multi-step tasks.
- Clean up scratch files after the final result has been written to outbox.
- Never deliver scratch files as the final output.

### Delegating to opencode
- Write the input file to `/exchange/inbox/opencode/<filename>`.
- Instruct opencode to write its result to `/exchange/outbox/opencode/<filename>`.
- Pick up opencode's result from `/exchange/outbox/opencode/`.

---

## Quick Reference

```bash
# Check your inbox
ls /exchange/inbox/openclaw/

# Write final output
cat > /exchange/outbox/openclaw/result.html << 'EOF'
...
EOF

# Write a temp file to scratch
cat > /exchange/scratch/openclaw/work.tmp << 'EOF'
...
EOF

# Send a task file to opencode
cp /exchange/scratch/openclaw/task.json /exchange/inbox/opencode/task.json

# Read opencode's result
cat /exchange/outbox/opencode/result.json
```

---

## opencode Web Services

opencode runs an HTTP server that serves browser-accessible content produced by its agents. The server is always on port **9081** and auto-starts on container restart.

### Service registry

`/exchange/outbox/opencode/serve-process.json` lists every active service. Read this file to discover what opencode is currently serving.

```json
{
  "server": { "cmd": "...", "port": 9081, "pid": 11, "started_at": "2026-05-16T17:13:54Z" },
  "services": [
    {
      "name": "hello-world",
      "type": "static",
      "description": "Hello World page",
      "path": "/hello-world",
      "dir": "/exchange/outbox/opencode/serve/www/hello-world",
      "url": "http://localhost:9081/hello-world"
    }
  ]
}
```

### URLs by caller

The `url` field in each service always uses `localhost`. Replace the host depending on where you are calling from:

| Caller | Base URL | Example |
|--------|----------|---------|
| openclaw (inside container) | `http://opencode:9081` | `http://opencode:9081/hello-world` |
| Paperclip (host) | `http://localhost:9081` | `http://localhost:9081/hello-world` ← use as-is |

### Quick reference

```bash
# From openclaw — list active services with in-container URLs
node -e "
  const d=require('/exchange/outbox/opencode/serve-process.json');
  d.services.forEach(s=>console.log(s.name, s.url.replace('localhost','opencode'), s.description));
"

# From openclaw — fetch a served resource
curl http://opencode:9081/<service-path>

# From openclaw — check if server is running
node -e "const d=require('/exchange/outbox/opencode/serve-process.json'); process.kill(d.server.pid,0)" 2>/dev/null \
  && echo "running" || echo "not running"
```

---

## Prompt Templates

Use these exact phrasings when Paperclip (or another caller) instructs openclaw or opencode to work with files.

---

### Paperclip → openclaw: deliver a task via inbox file

```
Read the file at /exchange/inbox/openclaw/<filename>. Complete the task described in it.
Write your result to /exchange/outbox/openclaw/<result-filename>.
When done, confirm the exact path you wrote to.
```

---

### Paperclip → openclaw: read a file openclaw already produced

```
The file you need is at /exchange/outbox/openclaw/<filename>. Read it and summarize the key findings.
```

---

### Paperclip → opencode: deliver a coding task via inbox file

```
Read the task spec at /exchange/inbox/opencode/<filename>.
Implement the solution and write the final code to /exchange/outbox/opencode/<result-filename>.
Confirm the output path when done.
```

---

### Paperclip → opencode: read a file opencode already produced

```
Your last output is at /exchange/outbox/opencode/<filename>. Review it and confirm it is correct.
```

---

### openclaw → opencode: delegate a sub-task

```
1. Write the input data or spec to /exchange/inbox/opencode/<task-filename>.
2. Send opencode this prompt:
   "Read /exchange/inbox/opencode/<task-filename>. <describe the task>.
    Write your result to /exchange/outbox/opencode/<result-filename>.
    Confirm the output path when done."
3. Pick up the result from /exchange/outbox/opencode/<result-filename>.
```

---

### openclaw: multi-step task with scratch space

```
Save intermediate work to /exchange/scratch/openclaw/<tmp-filename> while processing.
When the task is complete, copy the final result to /exchange/outbox/openclaw/<final-filename>
and delete scratch files.
```

---

### opencode: multi-step task with scratch space

```
Use /exchange/scratch/opencode/ for any temporary files during your work.
Write only the final deliverable to /exchange/outbox/opencode/<filename>.
Clean up scratch files when done.
```

---

### openclaw: list what opencode is currently serving

```
Read /exchange/outbox/opencode/serve-process.json.
For each entry in services[], report: name, description, and URL — replacing "localhost" with "opencode" in the url field.
Also report whether the server is running (check if the pid in server.pid is alive).
```

---

### openclaw: fetch content served by opencode

```
The resource you need is served by opencode at http://opencode:9081/<service-path>.
Fetch it with: curl http://opencode:9081/<service-path>
```

---

### openclaw → opencode: delegate a serve task, then use the result

```
1. Write the task spec to /exchange/inbox/opencode/<task-filename>.
2. Send opencode this prompt:
   "Read /exchange/inbox/opencode/<task-filename>. <describe what to build and serve>.
    Follow the serve conventions. Confirm the service name and URL when done."
3. When opencode confirms, read /exchange/outbox/opencode/serve-process.json to get the service entry.
4. Access the result at http://opencode:9081/<service-path> (replace localhost with opencode).
```

---

### Paperclip: list what opencode is currently serving

```
Read $PAPERCLIP_EXCHANGE_DIR/outbox/opencode/serve-process.json (or <agentyard>/shared/outbox/opencode/serve-process.json).
For each entry in services[], report: name, description, and url (use as-is — localhost:9081 is correct from the host).
```

---

### Paperclip: drop shared context for both agents

```
Write the shared context file to /exchange/scratch/openclaw/<context-filename>
(visible to openclaw) or /exchange/scratch/opencode/<context-filename> (visible to opencode).
Reference this path in the task prompt you send to each agent.
```
