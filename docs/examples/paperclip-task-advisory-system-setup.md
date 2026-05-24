# Advisory System Setup: Stock Portal, Daily Monitor, and Monthly Screener

Execute the following three actions in order:

1. Register both Paperclip routines (SUB-TASK B) so the agent assignments are confirmed before the portal is built.
2. Delegate the portal build to the Full Stack Developer (SUB-TASK A).
3. Verify completion criteria, post a summary comment, and close this issue.

> **CONSTRAINT — ALL ROUTINES MUST BE PAPERCLIP ROUTINES**
> Do NOT create Claude Code cloud routines (claude.ai/code/routines or the /schedule skill).
> Both routines in SUB-TASK B must be registered exclusively via the Paperclip routines API.
> Creating routines in any other system is a task failure.

---

## FILE FORMAT CONTRACT

The portal parses markdown files produced by the daily and monthly routines. Both the portal developer and the routine issue bodies must conform to these specifications exactly.

### Daily Alert Files

**Path:** `/exchange/outbox/openclaw/daily-alert-{YYYY-MM-DD}.md`
**Glob pattern used by portal:** `daily-alert-*.md`

A summary line must appear near the top:
```
Summary: N ON SALE, N MAJOR EVENT, N SENTIMENT SHIFT, N WATCHLIST NOTE, N CLEAN
```

Required sections in this order (all must appear even if empty):
```
## ON SALE
## MAJOR EVENT
## SENTIMENT SHIFT
## WATCHLIST NOTE
## CLEAN
## Data Issues
## Sources
```

Every ticker entry in sections ON SALE through CLEAN must use this exact table structure:
```
| Ticker | Alert Type | Near-Term Support | Deep Floor | Downtrend | Sell Target | Notes |
|--------|-----------|------------------|------------|-----------|-------------|-------|
```

### Monthly Screen Files

**Path:** `/exchange/outbox/openclaw/monthly-screen-{YYYY-MM-DD}.md`
**Glob pattern used by portal:** `monthly-screen-*.md`

Required sections:
```
## Executive Summary
## Finalist Recommendations
### TICKER   (one subsection per finalist)
## Scoring Table
## Not Recommended
## Sources
```

Each `### TICKER` subsection must include: Sector, Current price and market cap, Dividend/distribution yield, 10-year high and low, Current price position as % of that range, Prior recovery evidence, Cyclical macro driver, Income history across cycles, Key metrics (P/E, revenue growth, D/E, FCF), Key risks, Analyst consensus and count, Suggested alert threshold.

The Scoring Table covers all candidates that passed hard filters, with ranking criteria as columns. The Not Recommended table lists exclusions with the specific failing filter.

---

## SUB-TASK A — Portal Build

Create a Paperclip issue for the Full Stack Developer (opencode agent) with the following content.

**Issue title:** `stock-portal-build`
**Assigned to:** Full Stack Developer

---

Build the Stock Advisory Portal as specified below. The portal covers the stock workflow UI only — it does not replicate Paperclip dashboard functionality. No agent config, no budget views, no activity feed.


### STEP 0 — VERIFY PAPERCLIP API CONNECTIVITY BEFORE BUILDING ANYTHING

Before writing any portal code, confirm the Paperclip API is reachable from this container and that your credentials work. Run:

```sh
curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer $PAPERCLIP_API_KEY" \
  "$PAPERCLIP_API_URL/api/agents/me"
```

Expected result: HTTP 200. If you get anything else, **stop and post a comment** with the error and the value of `$PAPERCLIP_API_URL` — do not proceed with the portal build until this is resolved.

Once confirmed, use the verified `$PAPERCLIP_API_URL` value as the Paperclip base URL in `server.js`. Never hardcode a URL — always read it from `process.env.PAPERCLIP_API_URL` at runtime so that the portal works correctly regardless of environment.


### SERVE CONVENTIONS — MANDATORY

The only server allowed is `/exchange/outbox/opencode/serve/server.js` on port 9081. Never start a server outside that path. Before starting, check whether the server is already running by reading `serve-process.json`. Always start in background mode: `node /exchange/outbox/opencode/serve/server.js &` followed by `disown`. Static files go in `/exchange/outbox/opencode/serve/www/stock-portal/`. Register the service as `stock-portal` in `serve-process.json`. Host access is `http://localhost:9081/stock-portal`. Use `http://opencode:9081/stock-portal` when verifying from openclaw.


### FILE FORMAT CONTRACT

The portal parses files produced by two routines. Use these exact specifications — no guessing at structure.

**Daily alert files** at `/exchange/outbox/openclaw/daily-alert-{YYYY-MM-DD}.md`:
- Summary line: `Summary: N ON SALE, N MAJOR EVENT, N SENTIMENT SHIFT, N WATCHLIST NOTE, N CLEAN`
- Sections (parse by `## heading`): ON SALE, MAJOR EVENT, SENTIMENT SHIFT, WATCHLIST NOTE, CLEAN, Data Issues, Sources
- Table columns (parse by exact heading names): `Ticker | Alert Type | Near-Term Support | Deep Floor | Downtrend | Sell Target | Notes`

**Monthly screen files** at `/exchange/outbox/openclaw/monthly-screen-{YYYY-MM-DD}.md`:
- Sections: Executive Summary, Finalist Recommendations, Scoring Table, Not Recommended, Sources
- Finalists as `### TICKER` subsections under Finalist Recommendations
- Per-finalist fields: Sector, Current price and market cap, Yield, 10-year high/low, Cycle position %, Prior recovery, Cyclical macro driver, Income history, P/E, Revenue growth, D/E, FCF, Analyst consensus, Alert threshold


### BUILD FOUR SCREENS


**1. Alert Dashboard (`index.html`)**

Reads the latest `/exchange/outbox/openclaw/daily-alert-*.md` file (newest by filename). Parses the Summary line to show counts for all five categories: ON SALE, MAJOR EVENT, SENTIMENT SHIFT, WATCHLIST NOTE, CLEAN. Displays collapsible sections per category showing the full table (Ticker, Alert Type, Near-Term Support, Deep Floor, Downtrend, Sell Target, Notes). Includes a historical report selector for the last 30 files.


**2. Watchlist Manager (`watchlist.html`)**

Reads `/exchange/inbox/openclaw/approved_stocks.md`. Displays a table of all tickers with columns: Ticker, Company, Date Added, Alert Threshold, Notes, Status. Each row includes an **Active Monitoring toggle button** that switches the ticker between Active Monitoring and Paused by calling `PATCH /stock-portal/api/watchlist/:ticker/status`. The button label and style must reflect current state: green "Active" when monitoring is on, grey "Paused" when off. The toggle rewrites the ticker's section in `approved_stocks.md` (moving the row between `## Active Monitoring` and `## Paused`). No Entry Price column.


**3. Approval Queue (`approvals.html`)**

Reads pending board approval requests from the Paperclip API. Displays each candidate card with ticker, yield, cycle position, investment thesis, and a link to the full screening report. Read-only — approvals are actioned in the Paperclip board. Use `process.env.PAPERCLIP_API_URL` and `process.env.PAPERCLIP_API_KEY` in `server.js` — both are confirmed available after Step 0.


**4. Screening Reports (`screening.html`)**

Lists all `/exchange/outbox/openclaw/monthly-screen-*.md` files newest first. Renders each as styled HTML: Executive Summary at top, then finalist cards (one per `### TICKER` subsection), then the Scoring Table as a sortable HTML table.


### API ROUTES

Add these routes to `server.js`. All data is served through these — no direct filesystem access from browser JavaScript.

```
GET /stock-portal/api/alerts/latest
GET /stock-portal/api/alerts/history
GET /stock-portal/api/alerts/:date
GET /stock-portal/api/watchlist
PATCH /stock-portal/api/watchlist/:ticker/status
GET /stock-portal/api/approvals
GET /stock-portal/api/screening
GET /stock-portal/api/screening/:date
```


### TECH CONSTRAINTS

No npm, no build step, no external CDN. Node.js built-ins only for `server.js`. Vanilla JavaScript for frontend. Dark theme, monospace font for tickers and numbers, mobile-responsive.


### BUILD ORDER

0. Verify Paperclip API connectivity (Step 0 above) — do not proceed until HTTP 200 confirmed
1. `server.js` with all API routes (stub responses first, real data wired in as each screen is built)
2. Alert Dashboard (`index.html`) — wire to real alert data
3. Watchlist Manager (`watchlist.html`) — read + status toggle
4. Approval Queue (`approvals.html`)
5. Screening Reports (`screening.html`)

Write a `README.md` in `/exchange/outbox/opencode/serve/www/stock-portal/` documenting how to access the portal, all data source paths, and known limitations.

When complete, verify the portal is accessible at `http://opencode:9081/stock-portal`, post a comment with the URL and a summary of what was built, then close this issue.

---

## SUB-TASK B — Routine Setup

Read `skills/paperclip/SKILL.md` for the Paperclip routines API.
Register both routines **in Paperclip only** — do not use the Claude Code /schedule skill or create claude.ai cloud routines under any circumstances.

Check whether each routine already exists before creating it. If a routine for the daily monitor or monthly screener is already registered, skip creating it and note the existing routine ID in your closing comment.


### ROUTINE 1 — Daily Stock Monitor

**Trigger:** Monday–Friday, 07:00 local time (cron: `0 7 * * 1-5`)
**Assigned to:** Stock Watch Analyst
**Concurrency policy:** skip if an issue already exists for today's date

**Issue title template:** `stock-watcher-daily-{YYYY-MM-DD}`

**Issue body template:**

```
Run the daily stock monitoring pass for {YYYY-MM-DD}.

STEP 1 — ALERT EVALUATION

Read /exchange/inbox/openclaw/approved_stocks.md. Process every ticker listed under Active Monitoring.
Read alert thresholds from /exchange/inbox/openclaw/screening_criteria.md. Apply per-ticker Alert Threshold overrides where present.

Fetch from Yahoo Finance: current price, previous close, % change today, 30-day high, % drop from 30-day high, volume vs 30-day average. Search news (last 48h) and analyst activity (last 7 days).

Classify each ticker into exactly one category:
- ON SALE: price dropped >= threshold% from 30-day high with no fundamental cause driving the drop
- MAJOR EVENT: earnings miss or beat >10%; CEO or CFO departure; SEC action or lawsuit; >=2 analyst downgrades in 7 days; guidance cut; acquisition announcement; trading halt; or volume >3x 30-day average with no news (label UNUSUAL VOLUME)
- SENTIMENT SHIFT: consistent negative tone across >=3 credible sources in 48h, or a previously bullish analyst turns bearish
- WATCHLIST NOTE: earnings within 5 business days; positive news; volume 1.5x-3x average
- CLEAN: no notable conditions

If a negative fundamental event drives a price drop, classify as MAJOR EVENT, not ON SALE. ON SALE requires the absence of a fundamental cause.

If data cannot be fetched for a ticker, place it in Data Issues with a one-line explanation.

STEP 2 — PRICE STRUCTURE ANALYSIS

Run this prompt for every ticker, regardless of alert category:

"For [TICKER], analyze the following and return exactly 4 values with no explanations in the output. To determine the values, use this logic: NEAR-TERM SUPPORT — find the price zone where buyers most frequently step in based on volume history and the stock tends to bounce. DEEP FLOOR — find the price zone that has repeatedly held during major selloffs or corrections over multiple years. DOWNTREND — determine if the current price level is a result of a structural downtrend over the last two years specifically, not longer historical patterns, rather than a normal price oscillation around fair value. SELL TARGET — find the single price point with the highest probability of being reached under normal market conditions based on historical resistance levels, analyst targets, and mean reversion, excluding outlier highs — be conservative, bias toward the nearest resistance ceiling the stock is most likely to stall at. Output format, nothing else: 1. NEAR-TERM SUPPORT: $XX-$XX  2. DEEP FLOOR: $XX-$XX  3. DOWNTREND: True / False  4. SELL TARGET: $XX"

OUTPUT

Write to /exchange/outbox/openclaw/daily-alert-{YYYY-MM-DD}.md.

Include a summary line near the top:
Summary: N ON SALE, N MAJOR EVENT, N SENTIMENT SHIFT, N WATCHLIST NOTE, N CLEAN

Required sections in order (all must appear even if empty):
## ON SALE
## MAJOR EVENT
## SENTIMENT SHIFT
## WATCHLIST NOTE
## CLEAN
## Data Issues
## Sources

Every ticker in every section must use this table:
| Ticker | Alert Type | Near-Term Support | Deep Floor | Downtrend | Sell Target | Notes |
|--------|-----------|------------------|------------|-----------|-------------|-------|

No ticker may appear in more than one section. No Active Monitoring ticker may be omitted.

When done, post a closing comment listing all flagged tickers grouped by category (ON SALE, MAJOR EVENT, SENTIMENT SHIFT, WATCHLIST NOTE) and all tickers where Downtrend is True. Then close this issue.
```


### ROUTINE 2 — Monthly Stock Screener

**Trigger:** 1st of each month, 18:00 local time (cron: `0 18 1 * *`)
**Assigned to:** Financial Research Analyst
**Concurrency policy:** skip if an issue already exists for this month

**Issue title template:** `stock-analyst-monthly-{YYYY-MM-DD}`

**Issue body template:**

```
Run the monthly stock screening pass for {YYYY-MM-DD}.

Read /exchange/inbox/openclaw/screening_criteria.md for all criteria: sectors, hard filters, pool size, finalist count, and ranking weights. Do not use hardcoded values.

Do not recommend any ticker already listed under Active Monitoring in /exchange/inbox/openclaw/approved_stocks.md.

STEP 1 — BUILD CANDIDATE POOL
Use web_search to identify publicly traded companies matching the cyclical income profile in screening_criteria.md. Save tickers to /exchange/scratch/openclaw/candidates.txt. Target the pool size from the criteria file (typically 15-25 stocks).

STEP 2 — HARD FILTER PASS
For each candidate, fetch fundamentals via Yahoo Finance quoteSummary with modules: price, summaryDetail, financialData, defaultKeyStatistics, incomeStatementHistory, recommendationTrend, upgradeDowngradeHistory. Add sleep 1 between requests. Apply every hard filter from screening_criteria.md. Record the specific failing filter for each exclusion.

STEP 3 — QUALITATIVE RESEARCH
For each candidate that passes hard filters, research: price cycle history and evidence of prior recoveries, distribution history across upcycles and downcycles, business model and cash flow characteristics, current position in the historical cycle.

STEP 4 — SELECT FINALISTS
Rank by criteria in screening_criteria.md (typically: depth into historical cycle low, income yield, prior recovery strength). Select up to the finalist count specified.

OUTPUT

Write to /exchange/outbox/openclaw/monthly-screen-{YYYY-MM-DD}.md.

Required sections:
## Executive Summary
## Finalist Recommendations
### TICKER  (one subsection per finalist, containing: Sector, Current price and market cap, Dividend/distribution yield, 10-year high and low, Current price position as % of that range, Prior recovery evidence, Cyclical macro driver, Income history across cycles, Key metrics: P/E, revenue growth, D/E, FCF, Key risks, Analyst consensus and count, Suggested alert threshold)
## Scoring Table  (all hard-filter-pass candidates with ranking criteria as columns)
## Not Recommended  (exclusions with the specific filter that failed)
## Sources

BOARD APPROVALS

For each finalist, file a request_board_approval via the Paperclip API:
- Title: Add [TICKER] to watchlist? — Cyclical income play
- Body: one paragraph covering yield, current cycle position (% of 10-year range), and investment thesis
- Report path: /exchange/outbox/openclaw/monthly-screen-{YYYY-MM-DD}.md

Do not file for candidates that did not make the finalist list.

When done:
1. Post a closing comment listing each finalist with ticker, yield, cycle position, and approval ID
2. Confirm all request_board_approval calls were filed
3. Delete /exchange/scratch/openclaw/candidates.txt
4. Close this issue
```

---

## COMPLETION CRITERIA

Close this issue when all three of the following are true:

1. **Portal is live:** `http://opencode:9081/stock-portal` is accessible and all four screens load without errors. The Alert Dashboard renders the latest `daily-alert-*.md` file correctly, showing all five category counts. The Watchlist Manager toggle buttons successfully move tickers between Active Monitoring and Paused.
2. **Routines are registered in Paperclip:** Both the Daily Stock Monitor and Monthly Stock Screener routines are active in Paperclip (verified via the Paperclip routines API). No Claude Code cloud routines (claude.ai/code/routines) have been created as part of this setup.
3. **Comment posted:** A closing comment lists the portal URL, both routine IDs, and a one-paragraph summary of what was built and registered.
