# Paperclip Task: Build the Domain Portal

Create this issue in the Paperclip UI and assign it to the **CEO** agent.

---

**Title**

```
Setup: build the [Domain] Portal
```

---

**Description**

```
Delegate to the Full Stack Developer agent. Build the [Domain] Portal as specified below.

The portal covers the domain workflow UI only — it does not replicate Paperclip dashboard functionality. No agent config, no budget views, no activity feed.

SERVE CONVENTIONS — MANDATORY
The only server allowed is /exchange/outbox/opencode/serve/server.js on port 9081. Never start a server outside that path. Before starting, check whether the server is already running by reading serve-process.json. Always start in background mode: node /exchange/outbox/opencode/serve/server.js & followed by disown. Static files go in /exchange/outbox/opencode/serve/www/[portal-name]/. Register the service as [portal-name] in serve-process.json. Host access is http://localhost:9081/[portal-name]. Use http://opencode:9081/[portal-name] when verifying from openclaw.

BUILD FOUR SCREENS

1. Report Dashboard (index.html)
Reads the latest /exchange/outbox/openclaw/monitor-report-*.md file. Shows a summary of alert categories and counts. Displays collapsible sections per category with item details. Includes a historical report selector for the last 30 files.

2. Watchlist Manager (watchlist.html)
Reads /exchange/inbox/openclaw/[monitor-agent]/watchlist.md. Displays a read-only table of all items with status badges (Active, Paused, Removed).

3. Approval Queue (approvals.html)
Reads pending Paperclip board approvals. Displays each candidate card with thesis and recommendation summary, and a link to the full analyst report. Read-only — approvals are actioned in the Paperclip board.

4. Analyst Reports (reports.html)
Lists all /exchange/outbox/openclaw/analyst-report-*.md files newest first. Renders each as styled HTML.

API ROUTES
Add these routes to server.js — all data served through these, no direct filesystem access from browser JavaScript:
  /[portal-name]/api/reports/latest
  /[portal-name]/api/reports/history
  /[portal-name]/api/reports/:date
  /[portal-name]/api/watchlist
  /[portal-name]/api/analyst
  /[portal-name]/api/analyst/:date

TECH CONSTRAINTS
No npm, no build step, no external CDN. Node.js built-ins only for server.js. Vanilla JavaScript for frontend. Dark theme, mobile-responsive.

BUILD ORDER
Report Dashboard and server.js API routes first, then Approval Queue, then Watchlist Manager, then Analyst Reports.

Write a README.md in /exchange/outbox/opencode/serve/www/[portal-name]/ documenting how to access the portal, all data source paths, and known limitations.

When complete, verify the portal is accessible at http://opencode:9081/[portal-name], post a comment with the URL and a summary of what was built, then close this issue.
```

---

## Customisation Notes

Replace the bracketed values before creating the issue:
- `[Domain]` — the name of the domain this portal serves (used in the title and heading)
- `[portal-name]` — the URL slug for the portal (e.g. `my-portal`) — must match what's registered in `serve-process.json`
- `[monitor-agent]` — the openclaw agent nameKey that writes the monitor reports
- Add or remove screens depending on the domain — the four above are a minimum viable set
- Extend the API routes list to match any additional screens you add
