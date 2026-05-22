# Paperclip Adapter Development Reference

Quick reference for building new Paperclip adapters and integrating with the Paperclip API from custom agents. All findings from reverse-engineering the existing adapter codebase.

---

## Adapter Interface Contract

Every adapter implements `ServerAdapterModule` from `@paperclipai/adapter-utils`:

```typescript
interface ServerAdapterModule {
  type: string;                          // unique, snake_case, e.g. "langgraph_local"
  execute(ctx: AdapterExecutionContext): Promise<AdapterExecutionResult>;
  testEnvironment(ctx: AdapterEnvironmentTestContext): Promise<AdapterEnvironmentTestResult>;

  // Optional
  sessionCodec?: AdapterSessionCodec;   // for session persistence across wakes
  listSkills?: (ctx) => Promise<AdapterSkillSnapshot>;
  syncSkills?: (ctx, desiredSkills) => Promise<AdapterSkillSnapshot>;
  models?: AdapterModel[];
  agentConfigurationDoc?: string;        // markdown shown in UI
  supportsLocalAgentJwt?: boolean;       // inject short-lived JWT for agent→Paperclip calls
  supportsInstructionsBundle?: boolean;  // CLAUDE.md / instructions file support
  requiresMaterializedRuntimeSkills?: boolean;
  getRuntimeCommandSpec?: (config) => AdapterRuntimeCommandSpec | null;
}
```

Source: `c:\PROJECTS\paperclip\packages\adapter-utils\src\types.ts`

---

## AdapterExecutionContext — What the Adapter Receives

```typescript
interface AdapterExecutionContext {
  runId: string;
  agent: {
    id: string;
    companyId: string;
    name: string;
    adapterType: string;
    adapterConfig: Record<string, unknown>;  // from agent UI config
  };
  runtime: {
    sessionId?: string;
    sessionParams?: Record<string, unknown>;  // persisted from previous wake's sessionParams
    sessionDisplayId?: string;
  };
  config: Record<string, unknown>;            // same as agent.adapterConfig
  context: Record<string, unknown>;           // wake payload — see below
  onLog: (stream: "stdout" | "stderr", chunk: string) => Promise<void>;
  onMeta?: (meta) => Promise<void>;
  onSpawn?: (meta: { pid, processGroupId, startedAt }) => Promise<void>;
  authToken?: string;                         // short-lived JWT if supportsLocalAgentJwt=true
}
```

### context fields (the wake payload)
```typescript
context.issueId          // UUID of the issue that triggered the wake
context.taskId           // same as issueId in most cases
context.wakeReason       // "new_issue" | "comment" | "approval" | ...
context.wakeCommentId    // UUID of comment that triggered the wake (if reason=comment)
context.approvalId       // UUID of approval (if reason=approval)
context.approvalStatus   // "approved" | "rejected" (if reason=approval)
context.issueIds         // array of related issue UUIDs
context.paperclipWake    // full structured wake payload (see below)
context.paperclipIssue   // { id, identifier, title, status, workMode, priority } — NO body/description
```

### IMPORTANT: Issue body is NOT in context
`context.paperclipIssue` (type `PaperclipWakeIssue`) has: `id, identifier, title, status, workMode, priority` — **no body/description field**.

To get the issue body, the adapter must call:
```
GET /api/issues/{issueId}
```
and read the `description` or `body` field from the response.

### paperclipWake structure
```typescript
context.paperclipWake = {
  reason: string | null,
  issue: { id, identifier, title, status, workMode, priority } | null,
  comments: Array<{
    id: string | null,
    issueId: string | null,
    body: string,            // full comment text
    bodyTruncated: boolean,
    createdAt: string | null,
    authorType: string | null,   // "agent" | "user"
    authorId: string | null,
  }>,
  commentIds: string[],
  latestCommentId: string | null,
  // ... other fields
}
```

Comments are available in full. Filter by `authorType === "user"` to get human comments only.

---

## AdapterExecutionResult — What the Adapter Returns

```typescript
interface AdapterExecutionResult {
  exitCode: number | null;
  signal: string | null;
  timedOut: boolean;
  errorMessage?: string | null;
  sessionParams?: Record<string, unknown>;  // stored by Paperclip, re-injected next wake as runtime.sessionParams
  usage?: { inputTokens: number; outputTokens: number; cachedInputTokens?: number };
  summary?: string;                          // short plaintext shown in UI
  provider?: string;
  model?: string;
  costUsd?: number;
  clearSession?: boolean;                    // force fresh session on next wake
}
```

**Session persistence pattern:** whatever you put in `sessionParams` is stored by Paperclip and returned as `runtime.sessionParams` on the next wake. Use this for graph state, stage machines, file paths, etc.

---

## sessionCodec — Persistent Session State

```typescript
interface AdapterSessionCodec {
  deserialize(raw: unknown): Record<string, unknown> | null;
  serialize(params: Record<string, unknown> | null): unknown;
  getDisplayId(params: Record<string, unknown> | null): string | null;  // shown in UI
}
```

Minimal implementation:
```typescript
export const sessionCodec: AdapterSessionCodec = {
  deserialize(raw) { return typeof raw === "object" && raw !== null ? raw as Record<string, unknown> : null; },
  serialize(params) { return params; },
  getDisplayId(params) { return (params?.stage as string) ?? null; },
};
```

---

## AdapterSessionManagement

Session management controls when Paperclip creates a new session vs continues an existing one. Not required for simple adapters — omit and Paperclip uses defaults.

---

## Useful Server-Utils Helpers

From `@paperclipai/adapter-utils/server-utils`:

```typescript
asString(v: unknown): string | null      // safe config value extraction
asNumber(v: unknown): number | null
asBoolean(v: unknown): boolean | null
buildPaperclipEnv(agent): Record<string, string>  // injects PAPERCLIP_* env vars
renderTemplate(template: string, data: Record<string, string>): string  // {{var}} substitution
runChildProcess(command, args, opts): Promise<{exitCode, stdout, stderr}>  // spawn with timeout
```

---

## Package Structure for a New Adapter

```
packages/adapters/<name>/
  package.json         # "type":"module", exports: {"."} and {"./server"}
  tsconfig.json        # extends ../../../tsconfig.base.json
  src/
    index.ts           # export type, label, agentConfigurationDoc, createServerAdapter
    server/
      index.ts         # export sessionCodec, execute, testEnvironment
      execute.ts       # implement AdapterExecutionContext → AdapterExecutionResult
      test.ts          # implement AdapterEnvironmentTestContext → AdapterEnvironmentTestResult
```

### Minimal package.json
```json
{
  "name": "@paperclipai/adapter-<name>",
  "version": "0.1.0",
  "type": "module",
  "exports": {
    ".": "./src/index.ts",
    "./server": "./src/server/index.ts"
  },
  "dependencies": { "@paperclipai/adapter-utils": "workspace:*" },
  "devDependencies": { "@types/node": "^24.0.0", "typescript": "^5.7.3" }
}
```

### Minimal tsconfig.json
```json
{
  "extends": "../../../tsconfig.base.json",
  "compilerOptions": { "outDir": "dist", "rootDir": "src" },
  "include": ["src"]
}
```

---

## Registering a Built-in Adapter

File: `c:\PROJECTS\paperclip\server\src\adapters\registry.ts`

1. Add import at top:
```typescript
import { execute as myExecute, testEnvironment as myTest, sessionCodec as myCodec }
  from "@paperclipai/adapter-my-name/server";
import { agentConfigurationDoc as myDoc } from "@paperclipai/adapter-my-name";
```

2. Add adapter object (near other adapter objects, around line 395):
```typescript
const myAdapter: ServerAdapterModule = {
  type: "my_type",
  execute: myExecute,
  testEnvironment: myTest,
  sessionCodec: myCodec,
  supportsLocalAgentJwt: false,
  supportsInstructionsBundle: false,
  requiresMaterializedRuntimeSkills: false,
  agentConfigurationDoc: myDoc,
};
```

3. Add to `registerBuiltInAdapters()` array (around line 515):
```typescript
function registerBuiltInAdapters() {
  for (const adapter of [
    // ... existing adapters ...
    myAdapter,   // ← add here
  ]) {
    adaptersByType.set(adapter.type, adapter);
  }
}
```

---

## Paperclip REST API Quick Reference

**Base URL:** `http://localhost:3100` (from host). From inside containers: `http://host.docker.internal:3100`

**Auth:** `local_trusted` — no `Authorization` header needed from host. Containers use `Authorization: Bearer $PAPERCLIP_API_KEY`.

**Content-Type:** always `application/json` for POST/PATCH.

### Companies
```
GET  /api/companies                              → array of companies
     response: [{ id, issuePrefix, name }]

GET  /api/companies/{companyId}/agents           → array of agents
     response: [{ id, nameKey, adapterType, status }]
```

### Issues
```
GET  /api/issues/{issueId}                       → full issue (includes body/description)
     response: { id, identifier, title, description, status, assigneeAgentId, parentId }

GET  /api/companies/{companyId}/issues           → list issues
     query params: limit, status, q (search)
     status values: backlog | todo | in_progress | in_review | blocked | done | cancelled

POST /api/companies/{companyId}/issues           → create issue
     body: { title, description, assigneeAgentId, status, parentId? }
     response: { id, identifier }

PATCH /api/issues/{issueId}                      → update issue
     body: { status?, title?, description?, assigneeAgentId?, parentId?, priority? }
```

### Comments
```
GET  /api/issues/{issueId}/comments              → array of comments
     response: [{ id, body, authorType, authorId, createdAt }]

POST /api/issues/{issueId}/comments              → post comment
     body: { body: string, reopen?: boolean }
     reopen: true moves blocked issue back to todo and re-wakes agent
```

### Approvals
```
GET  /api/companies/{companyId}/approvals        → list approvals
     response: [{ id, type, status, title, description }]

GET  /api/approvals/{approvalId}                 → single approval
     response: { id, type, status, title, description }

POST /api/companies/{companyId}/approvals        → create approval
     body: { type: "request_board_approval", title: string, description: string }
     response: { id }

GET  /api/approvals/{approvalId}/issues          → issues linked to approval
```

### Environments & Secrets
```
GET  /api/companies/{companyId}/environments     → list environments
GET  /api/companies/{companyId}/secrets          → list secrets
POST /api/secrets/{secretId}/rotate              → update secret value
     body: { value: string }
```

### Routines
```
GET  /api/companies/{companyId}/routines         → list routines
```

### Agents
```
POST /api/agents/{agentId}/pause
POST /api/agents/{agentId}/resume
```

---

## Discovering Agent IDs at Runtime

Agent IDs are UUIDs that change per installation. Always discover at runtime:

```typescript
const agents = await fetch(`${base}/api/companies/${companyId}/agents`).then(r => r.json());
const fsdAgent = agents.find((a: { nameKey: string }) => a.nameKey === "full-stack-developer");
const fsdAgentId = fsdAgent?.id;
```

**MINT agent nameKeys:**
| nameKey | Adapter |
|---|---|
| `ceo` | `claude_local` |
| `stock-watcher` | `openclaw_gateway` |
| `financial-research-analyst` | `openclaw_gateway` |
| `full-stack-developer` | `opencode_local` |

---

## File Exchange Paths

| Purpose | Host path | Container path |
|---|---|---|
| openclaw inbox | `./shared/inbox/openclaw/` | `/exchange/inbox/openclaw/` |
| opencode inbox | `./shared/inbox/opencode/` | `/exchange/inbox/opencode/` |
| openclaw outbox | `./shared/outbox/openclaw/` | `/exchange/outbox/openclaw/` |
| opencode outbox | `./shared/outbox/opencode/` | `/exchange/outbox/opencode/` |
| opencode web server | `./shared/outbox/opencode/serve/` | `/exchange/outbox/opencode/serve/` |
| openclaw scratch | `./shared/scratch/openclaw/` | `/exchange/scratch/openclaw/` |
| opencode scratch | `./shared/scratch/opencode/` | `/exchange/scratch/opencode/` |

`PAPERCLIP_EXCHANGE_DIR` env var (set in `../paperclip/.env`) = absolute path to `./shared/`.

---

## Networking — URL Resolution

| Target | From host | From openclaw container | From opencode container |
|---|---|---|---|
| Paperclip API | `http://localhost:3100` | `http://host.docker.internal:3100` | `http://host.docker.internal:3100` |
| openclaw gateway | `http://localhost:18789` | `http://127.0.0.1:18789` | `http://openclaw:18789` |
| opencode web | `http://localhost:9081` | `http://host.docker.internal:9081` | `http://127.0.0.1:9081` |

---

## Environment Variables Available to Adapters

Set by Paperclip / inherited from host process:

| Variable | Source | Value |
|---|---|---|
| `PAPERCLIP_API_URL` | paperclip .env | `http://localhost:3100` |
| `PAPERCLIP_EXCHANGE_DIR` | paperclip .env | absolute path to `agentyard/shared/` |
| `PAPERCLIP_INBOX_DIR` | paperclip .env | absolute path to `agentyard/shared/inbox/` |
| `PAPERCLIP_OUTBOX_DIR` | paperclip .env | absolute path to `agentyard/shared/outbox/` |
| `ANTHROPIC_API_KEY` | agentyard .env | Anthropic key |
| `AWS_ACCESS_KEY_ID` | agentyard .env | AWS key |
| `PAPERCLIP_API_KEY` | injected by harness | short-lived JWT for agent→Paperclip (if supportsLocalAgentJwt=true) |

`buildPaperclipEnv(agent)` from adapter-utils adds `PAPERCLIP_AGENT_ID`, `PAPERCLIP_COMPANY_ID`, `PAPERCLIP_RUN_ID`, and other agent-scoped vars.

---

## Existing Adapters as Reference Implementations

| Adapter | Type | File | Notes |
|---|---|---|---|
| openclaw-gateway | `openclaw_gateway` | `packages/adapters/openclaw-gateway/src/server/execute.ts` (~1500 lines) | WebSocket gateway, ED25519 auth, streaming events |
| opencode-local | `opencode_local` | `packages/adapters/opencode-local/src/server/execute.ts` (~694 lines) | SSH + JSONL parsing, session management |
| claude-local | `claude_local` | `packages/adapters/claude-local/src/server/execute.ts` (~975 lines) | Local CLI spawn, prompt caching |

For a **minimal process-spawning adapter**, `opencode-local` is the closest model.

---

## testEnvironment Return Type

```typescript
interface AdapterEnvironmentTestResult {
  ok: boolean;
  checks: Array<{
    code: string;          // machine identifier, e.g. "graph_file_found"
    level: "info" | "warning" | "error";
    message: string;
    hint?: string;         // shown to user when level=error
  }>;
}
```
