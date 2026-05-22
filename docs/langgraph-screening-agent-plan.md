# Implementation Plan: `langgraph-local` Adapter + Screening Signal Agent

## What This Builds

Two things:

1. **`langgraph-local` Paperclip adapter** — a thin adapter in the paperclip project that spawns any LangGraph.js graph as a Node.js child process, injects Paperclip wake context via env vars, and round-trips session state through `sessionParams` for cross-wake persistence.

2. **`screening-signal` agent** — an on-demand stock screener registered in Paperclip. A human creates an issue with criteria in plain English. The graph resolves criteria (from issue body, prior run, or `screening_criteria.md`), delegates the actual stock screening to the Full Stack Developer (opencode) via a sub-issue, presents candidates as Paperclip approval items, and appends approved picks to `approved_stocks.md`.

No scheduled trigger. Runs only when a human creates a Paperclip issue.

---

## Architecture Overview

```
Human creates Paperclip issue
    │
    ▼
screening-signal agent wakes (langgraph-local adapter)
    │
    ├─ Adapter reads adapterConfig.graphFile
    ├─ Fetches issue body from Paperclip API
    ├─ Injects LANGGRAPH_CONTEXT + LANGGRAPH_SESSION env vars
    ├─ Spawns: npx tsx <graphFile>
    │
    ▼
LangGraph graph runs (stage machine)
    │
    ├─ ResolveCriteria ──► if prior criteria differ ──► AskCriteriaChoice (interrupt → exit)
    │                  └──► else ──► NormalizeCriteria (Claude Haiku)
    │
    ├─ DelegateToOpencode ──► writes task to /exchange/inbox/opencode/
    │                      ──► creates sub-issue assigned to full-stack-developer
    │                      ──► exits: awaiting_opencode
    │
    ├─ [re-wake] CheckOpencodeResults ──► if results file exists ──► ParseAndPresent
    │                                 └──► else re-exit same stage
    │
    ├─ ParseAndPresent ──► creates one Paperclip approval per candidate
    │                   ──► exits: awaiting_approvals
    │
    ├─ [re-wake] CheckApprovals ──► if all resolved ──► FinalizeSelection
    │                           └──► else re-exit same stage
    │
    └─ FinalizeSelection ──► appends approved tickers to approved_stocks.md
                         ──► persists lastUsedCriteria in sessionParams
                         ──► closes parent issue
    │
    ▼
Graph writes last stdout line: { sessionParams, usage, summary }
Adapter stores sessionParams → Paperclip keeps for next wake
```

---

## Part 1: `langgraph-local` Adapter

### Location
`c:\PROJECTS\paperclip\packages\adapters\langgraph-local\`

### Adapter Config (set in Paperclip agent UI)
```json
{
  "graphFile": "C:/PROJECTS/agentyard/agents/screening-signal/src/graph.ts",
  "runner": "tsx",
  "timeoutSec": 300
}
```

### Files to Create

```
packages/adapters/langgraph-local/
  package.json
  tsconfig.json
  src/
    index.ts
    server/
      index.ts
      execute.ts
      test.ts
```

### package.json
```json
{
  "name": "@paperclipai/adapter-langgraph-local",
  "version": "0.1.0",
  "type": "module",
  "exports": {
    ".": "./src/index.ts",
    "./server": "./src/server/index.ts"
  },
  "dependencies": {
    "@paperclipai/adapter-utils": "workspace:*"
  },
  "devDependencies": {
    "@types/node": "^24.0.0",
    "typescript": "^5.7.3"
  }
}
```

### tsconfig.json
```json
{
  "extends": "../../../tsconfig.base.json",
  "compilerOptions": {
    "outDir": "dist",
    "rootDir": "src"
  },
  "include": ["src"]
}
```

### src/index.ts
```typescript
export const type = "langgraph_local";
export const label = "LangGraph (local)";

export const agentConfigurationDoc = `
## LangGraph Local Adapter

Runs a LangGraph.js graph as a local Node.js process.

**Required config:**
- \`graphFile\` — absolute path to the graph entry point (.ts or .js)

**Optional config:**
- \`runner\` — \`"tsx"\` (default, runs TypeScript directly) or \`"node"\` (compiled JS)
- \`timeoutSec\` — max seconds per wake (default: 300)

**Graph contract:**
- Read \`LANGGRAPH_CONTEXT\` env var (JSON) for wake context
- Read \`LANGGRAPH_SESSION\` env var (JSON, may be empty) to restore prior state
- Write log lines to stderr
- Write exactly one JSON object as the last stdout line: \`{ sessionParams, usage, summary }\`
- Exit 0 for clean interrupt or completion; non-zero for error
`.trim();

export function createServerAdapter() {
  return import("./server/index.js");
}
```

### src/server/execute.ts (core logic)
```typescript
import { spawn } from "node:child_process";
import path from "node:path";
import type { AdapterExecutionContext, AdapterExecutionResult } from "@paperclipai/adapter-utils";
import { asString, asNumber, buildPaperclipEnv } from "@paperclipai/adapter-utils/server-utils";

export async function execute(ctx: AdapterExecutionContext): Promise<AdapterExecutionResult> {
  const { agent, config, context, runtime, onLog } = ctx;

  const graphFile = asString(config.graphFile);
  if (!graphFile) {
    return { exitCode: 1, timedOut: false, signal: null, errorMessage: "adapterConfig.graphFile is required" };
  }

  const runner = asString(config.runner) ?? "tsx";
  const timeoutSec = asNumber(config.timeoutSec) ?? 300;

  // Fetch full issue details (PaperclipWakeIssue has no body field)
  const issueId = asString(context.issueId) ?? asString(context.taskId) ?? "";
  const paperclipApiBase = process.env.PAPERCLIP_API_URL ?? "http://localhost:3100";
  let issueBody = "";
  let issueTitle = "";
  if (issueId) {
    try {
      const res = await fetch(`${paperclipApiBase}/api/issues/${issueId}`);
      if (res.ok) {
        const issue = await res.json() as Record<string, unknown>;
        issueBody = (issue.description as string) ?? (issue.body as string) ?? "";
        issueTitle = (issue.title as string) ?? "";
      }
    } catch { /* non-fatal — graph can fall back */ }
  }

  // Build context for graph
  const wakePayload = (context.paperclipWake ?? {}) as Record<string, unknown>;
  const comments = (wakePayload.comments ?? []) as Array<{ body: string; authorType: string; createdAt: string }>;

  const graphContext = {
    issueId,
    issueTitle,
    issueBody,
    companyId: agent.companyId,
    agentId: agent.id,
    runId: ctx.runId,
    wakeReason: asString(context.wakeReason) ?? "",
    comments,
    paperclipApiBase,
    exchangeDir: process.env.PAPERCLIP_EXCHANGE_DIR ?? "",
    anthropicApiKey: process.env.ANTHROPIC_API_KEY ?? "",
  };

  const env: Record<string, string> = {
    ...process.env as Record<string, string>,
    ...buildPaperclipEnv(agent) as Record<string, string>,
    LANGGRAPH_CONTEXT: JSON.stringify(graphContext),
    LANGGRAPH_SESSION: runtime.sessionParams ? JSON.stringify(runtime.sessionParams) : "",
  };

  const [command, ...args] = runner === "tsx"
    ? ["npx", "tsx", graphFile]
    : ["node", graphFile];

  let stdout = "";
  const result = await new Promise<{ exitCode: number | null; signal: string | null; timedOut: boolean }>(
    (resolve) => {
      const proc = spawn(command, args, { env, cwd: path.dirname(graphFile) });
      const timer = setTimeout(() => { proc.kill("SIGTERM"); resolve({ exitCode: null, signal: "SIGTERM", timedOut: true }); }, timeoutSec * 1000);

      proc.stdout.on("data", (chunk: Buffer) => { stdout += chunk.toString(); });
      proc.stderr.on("data", (chunk: Buffer) => { void onLog("stderr", chunk.toString()); });
      proc.on("close", (code, signal) => { clearTimeout(timer); resolve({ exitCode: code, signal: signal as string | null, timedOut: false }); });
    }
  );

  if (result.timedOut) {
    return { exitCode: null, signal: "SIGTERM", timedOut: true, errorMessage: "Graph timed out" };
  }

  // Parse last JSON line from stdout
  let graphOutput: Record<string, unknown> = {};
  const lines = stdout.trim().split("\n");
  for (let i = lines.length - 1; i >= 0; i--) {
    const line = lines[i].trim();
    if (line.startsWith("{")) {
      try { graphOutput = JSON.parse(line); break; } catch { /* continue */ }
    } else {
      void onLog("stdout", line + "\n");
    }
  }

  const sessionParams = (graphOutput.sessionParams as Record<string, unknown>) ?? undefined;
  const usage = graphOutput.usage as { inputTokens?: number; outputTokens?: number } | undefined;

  return {
    exitCode: result.exitCode,
    signal: result.signal,
    timedOut: false,
    summary: (graphOutput.summary as string) ?? undefined,
    sessionParams,
    usage: usage ? { inputTokens: usage.inputTokens ?? 0, outputTokens: usage.outputTokens ?? 0 } : undefined,
    errorMessage: result.exitCode !== 0 ? `Graph exited with code ${result.exitCode}\n${stdout.slice(-500)}` : undefined,
  };
}
```

### src/server/test.ts
```typescript
import fs from "node:fs";
import type { AdapterEnvironmentTestContext, AdapterEnvironmentTestResult } from "@paperclipai/adapter-utils";
import { asString } from "@paperclipai/adapter-utils/server-utils";

export async function testEnvironment(ctx: AdapterEnvironmentTestContext): Promise<AdapterEnvironmentTestResult> {
  const checks: AdapterEnvironmentTestResult["checks"] = [];
  const graphFile = asString(ctx.config.graphFile);

  if (!graphFile) {
    checks.push({ code: "no_graph_file", level: "error", message: "adapterConfig.graphFile is not set", hint: "Set graphFile to the absolute path of your LangGraph entry point (.ts or .js)" });
    return { ok: false, checks };
  }

  if (!fs.existsSync(graphFile)) {
    checks.push({ code: "graph_file_missing", level: "error", message: `graphFile not found: ${graphFile}`, hint: "Verify the path is correct and the file exists" });
    return { ok: false, checks };
  }

  checks.push({ code: "graph_file_found", level: "info", message: `Graph file found: ${graphFile}` });

  const runner = asString(ctx.config.runner) ?? "tsx";
  checks.push({ code: "runner_config", level: "info", message: `Runner: ${runner}` });

  return { ok: true, checks };
}
```

### src/server/index.ts
```typescript
import type { AdapterSessionCodec } from "@paperclipai/adapter-utils";

export const sessionCodec: AdapterSessionCodec = {
  deserialize(raw: unknown) {
    if (typeof raw === "object" && raw !== null) return raw as Record<string, unknown>;
    return null;
  },
  serialize(params) { return params; },
  getDisplayId(params) {
    if (!params) return null;
    return (params.stage as string) ?? null;
  },
};

export { execute } from "./execute.js";
export { testEnvironment } from "./test.js";
```

### registry.ts changes (`c:\PROJECTS\paperclip\server\src\adapters\registry.ts`)

Add near the top with other adapter imports:
```typescript
import {
  execute as langgraphExecute,
  testEnvironment as langgraphTestEnvironment,
  sessionCodec as langgraphSessionCodec,
} from "@paperclipai/adapter-langgraph-local/server";
import { agentConfigurationDoc as langgraphAgentConfigurationDoc } from "@paperclipai/adapter-langgraph-local";
```

Add adapter object (near `openCodeLocalAdapter`):
```typescript
const langgraphLocalAdapter: ServerAdapterModule = {
  type: "langgraph_local",
  execute: langgraphExecute,
  testEnvironment: langgraphTestEnvironment,
  sessionCodec: langgraphSessionCodec,
  supportsLocalAgentJwt: false,
  supportsInstructionsBundle: false,
  requiresMaterializedRuntimeSkills: false,
  agentConfigurationDoc: langgraphAgentConfigurationDoc,
};
```

Add to `registerBuiltInAdapters()` array:
```typescript
langgraphLocalAdapter,
```

---

## Part 2: Screening Signal Agent

### Location
`c:\PROJECTS\agentyard\agents\screening-signal\`

### Files to Create

```
agents/screening-signal/
  package.json
  src/
    state.ts       — ScreeningState type
    paperclip.ts   — API helper functions
    nodes.ts       — all LangGraph node functions
    graph.ts       — entry point (reads env, runs graph, writes stdout)
```

### package.json
```json
{
  "name": "screening-signal",
  "version": "0.1.0",
  "type": "module",
  "main": "src/graph.ts",
  "scripts": {
    "install-deps": "npm install"
  },
  "dependencies": {
    "@langchain/langgraph": "^0.2",
    "@anthropic-ai/sdk": "^0.36"
  }
}
```

### src/state.ts
```typescript
export type Candidate = {
  ticker: string;
  company: string;
  rationale: string;
};

export type ScreeningState = {
  // Persistence stage
  stage: "fresh" | "awaiting_criteria_choice" | "awaiting_opencode" | "awaiting_approvals" | "done";

  // From LANGGRAPH_CONTEXT
  issueId: string;
  companyId: string;
  paperclipApiBase: string;
  exchangeDir: string;
  anthropicApiKey: string;

  // Resolved once and cached
  opencodeFsdAgentId: string;

  // Criteria
  rawInputCriteria: string;    // from issue body or latest user comment
  fileCriteria: string;        // contents of screening_criteria.md
  lastUsedCriteria: string;    // from prior sessionParams
  resolvedCriteria: string;    // final normalized criteria to use

  // Delegation
  delegationFile: string;      // /exchange/inbox/opencode/screening-task-{date}.md
  resultsFile: string;         // /exchange/outbox/opencode/screening-results-{date}.md

  // Results
  candidates: Candidate[];
  approvalIds: string[];
  approvedTickers: string[];

  // Token usage (accumulated)
  inputTokens: number;
  outputTokens: number;
};
```

### src/paperclip.ts — API helpers
```typescript
// All calls from host use local_trusted mode — no auth header needed

export async function getAgentIdByNameKey(base: string, companyId: string, nameKey: string): Promise<string | null> {
  const res = await fetch(`${base}/api/companies/${companyId}/agents`);
  const agents = await res.json() as Array<{ id: string; nameKey: string }>;
  return agents.find(a => a.nameKey === nameKey)?.id ?? null;
}

export async function postComment(base: string, issueId: string, body: string): Promise<void> {
  await fetch(`${base}/api/issues/${issueId}/comments`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ body }),
  });
}

export async function createIssue(base: string, companyId: string, opts: {
  title: string; description: string; assigneeAgentId: string; parentId?: string;
}): Promise<string> {
  const res = await fetch(`${base}/api/companies/${companyId}/issues`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ status: "todo", ...opts }),
  });
  const issue = await res.json() as { id: string };
  return issue.id;
}

export async function createApproval(base: string, companyId: string, opts: {
  title: string; description: string;
}): Promise<string> {
  const res = await fetch(`${base}/api/companies/${companyId}/approvals`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ type: "request_board_approval", ...opts }),
  });
  const approval = await res.json() as { id: string };
  return approval.id;
}

export async function getApproval(base: string, approvalId: string): Promise<{ status: string }> {
  const res = await fetch(`${base}/api/approvals/${approvalId}`);
  return res.json() as Promise<{ status: string }>;
}

export async function closeIssue(base: string, issueId: string): Promise<void> {
  await fetch(`${base}/api/issues/${issueId}`, {
    method: "PATCH",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ status: "done" }),
  });
}
```

### src/nodes.ts — node implementations

Key node outlines:

**resolveCriteria**: reads `screening_criteria.md`, compares with `lastUsedCriteria`, sets `stage` and posts a comment if both are available and different.

**normalizeCriteria**: calls Claude Haiku with the raw input + file criteria to produce clean structured markdown criteria. Accumulates token usage.

**delegateToOpencode**: 
- Discovers Full Stack Developer agent ID via API
- Writes task file to `/exchange/inbox/opencode/screening-task-{YYYY-MM-DD}.md`
- Creates sub-issue assigned to `full-stack-developer` with `parentId`
- Posts comment on parent issue: "Delegated to Full Stack Developer. Will resume when results are ready."
- Sets `stage: "awaiting_opencode"`

**checkOpencodeResults**: checks if `resultsFile` exists in `/exchange/outbox/opencode/`. If not, posts "Still waiting for screening results..." and re-exits same stage.

**parseAndPresent**: reads results file, parses candidates (by `## TICKER — Company` headers), creates one approval per candidate via Paperclip API.

**checkApprovals**: fetches each approval, collects `approved` ones, if all resolved proceeds to finalize else re-exits.

**finalizeSelection**: reads `approved_stocks.md`, appends approved tickers, writes back, posts summary comment, closes issue.

### src/graph.ts — entry point

```typescript
import { StateGraph, END } from "@langchain/langgraph";
import type { ScreeningState } from "./state.js";
import * as nodes from "./nodes.js";

// 1. Read env
const ctx = JSON.parse(process.env.LANGGRAPH_CONTEXT ?? "{}");
const session = process.env.LANGGRAPH_SESSION ? JSON.parse(process.env.LANGGRAPH_SESSION) : null;

// 2. Restore or init state
const initialState: ScreeningState = session ?? {
  stage: "fresh",
  issueId: ctx.issueId, companyId: ctx.companyId,
  paperclipApiBase: ctx.paperclipApiBase, exchangeDir: ctx.exchangeDir,
  anthropicApiKey: ctx.anthropicApiKey,
  opencodeFsdAgentId: "",
  rawInputCriteria: ctx.issueBody ?? "",
  fileCriteria: "", lastUsedCriteria: "", resolvedCriteria: "",
  delegationFile: "", resultsFile: "",
  candidates: [], approvalIds: [], approvedTickers: [],
  inputTokens: 0, outputTokens: 0,
};

// On resume, override dynamic fields from fresh context
if (session) {
  initialState.rawInputCriteria = ctx.comments?.filter((c: { authorType: string }) => c.authorType === "user").at(-1)?.body ?? session.rawInputCriteria;
}

// 3. Build graph
const graph = new StateGraph<ScreeningState>({ channels: { /* all state keys */ } })
  .addNode("resolveCriteria", nodes.resolveCriteria)
  .addNode("normalizeCriteria", nodes.normalizeCriteria)
  .addNode("delegateToOpencode", nodes.delegateToOpencode)
  .addNode("checkOpencodeResults", nodes.checkOpencodeResults)
  .addNode("parseAndPresent", nodes.parseAndPresent)
  .addNode("checkApprovals", nodes.checkApprovals)
  .addNode("finalizeSelection", nodes.finalizeSelection)
  .addConditionalEdges("resolveCriteria", s =>
    s.stage === "awaiting_criteria_choice" ? END : "normalizeCriteria"
  )
  .addEdge("normalizeCriteria", "delegateToOpencode")
  .addConditionalEdges("delegateToOpencode", s =>
    s.stage === "awaiting_opencode" ? END : "checkOpencodeResults"
  )
  .addConditionalEdges("checkOpencodeResults", s =>
    s.candidates.length > 0 ? "parseAndPresent" : END
  )
  .addConditionalEdges("parseAndPresent", s =>
    s.stage === "awaiting_approvals" ? END : "checkApprovals"
  )
  .addConditionalEdges("checkApprovals", s =>
    s.approvedTickers.length > 0 ? "finalizeSelection" : END
  )
  .addEdge("finalizeSelection", END);

// Entry node based on stage
const entryNode = {
  fresh: "resolveCriteria",
  awaiting_criteria_choice: "normalizeCriteria",
  awaiting_opencode: "checkOpencodeResults",
  awaiting_approvals: "checkApprovals",
  done: END,
}[initialState.stage] ?? "resolveCriteria";

graph.setEntryPoint(entryNode);

// 4. Run
const compiled = graph.compile();
const finalState = await compiled.invoke(initialState);

// 5. Write output
const output = {
  sessionParams: finalState,
  usage: { inputTokens: finalState.inputTokens, outputTokens: finalState.outputTokens },
  summary: finalState.stage === "done"
    ? `Done. Approved: ${finalState.approvedTickers.join(", ") || "none"}`
    : `Waiting: ${finalState.stage}`,
};
process.stdout.write(JSON.stringify(output) + "\n");
```

### Delegation task file written to opencode inbox

```markdown
# Screening Task — {date}

Read /workspace/conventions.md for paths.

Screen for stocks matching the criteria below. Use Yahoo Finance API
(https://query1.finance.yahoo.com — no key required) for data.

Exclude any tickers already in /exchange/inbox/openclaw/approved_stocks.md.

Write results to:
  /exchange/outbox/opencode/screening-results-{date}.md

Format each candidate as:
## TICKER — Company Name
- Yield: X%
- Market Cap: $XB
- Debt/Equity: X.X
- Why it passes: ...

Max 10 candidates, ranked best-first. Post a Paperclip comment on issue
{issueId} when done (http://host.docker.internal:3100).

---

## Screening Criteria

{resolvedCriteria}
```

---

## Verification Steps

1. `cd c:\PROJECTS\paperclip && pnpm install` — picks up new adapter package
2. `pnpm typecheck` — confirms adapter types compile
3. `cd c:\PROJECTS\agentyard\agents\screening-signal && npm install`
4. Restart Paperclip: `pnpm dev` (from paperclip dir)
5. In Paperclip UI: Create agent → name `screening-signal`, adapter `langgraph_local`, config:
   ```json
   { "graphFile": "C:/PROJECTS/agentyard/agents/screening-signal/src/graph.ts" }
   ```
6. Create issue assigned to `screening-signal`: title `Screen for high-yield pipeline stocks`, body `find me midstream pipeline stocks with yield above 5% that are near their 52-week low`
7. Agent wakes → normalizes criteria via Haiku → creates opencode sub-issue → exits `awaiting_opencode`
8. Full Stack Developer wakes on sub-issue → screens stocks → writes results file → closes sub-issue
9. Comment on parent issue → agent re-wakes → finds results → creates approval items → exits `awaiting_approvals`
10. Approve candidates in Paperclip UI → comment on issue → agent finalizes → appends to `approved_stocks.md` → closes issue

---

## Key Constraints to Watch

- `PaperclipWakeIssue` has no `body` field — adapter must `GET /api/issues/{id}` to get full description
- `local_trusted` auth means no `Authorization` header needed from host processes
- Graph exit code 0 = clean (interrupt or done); non-zero = error
- Only the **last JSON line** of stdout is parsed as graph output — log freely to stderr
- opencode API base from inside opencode container: `http://host.docker.internal:3100`
- opencode reads results file from `/exchange/outbox/opencode/` — this maps to `./shared/outbox/opencode/` on host
