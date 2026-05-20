# Paperclip Task: Set Up Agent Routines

Create this issue in the Paperclip UI and assign it to the **CEO** agent.

---

**Title**

```
Setup: configure periodic agent routines
```

---

**Description**

```
Set up two Paperclip routines using the routines API. Read skills/paperclip/references/routines.md before starting.

ROUTINE 1 — Periodic Monitor
Trigger: [schedule — e.g. every weekday morning, Monday–Friday].
On each trigger, check whether a monitor issue already exists for today. If not, create a Paperclip issue with:
  - Title: monitor-run-{YYYY-MM-DD}
  - Assigned to: [Monitor agent]
  - Description: the full monitoring instructions as defined in your CEO instructions

ROUTINE 2 — Periodic Analyst
Trigger: [schedule — e.g. every Sunday evening].
On each trigger, check whether an analyst issue already exists for this period. If not, create a Paperclip issue with:
  - Title: analyst-run-{YYYY-MM-DD}
  - Assigned to: [Analyst agent]
  - Description: the full analyst instructions as defined in your CEO instructions

When both routines are registered, post a comment with both routine IDs, then close this issue.
```

---

## Customisation Notes

Replace the bracketed values before creating the issue:
- `[schedule]` — the cron expression or natural-language schedule for each routine
- `[Monitor agent]` / `[Analyst agent]` — the Paperclip agent nameKey for each role
- Title prefixes (`monitor-run-`, `analyst-run-`) — match the naming convention used in the receiving agents' AGENTS.md files
