# Dead Code & Docs Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Delete the abandoned Vue prototype and dead SMC-paper-trading library sitting unused inside the SolidJS dashboard, and fix CLAUDE.md's stale claims about the cable adapter, the dashboard framework, and the (previously undocumented) node-sidecar process.

**Architecture:** Pure subtraction plus documentation — no runtime behavior changes. Every file targeted for deletion was confirmed (in the audit that produced this plan, and re-confirmed live below) to have zero references from anything reachable from `dashboard/src/main.jsx`.

**Tech Stack:** SolidJS/Vite dashboard, Markdown docs.

## Global Constraints

- Re-verify zero references immediately before each deletion in this plan — file contents may have shifted since the audit that identified them as dead.
- Do not delete anything not explicitly listed below, even if it looks similarly dead — flag it instead and move on.

---

### Task 1: Delete the dead Vue app

**Files:**
- Delete: `dashboard/src/main.js`
- Delete: `dashboard/src/App.vue`
- Delete: `dashboard/src/router/index.js`
- Delete: `dashboard/src/composables/useFlash.js`, `usePositions.js`, `useAnalysis.js`, `useDashboard.js`
- Delete: `dashboard/src/components/ClosedTrades.vue`, `PositionRow.vue`, `StatsBar.vue`, `Header.vue`, `OpenPositions.vue`
- Delete: `dashboard/src/views/Signals.vue`, `Strategies.vue`, `Settings.vue`, `Analysis.vue`, `Dashboard.vue`
- Delete: `dashboard/src/components/settings/CalibrationRunsPanel.vue`, `NetworkStatusPanel.vue`, `RecursiveFormNode.vue`
- Delete: `dashboard/src/components/analysis/SmcAnalysis.vue`, `CalibrationPanel.vue`, `MarketOverview.vue`, `HistoricalBehavior.vue`, `AiInsights.vue`
- Modify: `dashboard/package.json`

**Interfaces:**
- Consumes: none.
- Produces: none — pure deletion. `dashboard/src/index.html` already only loads `/src/main.jsx` (the live Solid entry point), confirmed unaffected.

- [ ] **Step 1: Re-confirm zero live references right before deleting**

Run:
```bash
cd dashboard/src
find . -iname "*.vue" -o -name "main.js" -o -path "*/router/index.js" -o -path "*/composables/*.js" | while read -r f; do
  base=$(basename "$f")
  grep -rl "$base" . --include="*.jsx" | grep -v "\.vue$" && echo "STOP: $f is referenced from a .jsx file — do not delete"
done
```
Expected: no output (no `STOP:` lines). If any file prints a `STOP:` line, halt this task and report — something changed since the audit.

- [ ] **Step 2: Delete all the Vue files, `main.js`, `router/index.js`, and `composables/`**

```bash
cd dashboard/src
git rm main.js App.vue router/index.js
git rm -r composables/
git rm components/ClosedTrades.vue components/PositionRow.vue components/StatsBar.vue components/Header.vue components/OpenPositions.vue
git rm views/Signals.vue views/Strategies.vue views/Settings.vue views/Analysis.vue views/Dashboard.vue
git rm components/settings/CalibrationRunsPanel.vue components/settings/NetworkStatusPanel.vue components/settings/RecursiveFormNode.vue
git rm components/analysis/SmcAnalysis.vue components/analysis/CalibrationPanel.vue components/analysis/MarketOverview.vue components/analysis/HistoricalBehavior.vue components/analysis/AiInsights.vue
```

Note: `components/settings/NetworkStatusPanel.vue` and `.../RecursiveFormNode.vue` are the dead Vue *counterparts* of the live `.jsx` files with the same base name — deleting the `.vue` one leaves the `.jsx` one (already confirmed live and referenced from `views/Settings.jsx`) untouched. Same for `views/Settings.vue`/`views/Dashboard.vue`/etc — always the `.vue` extension is the one being removed here, never `.jsx`.

- [ ] **Step 3: Remove `vue`/`vue-router` from `package.json`**

Current `dashboard/package.json` dependency lines (in context):
```json
    "@rails/actioncable": "^8.0.0",
    "axios": "^1.19.0",
    "lightweight-charts": "^5.2.0",
    "solid-toast": "^0.5.0",
    "tapable": "^2.3.3",
    "vue": "^3.5.13",
    "vue-router": "^4.6.4"
```
Replace with:
```json
    "@rails/actioncable": "^8.0.0",
    "axios": "^1.19.0",
    "lightweight-charts": "^5.2.0",
    "solid-toast": "^0.5.0",
    "tapable": "^2.3.3"
```
(Verify exact surrounding lines with `grep -n -B6 '"vue"' dashboard/package.json` first — the dependency block's key order may not match exactly what's captured here since this plan was written against a point-in-time read; the edit is "remove the `"vue"` and `"vue-router"` lines and the trailing comma on the line before them," not a literal block replace if the file has drifted.)

- [ ] **Step 4: Update the lockfile**

Run: `cd dashboard && npm install`
Expected: `package-lock.json` updates to drop `vue`/`vue-router` and their transitive deps; no errors.

- [ ] **Step 5: Build check**

Run: `cd dashboard && npm run build`
Expected: clean build — confirms nothing in the live Solid tree was accidentally importing from the deleted files.

- [ ] **Step 6: Commit**

```bash
git add dashboard/package.json dashboard/package-lock.json
git commit -m "dashboard: delete abandoned Vue prototype — unreferenced since the Solid migration"
```

---

### Task 2: Delete the dead SMC paper-trading helper (corrected scope)

**CORRECTION (found during implementation, 2026-08-11):** the original audit that
produced this task was wrong about the scope. `dashboard/src/components/charts/
PriceChart.jsx` (itself referenced live by `components/research/PremiumChart.jsx`
and `views/Charts.jsx`) actively imports from `lib/smc/smcEngine.js`,
`lib/smc/ictEngine.js`, `lib/smc/setupScanner.js`, and `lib/smc/canvasOverlay.js`
via multi-line `import { ... } from '../../lib/smc/X'` statements — real,
live, in-use code for the chart's SMC/ICT pattern overlays and setup scanning.
The original re-verification grep's pattern likely missed this because
`PriceChart.jsx` either didn't exist yet when the original audit ran, or the
grep pattern's line-based matching missed the multi-line import syntax — either
way, only `lib/smc/paperTrader.js` is confirmed genuinely dead (zero references
anywhere, and it calls a phantom `/api/paper/quote` endpoint with no matching
Rails route). The other four files stay.

**Files:**
- Delete: `dashboard/src/lib/smc/paperTrader.js` only

**Interfaces:**
- Consumes: none.
- Produces: none — pure deletion. `smcEngine.js`, `ictEngine.js`,
  `setupScanner.js`, `canvasOverlay.js` are NOT touched by this task — they are
  live dependencies of `PriceChart.jsx`.

- [ ] **Step 1: Re-confirm zero references to paperTrader.js specifically**

Run: `grep -rln "paperTrader" dashboard/src --include="*.jsx" --include="*.js" | grep -v "lib/smc/paperTrader.js"`
Expected: no output. If anything prints, stop and report — do not delete a file a live component actually imports.

Also re-confirm the other four files in `lib/smc/` are genuinely still live before touching anything: `grep -rn "from ['\"].*lib/smc/\(smcEngine\|ictEngine\|setupScanner\|canvasOverlay\)['\"]" dashboard/src --include="*.jsx" -A0 -B10 | grep -c "PriceChart.jsx"` should be non-zero (or simply open `dashboard/src/components/charts/PriceChart.jsx` and confirm its import block still references all four). If any of the four turn out to be unreferenced after all, treat that as a new finding to report, not something to delete under this task's original (now-corrected) instruction — this task's scope is `paperTrader.js` only.

- [ ] **Step 2: Delete**

```bash
git rm dashboard/src/lib/smc/paperTrader.js
```

- [ ] **Step 3: Build check**

Run: `cd dashboard && npm run build`
Expected: clean.

- [ ] **Step 4: Commit**

```bash
git commit -m "dashboard: delete dead paperTrader.js — unreferenced, called a phantom /api/paper/quote endpoint

The other lib/smc/*.js files (smcEngine, ictEngine, setupScanner,
canvasOverlay) are live dependencies of components/charts/PriceChart.jsx
and stay — corrected from the original plan's broader deletion scope,
which was based on a stale audit."
```

---

### Task 3: Fix CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

**Interfaces:** none — documentation only.

- [ ] **Step 1: Fix the Solid Cable claim**

Current `CLAUDE.md` (Stack section):
```markdown
- Solid Cable (ActionCable WebSocket backend)
```
Replace with:
```markdown
- ActionCable over the `redis` adapter (`config/cable.yml`) — not Solid Cable
```

- [ ] **Step 2: Fix the process count and table**

Current:
```markdown
`./bin/dev` starts 4 processes via `Procfile.dev`:

| Process | Command | Purpose |
|---------|---------|---------|
| `web` | `bin/rails server -p 3001` | Rails API server |
| `trading` | `ENABLE_TRADING_SERVICES=true bundle exec rake trading:daemon` | Trading brain (11 services in threads) |
| `jobs` | `bin/jobs` | Solid Queue worker (recurring tasks) |
| `dashboard` | `cd dashboard && npm run dev` | Next.js frontend |

Web and trading are separate OS processes sharing PostgreSQL and Redis — no shared in-process objects.
```
Replace with:
```markdown
`./bin/dev` starts 5 processes via `Procfile.dev`:

| Process | Command | Purpose |
|---------|---------|---------|
| `web` | `bin/rails server -p 3001` | Rails API server |
| `trading` | `ENABLE_TRADING_SERVICES=true bundle exec rake trading:daemon` | Trading brain (11 services in threads) |
| `jobs` | `bin/jobs` | Solid Queue worker (recurring tasks) |
| `dashboard` | `cd dashboard && npm run dev` | SolidJS + Vite frontend (dev server on :5181, proxies `/api` and `/cable` to :3001) |
| `sidecar` | `cd node-sidecar && npm start` | Node.js execution sidecar — Redis-only today, see below |

Web and trading are separate OS processes sharing PostgreSQL and Redis — no shared in-process objects.

### node-sidecar

`node-sidecar/` is a TypeScript process (`@shubhamtaywade82/dhanhq-ts`) meant to
execute multi-leg option spread skills (bull_call_spread, iron_condor, etc.)
that the Ruby `dhanhq` gem doesn't support. It communicates with Rails purely
over Redis pub/sub — it has no HTTP surface and Rails never calls it directly:

| Channel | Direction | Payload |
|---|---|---|
| `dhan:execution:intents` | Rails → sidecar | `{intent_id, strategy, params, correlation_id, risk_limits, created_at}` |
| `dhan:execution:fills` | sidecar → Rails | `{intent_id, correlation_id, is_paper, fill_price, quantity, security_id, filled_at}` |
| `dhan:execution:exits` | sidecar → Rails | `{position_id, correlation_id, exit_price, pnl, reason, is_paper, exited_at}` |
| `dhan:auth:rotated` | Rails → sidecar | Rails' `Dhan::TokenManager` publishes on token refresh; sidecar re-reads `dhan:auth:access_token` |

**Currently dormant**: nothing in `app/` or `lib/` calls
`Dhan::SidecarPublisher.publish_intent`, so `dhan:execution:intents` never
receives a message and the sidecar's execution engines never run.
`Entries::EntryGuard` places every order directly through
`Orders::GatewayLive`/`GatewayPaper`. The sidecar opens no Dhan WebSocket
connection (removed — it collided with Rails' own `Live::MarketFeedHub`/
`Live::OrderUpdateHub` on reconnect). Wiring spreads up for real is future
work: it needs an `EntryGuard` → `SidecarPublisher` call site, and the
sidecar's own exit-payload field mismatch (`executor.ts` reads
`signal.positionId`/`correlationId`/`exitPrice`, none of which exist on
`PositionMonitor`'s actual `"exit"` event) needs fixing first.
```

- [ ] **Step 3: Fix the frontend framework claim in the process table**

This is already fixed by Step 2's table replacement (the `dashboard` row now says "SolidJS + Vite frontend" instead of "Next.js frontend") — no separate edit needed. Confirm with:

Run: `grep -n "Next.js" CLAUDE.md`
Expected: no output.

- [ ] **Step 4: Proofread the full diff**

Run: `git diff CLAUDE.md`
Expected: only the three changes above — no accidental edits elsewhere in the file.

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: fix stale CLAUDE.md claims — cable adapter, dashboard framework, undocumented sidecar"
```
