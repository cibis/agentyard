# Database Maintenance

## Connecting to the Local Database

The local database runs as an **embedded PostgreSQL 18.1** instance started by the Paperclip server process. It is **not** a Docker container — it only runs while the server is active.

| Setting | Value |
|---|---|
| Host | `localhost` |
| Port | `54329` (embedded) — **not** 5432 |
| User | `paperclip` |
| Password | `paperclip` |
| Database | `paperclip` |
| Connection URL | `postgres://paperclip:paperclip@localhost:54329/paperclip` |

> The port `5432` in `.env` / `.env.example` is the Docker compose port. The embedded instance always uses `54329`.

### Verifying connectivity

```powershell
# From the repo root — uses the project's own postgres client
pnpm tsx --eval "(async () => {
  const { default: postgres } = await import('postgres');
  const sql = postgres('postgres://paperclip:paperclip@localhost:54329/paperclip', { max: 1 });
  const [r] = await sql\`SELECT current_user, current_database(), version()\`;
  console.log(r);
  await sql.end();
})()"
```

Or use the built-in migration status script (also checks connectivity):

```powershell
pnpm tsx packages/db/src/migration-status.ts --json
```

---

## Data Cleanup Queries

All queries below should be run from `packages/db/` so the `postgres` package resolves correctly, or from the repo root using `pnpm tsx`.

### Clear all Routines

Deleting from `routines` cascades automatically to `routine_revisions`, `routine_triggers`, and `routine_runs`.

```sql
DELETE FROM routines;
```

### Clear all Issues

Several tables reference `issues` without `ON DELETE CASCADE` and must be handled manually first.

```sql
-- Null out nullable FKs (no cascade, nullable columns)
UPDATE issues SET parent_id = NULL WHERE parent_id IS NOT NULL;
UPDATE cost_events SET issue_id = NULL WHERE issue_id IS NOT NULL;
UPDATE finance_events SET issue_id = NULL WHERE issue_id IS NOT NULL;

-- Delete from RESTRICT tables (not-null FKs, no cascade)
DELETE FROM feedback_votes;
DELETE FROM issue_comments;
DELETE FROM issue_inbox_archives;
DELETE FROM issue_read_states;
DELETE FROM issue_thread_interactions;

-- Delete all issues (cascades handle the rest)
DELETE FROM issues;
```

Tables that auto-cascade from `issues`: `issue_approvals`, `issue_attachments`, `issue_documents`,
`issue_execution_decisions`, `issue_labels`, `issue_recovery_actions`, `issue_reference_mentions`,
`issue_relations`, `issue_tree_holds`, `issue_tree_hold_members`, `issue_work_products`, `feedback_exports`.

### Clear all Runs (heartbeat_runs)

```sql
-- Null out nullable FKs without cascade
UPDATE activity_log SET run_id = NULL WHERE run_id IS NOT NULL;
UPDATE agent_task_sessions SET last_run_id = NULL WHERE last_run_id IS NOT NULL;
UPDATE cost_events SET heartbeat_run_id = NULL WHERE heartbeat_run_id IS NOT NULL;
UPDATE finance_events SET heartbeat_run_id = NULL WHERE heartbeat_run_id IS NOT NULL;

-- Delete from RESTRICT NOT NULL table
DELETE FROM heartbeat_run_events;

-- Delete all runs (cascades heartbeat_run_watchdog_decisions; set-null handles the rest)
DELETE FROM heartbeat_runs;
```

### Clear inbox

```sql
DELETE FROM inbox_dismissals;
DELETE FROM issue_inbox_archives;
```

### Clear everything (routines + issues + runs + inbox) in one transaction

```powershell
pnpm tsx --eval "(async () => {
  const { default: postgres } = await import('postgres');
  const sql = postgres('postgres://paperclip:paperclip@localhost:54329/paperclip', { max: 1 });
  await sql.begin(async sql => {
    // Routines
    await sql\`DELETE FROM routines\`;
    // Issues — clear blockers first
    await sql\`UPDATE issues SET parent_id = NULL WHERE parent_id IS NOT NULL\`;
    await sql\`UPDATE cost_events SET issue_id = NULL WHERE issue_id IS NOT NULL\`;
    await sql\`UPDATE finance_events SET issue_id = NULL WHERE issue_id IS NOT NULL\`;
    await sql\`DELETE FROM feedback_votes\`;
    await sql\`DELETE FROM issue_comments\`;
    await sql\`DELETE FROM issue_inbox_archives\`;
    await sql\`DELETE FROM issue_read_states\`;
    await sql\`DELETE FROM issue_thread_interactions\`;
    await sql\`DELETE FROM issues\`;
    // Runs — clear blockers first
    await sql\`UPDATE activity_log SET run_id = NULL WHERE run_id IS NOT NULL\`;
    await sql\`UPDATE agent_task_sessions SET last_run_id = NULL WHERE last_run_id IS NOT NULL\`;
    await sql\`UPDATE cost_events SET heartbeat_run_id = NULL WHERE heartbeat_run_id IS NOT NULL\`;
    await sql\`UPDATE finance_events SET heartbeat_run_id = NULL WHERE heartbeat_run_id IS NOT NULL\`;
    await sql\`DELETE FROM heartbeat_run_events\`;
    await sql\`DELETE FROM heartbeat_runs\`;
    // Inbox
    await sql\`DELETE FROM inbox_dismissals\`;
  });
  console.log('Done');
  await sql.end();
})()"
```

---

## FK Relationship Reference

### Tables with no cascade that block deletion

| Parent table | Blocking child table | Column | Nullable? | Fix |
|---|---|---|---|---|
| `issues` | `issues` (self) | `parent_id` | yes | SET NULL first |
| `issues` | `cost_events` | `issue_id` | yes | SET NULL first |
| `issues` | `finance_events` | `issue_id` | yes | SET NULL first |
| `issues` | `feedback_votes` | `issue_id` | no | DELETE first |
| `issues` | `issue_comments` | `issue_id` | no | DELETE first |
| `issues` | `issue_inbox_archives` | `issue_id` | no | DELETE first |
| `issues` | `issue_read_states` | `issue_id` | no | DELETE first |
| `issues` | `issue_thread_interactions` | `issue_id` | no | DELETE first |
| `heartbeat_runs` | `activity_log` | `run_id` | yes | SET NULL first |
| `heartbeat_runs` | `agent_task_sessions` | `last_run_id` | yes | SET NULL first |
| `heartbeat_runs` | `cost_events` | `heartbeat_run_id` | yes | SET NULL first |
| `heartbeat_runs` | `finance_events` | `heartbeat_run_id` | yes | SET NULL first |
| `heartbeat_runs` | `heartbeat_run_events` | `run_id` | no | DELETE first |
