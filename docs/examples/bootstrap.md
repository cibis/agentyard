# Bootstrap Tasks — Generic Agentyard Setup

Steps to get a new Paperclip + openclaw + opencode agent system fully operational after the initial agent and AGENTS.md files are in place.

---

## Step 1 — Prepare Inbox Files

Before the agents can run, populate the files they read for configuration and initial data:

| File | Purpose |
|------|---------|
| `/exchange/inbox/openclaw/<monitor-agent>/watchlist.md` | Items the monitoring agent tracks — one row per item with status (Active, Paused, Removed) |
| `/exchange/inbox/openclaw/<analyst-agent>/criteria.md` | Screening thresholds and filters — human-editable, no agent changes needed when this file changes |

Edit these files directly on the host in `shared/inbox/openclaw/`. Changes take effect on the next agent run.

---

## Step 2 — Set Up Paperclip Routines

See `paperclip-task-setup-routines.md` for the issue to create.

Create the issue in the Paperclip UI, assign it to the CEO agent, and let the CEO configure both routines via the routines API.

---

## Step 3 — Build the Portal

See `paperclip-task-build-portal.md` for the issue to create.

Create the issue in the Paperclip UI, assign it to the CEO agent. The CEO will delegate to the Full Stack Developer agent.

---

## Step 4 — First-Run Validation

After steps 1–3 are complete, validate the system end-to-end.

### Validate the periodic monitor

Create a Paperclip issue manually:
- **Title:** `monitor-run-{today's date}`
- **Assigned to:** Monitor agent
- **Description:** the full monitoring instructions from the agent's AGENTS.md

Expected output: `/exchange/outbox/openclaw/monitor-report-{date}.md` with all active watchlist items covered and all required fields populated.

### Validate the portal

Open `http://localhost:9081/<portal-name>` in a browser. Confirm:
- Dashboard loads and shows the latest monitor report
- Watchlist Manager shows all active items
- No JavaScript console errors on the main screens

### Validate the analyst / screener

The analyst routine fires automatically on its schedule. To trigger an early run, create a Paperclip issue manually assigned to the Analyst agent.

Expected output: `/exchange/outbox/openclaw/analyst-report-{date}.md` plus board approval requests for finalists in the Paperclip board.

---

## Ongoing Maintenance

| Task | Who | When |
|------|-----|------|
| Review and approve/reject board approval requests | Human owner | After each analyst run |
| Add approved items to `watchlist.md` | Human owner | After board approval |
| Move items to Paused or Removed in `watchlist.md` | Human owner | As needed |
| Update thresholds or filters in `criteria.md` | Human owner | As requirements evolve — takes effect on the next run, no agent changes needed |
| Update agent AGENTS.md files | Human owner (with Claude Code) | Only when agent behavior patterns need to change, not for criteria value changes |
