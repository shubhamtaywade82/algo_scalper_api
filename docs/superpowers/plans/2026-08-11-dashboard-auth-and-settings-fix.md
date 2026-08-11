# Dashboard Auth & Settings Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the dashboard's non-functional fake login/register flow (real access control is already `X-Api-Key`/`API_DASHBOARD_TOKEN`), make every REST call that hits a dashboard-token-gated route actually send that header, and wire up three settings features (fast entry mode, IP whitelist update, deep-merge config editor) whose backend logic already exists but was never exposed as routes.

**Architecture:** Solid dashboard (Vite dev server on :5181, proxies `/api`+`/cable` to Rails on :3001) talks to Rails via REST (`fetch`/axios) gated by `Api::TokenAuthenticatable#authenticate_dashboard_token!` (checks `X-Api-Key`/`Authorization: Bearer` against `API_DASHBOARD_TOKEN`) and a separate settings-write gate `authenticate_settings!` (checks `X-Settings-Update-Token` against `SETTINGS_UPDATE_TOKEN`). Both checks no-op when their respective env var is unset (dev default) — which is exactly why the missing headers are invisible today and will break the moment production sets `API_DASHBOARD_TOKEN`.

**Tech Stack:** SolidJS (Vite), Ruby/Rails 8 (`Api::SettingsController`, `AlgoConfig::DocumentStore`, `Signal::FastEntryMode`, `Dhan::IpService`).

## Global Constraints

- Reuse `dashboard/src/lib/dashboardApi.js`'s existing `dashboardApiHeaders()` helper for the `X-Api-Key` fix — do not create a new HTTP wrapper or migrate call sites to axios. Two files (`views/Charts.jsx`, `views/TrailEngine.jsx`) already use this helper correctly; follow that exact pattern.
- Do not change any response JSON shape a component already parses (e.g. `data.success`, `data.fast_entry_mode`, `data.flag`) — the three new Rails routes must match what the dashboard already sends/expects, verified against real file contents in this plan, not assumed.
- New Rails controller actions follow the existing `Api::SettingsController` pattern exactly: rescue `StandardError`, log via `Rails.logger.error`, return JSON error with a status code — same shape as `index`/`update_bulk`/`change_logs`.
- Real user auth (session/token backend) is explicitly out of scope — this plan deletes the fake auth UI, it does not replace it with a real one.

---

### Task 1: Remove the fake auth flow

**Files:**
- Delete: `dashboard/src/views/Login.jsx`
- Delete: `dashboard/src/views/Register.jsx`
- Delete: `dashboard/src/components/auth/AuthGuard.jsx`
- Delete: `dashboard/src/stores/useAuth.js`
- Modify: `dashboard/src/App.jsx`
- Modify: `dashboard/src/components/layout/Sidebar.jsx`

**Interfaces:**
- Consumes: none new.
- Produces: `App.jsx`'s route tree no longer has a `Protected`/`AuthGuard` wrapper — `AppShell` becomes the direct top-level routed component. `Sidebar.jsx` no longer renders a user-profile/sign-in footer block.

- [ ] **Step 1: Confirm no other file references the four files being deleted**

Run: `grep -rln "useAuth\|AuthGuard\|views/Login\|views/Register" dashboard/src`
Expected: only `App.jsx`, `components/layout/Sidebar.jsx`, and the four files themselves. If anything else matches, stop and report before deleting.

- [ ] **Step 2: Delete the four files**

```bash
git rm dashboard/src/views/Login.jsx dashboard/src/views/Register.jsx dashboard/src/components/auth/AuthGuard.jsx dashboard/src/stores/useAuth.js
```

- [ ] **Step 3: Edit `App.jsx`**

Current `dashboard/src/App.jsx:1-45` (imports + `Protected`):
```jsx
import { Router, Route, Navigate } from '@solidjs/router'
import { Show, lazy } from 'solid-js'
import { DashboardContext } from './context/DashboardContext'
import { Toaster } from 'solid-toast'
import { useDashboard } from './stores/useDashboard'
import { usePositions } from './stores/usePositions'
import { useUIStore } from './stores/ui.store'
import Header from './components/Header'
import Sidebar from './components/layout/Sidebar'
import './style.css'

const Dashboard = lazy(() => import('./views/Dashboard'))
const Strategies = lazy(() => import('./views/Strategies'))
const StrategyCreator = lazy(() => import('./views/StrategyCreator'))
const Signals = lazy(() => import('./views/Signals'))
const Analysis = lazy(() => import('./views/Analysis'))
const Settings = lazy(() => import('./views/Settings'))
const Ledger = lazy(() => import('./views/Ledger'))
const TrailEngine = lazy(() => import('./views/TrailEngine.jsx'))
const OptionScalper = lazy(() => import('./views/OptionScalper'))
const OptionChain = lazy(() => import('./views/OptionChain'))
const Backtester = lazy(() => import('./views/Backtester'))
const Replay = lazy(() => import('./views/Replay'))
const Alpha = lazy(() => import('./views/Alpha'))
const Charts = lazy(() => import('./views/Charts'))

// New TDD routes — all backends implemented
const MarketWatch = lazy(() => import('./views/MarketWatch'))
const Positions = lazy(() => import('./views/Positions'))
const Holdings = lazy(() => import('./views/Holdings'))
const Funds = lazy(() => import('./views/Funds'))
const Reports = lazy(() => import('./views/Reports'))
const Alerts = lazy(() => import('./views/Alerts'))
const Scheduler = lazy(() => import('./views/Scheduler'))
const Logs = lazy(() => import('./views/Logs'))

// Auth routes
const Login = lazy(() => import('./views/Login'))
const Register = lazy(() => import('./views/Register'))
import AuthGuard from './components/auth/AuthGuard'

function Protected(props) {
  return <AuthGuard>{props.children}</AuthGuard>
}
```

Replace with:
```jsx
import { Router, Route, Navigate } from '@solidjs/router'
import { Show, lazy } from 'solid-js'
import { DashboardContext } from './context/DashboardContext'
import { Toaster } from 'solid-toast'
import { useDashboard } from './stores/useDashboard'
import { usePositions } from './stores/usePositions'
import { useUIStore } from './stores/ui.store'
import Header from './components/Header'
import Sidebar from './components/layout/Sidebar'
import './style.css'

const Dashboard = lazy(() => import('./views/Dashboard'))
const Strategies = lazy(() => import('./views/Strategies'))
const StrategyCreator = lazy(() => import('./views/StrategyCreator'))
const Signals = lazy(() => import('./views/Signals'))
const Analysis = lazy(() => import('./views/Analysis'))
const Settings = lazy(() => import('./views/Settings'))
const Ledger = lazy(() => import('./views/Ledger'))
const TrailEngine = lazy(() => import('./views/TrailEngine.jsx'))
const OptionScalper = lazy(() => import('./views/OptionScalper'))
const OptionChain = lazy(() => import('./views/OptionChain'))
const Backtester = lazy(() => import('./views/Backtester'))
const Replay = lazy(() => import('./views/Replay'))
const Alpha = lazy(() => import('./views/Alpha'))
const Charts = lazy(() => import('./views/Charts'))

// New TDD routes — all backends implemented
const MarketWatch = lazy(() => import('./views/MarketWatch'))
const Positions = lazy(() => import('./views/Positions'))
const Holdings = lazy(() => import('./views/Holdings'))
const Funds = lazy(() => import('./views/Funds'))
const Reports = lazy(() => import('./views/Reports'))
const Alerts = lazy(() => import('./views/Alerts'))
const Scheduler = lazy(() => import('./views/Scheduler'))
const Logs = lazy(() => import('./views/Logs'))
```

- [ ] **Step 4: Edit the route tree at the bottom of `App.jsx`**

Current (inside `export default function App()`):
```jsx
  return (
    <Router>
      {/* Auth pages — own layout, no header chrome */}
      <Route path="/login" component={Login} />
      <Route path="/register" component={Register} />

      {/* Protected app shell */}
      <Route component={Protected}>
        <Route component={AppShell}>
          <Route path="/" component={Dashboard} />
```

Replace with:
```jsx
  return (
    <Router>
      {/* App shell */}
      <Route component={AppShell}>
        <Route path="/" component={Dashboard} />
```

And the matching closing tags — current:
```jsx
          <Route path="/logs" component={Logs} />
          <Route path="*" component={() => <Navigate href="/" />} />
        </Route>
      </Route>

      {/* Fullscreen — own layout, no Header/footer chrome */}
```

Replace with:
```jsx
        <Route path="/logs" component={Logs} />
        <Route path="*" component={() => <Navigate href="/" />} />
      </Route>

      {/* Fullscreen — own layout, no Header/footer chrome */}
```

(Every route between `path="/"` and `path="/logs"` loses one level of indentation since it's no longer nested inside the removed `Protected` route — a plain re-indent, not a logic change.)

- [ ] **Step 5: Edit `Sidebar.jsx` — remove the `useAuth` import and the user-profile footer**

Current `dashboard/src/components/layout/Sidebar.jsx:1-4`:
```jsx
import { For, Show } from 'solid-js'
import { A } from '@solidjs/router'
import { navigationConfig } from '../../lib/config/routes'
import { useAuth } from '../../stores/useAuth'
```

Replace with:
```jsx
import { For, Show } from 'solid-js'
import { A } from '@solidjs/router'
import { navigationConfig } from '../../lib/config/routes'
```

Current (inside `export default function Sidebar(props)`):
```jsx
export default function Sidebar(props) {
  const collapsed = () => props.collapsed
  const auth = useAuth()
  const user = () => auth.user()

  return (
```

Replace with:
```jsx
export default function Sidebar(props) {
  const collapsed = () => props.collapsed

  return (
```

Current — the entire "User profile footer" block at the end of the component, immediately before the closing `</aside>`:
```jsx
      {/* User profile footer */}
      <div class={`shrink-0 border-t border-white/5 bg-gray-900/90 backdrop-blur-xl ${collapsed() ? 'p-2' : 'p-3'}`}>
        <Show when={!collapsed() && user()} fallback={
          <A href="/login" class="flex items-center justify-center gap-2 text-gray-500 hover:text-gray-300 transition-colors">
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path d="M15 3h4a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2h-4M10 17l5-5-5-5M13 12H3" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
            </svg>
            <Show when={!collapsed()}>
              <span class="text-[10px] font-bold uppercase tracking-widest">Sign In</span>
            </Show>
          </A>
        }>
          <div class="flex items-center gap-3">
            <div class="w-7 h-7 rounded-full bg-primary-500/20 flex items-center justify-center shrink-0">
              <span class="text-[10px] font-black text-primary-400">
                {(user()?.name || 'U').charAt(0).toUpperCase()}
              </span>
            </div>
            <div class="flex-1 min-w-0">
              <p class="text-[11px] font-bold text-gray-200 truncate">{user()?.name}</p>
              <p class="text-[8px] text-gray-500 truncate">{user()?.email}</p>
            </div>
            <button
              onClick={auth.logout}
              class="text-gray-500 hover:text-rose-400 transition-colors shrink-0"
              title="Sign out"
            >
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
              </svg>
            </button>
          </div>
        </Show>
      </div>
    </aside>
  )
}
```

Delete the whole `<div class="shrink-0 border-t ...">...</div>` block, leaving just:
```jsx
    </aside>
  )
}
```

- [ ] **Step 6: Build check**

Run: `cd dashboard && npm run build`
Expected: builds clean, no unresolved-import errors for `./views/Login`, `./views/Register`, `./components/auth/AuthGuard`, `./stores/useAuth`.

- [ ] **Step 7: Manual smoke test**

Run: `cd dashboard && npm run dev`, open the printed localhost URL in a browser.
Expected: app loads straight to the Dashboard view with no redirect to `/login`; sidebar renders with no user-profile footer section at the bottom.

- [ ] **Step 8: Commit**

```bash
git add dashboard/src/App.jsx dashboard/src/components/layout/Sidebar.jsx
git commit -m "dashboard: remove fake login/register flow — access already gated by X-Api-Key"
```

---

### Task 2: Attach `dashboardApiHeaders()` to every dashboard-token-gated `fetch()` call missing it

**Files:**
- Modify: `dashboard/src/components/LedgerJournalPanel.jsx:1,23`
- Modify: `dashboard/src/components/research/ExpectancyReportPanel.jsx:1,79`
- Modify: `dashboard/src/components/ClosedTrades.jsx:1,112`
- Modify: `dashboard/src/views/Settings.jsx:1,24`
- Modify: `dashboard/src/components/LedgerWalletPanel.jsx:1,15`
- Modify: `dashboard/src/stores/useAlpha.js:1,17,26,35`
- Modify: `dashboard/src/components/research/LifecycleBoardPanel.jsx:1,85,101,128`
- Modify: `dashboard/src/components/research/SignalPipelinePanel.jsx:1,75,96,116,144`
- Modify: `dashboard/src/components/settings/FastEntryModePanel.jsx:1,13`
- Modify: `dashboard/src/components/signals/SignalsSidebar.jsx:1,120`
- Modify: `dashboard/src/views/Signals.jsx:1,123`
- Modify: `dashboard/src/stores/useAnalysis.js:1,31,55`
- Modify: `dashboard/src/stores/usePositions.js:1,22,35`
- Modify: `dashboard/src/stores/useDashboard.js:1,102`

**Interfaces:**
- Consumes: `dashboardApiHeaders()` from `dashboard/src/lib/dashboardApi.js` (existing, unchanged — returns `{}` when `VITE_API_DASHBOARD_TOKEN` unset, `{'X-Api-Key': token}` when set).
- Produces: no change to any response handling — only the request's `headers` object gains the `X-Api-Key` entry when applicable. `views/Charts.jsx` and `views/TrailEngine.jsx` already do this correctly; do not touch them.

Each step below is a real, verified current-vs-new pair — no site is guessed. Do them in one pass since they're the same one-line-per-call fix repeated across files; **one commit at the end** covers all of them (this is a single mechanical change, not 14 independent features).

- [ ] **Step 1: `components/LedgerJournalPanel.jsx`**

Add the import (top of file, after the existing `solid-js` import):
```jsx
import { createSignal, onMount, onCleanup, Show, For } from 'solid-js'
import { dashboardApiHeaders } from '../lib/dashboardApi'
```

Current line 23:
```jsx
      const res = await fetch('/api/ledger/journal?per_page=25')
```
Replace with:
```jsx
      const res = await fetch('/api/ledger/journal?per_page=25', { headers: dashboardApiHeaders() })
```

- [ ] **Step 2: `components/research/ExpectancyReportPanel.jsx`**

Add the import:
```jsx
import { createSignal, For, Show } from 'solid-js'
import { dashboardApiHeaders } from '../../lib/dashboardApi'
```

Current line 79:
```jsx
      const res = await fetch(`/api/research/lifecycles/expectancy?${params.toString()}`)
```
Replace with:
```jsx
      const res = await fetch(`/api/research/lifecycles/expectancy?${params.toString()}`, { headers: dashboardApiHeaders() })
```

- [ ] **Step 3: `components/ClosedTrades.jsx`**

Add the import:
```jsx
import { createSignal, createMemo, onMount, createEffect } from 'solid-js'
import { dashboardApiHeaders } from '../lib/dashboardApi'
```

Current line 112:
```jsx
      const res = await fetch(`/api/positions?${buildQuery()}`)
```
Replace with:
```jsx
      const res = await fetch(`/api/positions?${buildQuery()}`, { headers: dashboardApiHeaders() })
```

- [ ] **Step 4: `views/Settings.jsx`**

Add the import (with the other relative imports at top):
```jsx
import { createSignal, onMount, For, Show } from 'solid-js'
import RecursiveFormNode from '../components/settings/RecursiveFormNode'
import NetworkStatusPanel from '../components/settings/NetworkStatusPanel'
import { dashboardApiHeaders } from '../lib/dashboardApi'
```

Current line 24 (`fetchSettings`, the `GET /api/settings` call — this is the `index` action, gated by `authenticate_dashboard_token!`):
```jsx
      const response = await fetch('/api/settings')
```
Replace with:
```jsx
      const response = await fetch('/api/settings', { headers: dashboardApiHeaders() })
```

Leave the `POST /api/settings/bulk` call (line 58) untouched — it's gated by `authenticate_settings!`/`X-Settings-Update-Token`, already sent, unrelated to this fix.

- [ ] **Step 5: `components/LedgerWalletPanel.jsx`**

Add the import:
```jsx
import { createSignal, onMount, onCleanup, Show, For } from 'solid-js'
import AnimatedNumber from './AnimatedNumber'
import { dashboardApiHeaders } from '../lib/dashboardApi'
```

Current line 15:
```jsx
      const res = await fetch('/api/ledger/balance')
```
Replace with:
```jsx
      const res = await fetch('/api/ledger/balance', { headers: dashboardApiHeaders() })
```

- [ ] **Step 6: `stores/useAlpha.js`**

Add the import:
```js
import { createSignal, onMount, onCleanup } from 'solid-js'
import { dashboardApiHeaders } from '../lib/dashboardApi'
```

Current lines 17, 26, 35:
```js
      const res = await fetch('/api/alpha/status')
```
```js
      const res = await fetch('/api/alpha/history')
```
```js
      const res = await fetch('/api/alpha/performance')
```
Replace each with:
```js
      const res = await fetch('/api/alpha/status', { headers: dashboardApiHeaders() })
```
```js
      const res = await fetch('/api/alpha/history', { headers: dashboardApiHeaders() })
```
```js
      const res = await fetch('/api/alpha/performance', { headers: dashboardApiHeaders() })
```

- [ ] **Step 7: `components/research/LifecycleBoardPanel.jsx`**

Add the import:
```jsx
import { createSignal, onMount, For, Show } from 'solid-js'
import { dashboardApiHeaders } from '../../lib/dashboardApi'
```

Current line 85:
```jsx
      const res = await fetch('/api/research/lifecycles?per_page=10')
```
Replace with:
```jsx
      const res = await fetch('/api/research/lifecycles?per_page=10', { headers: dashboardApiHeaders() })
```

Current lines 101-114 (the POST):
```jsx
      const res = await fetch('/api/research/lifecycles/run', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          underlying_symbol: symbol(),
          date: date(),
          spot_price: spotPrice(),
          expiry_flag: expiryFlag(),
          max_distance: maxDistance(),
          entry_time: entryTime()
        })
      })
```
Replace with:
```jsx
      const res = await fetch('/api/research/lifecycles/run', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', ...dashboardApiHeaders() },
        body: JSON.stringify({
          underlying_symbol: symbol(),
          date: date(),
          spot_price: spotPrice(),
          expiry_flag: expiryFlag(),
          max_distance: maxDistance(),
          entry_time: entryTime()
        })
      })
```

Current line 128:
```jsx
      const res = await fetch(`/api/research/lifecycles/${id}`)
```
Replace with:
```jsx
      const res = await fetch(`/api/research/lifecycles/${id}`, { headers: dashboardApiHeaders() })
```

- [ ] **Step 8: `components/research/SignalPipelinePanel.jsx`**

Add the import:
```jsx
import { createSignal, onMount, For, Show } from 'solid-js'
import { dashboardApiHeaders } from '../../lib/dashboardApi'
```

Current line 75:
```jsx
      const res = await fetch(`/api/candles/${symbol()}?interval=5&days=2`)
```
Replace with:
```jsx
      const res = await fetch(`/api/candles/${symbol()}?interval=5&days=2`, { headers: dashboardApiHeaders() })
```

Current line 96:
```jsx
      const res = await fetch('/api/research/signals?per_page=10')
```
Replace with:
```jsx
      const res = await fetch('/api/research/signals?per_page=10', { headers: dashboardApiHeaders() })
```

Current lines 116-127 (the POST — exact body fields don't matter here, only the `headers` line changes):
```jsx
      const res = await fetch('/api/research/signals', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
```
Replace the `headers` line with:
```jsx
      const res = await fetch('/api/research/signals', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', ...dashboardApiHeaders() },
        body: JSON.stringify({
```
(leave the rest of the `body: JSON.stringify({...})` object exactly as-is).

Current line 144:
```jsx
      const res = await fetch(`/api/research/signals/${id}`)
```
Replace with:
```jsx
      const res = await fetch(`/api/research/signals/${id}`, { headers: dashboardApiHeaders() })
```

- [ ] **Step 9: `components/settings/FastEntryModePanel.jsx`**

Add the import:
```jsx
import { createSignal, onMount, Show } from 'solid-js'
import { dashboardApiHeaders } from '../../lib/dashboardApi'
```

Current line 13 (the `GET`, gated by `authenticate_dashboard_token!` per Task 3 of the settings-routes work below):
```jsx
      const response = await fetch('/api/settings/fast_entry_mode')
```
Replace with:
```jsx
      const response = await fetch('/api/settings/fast_entry_mode', { headers: dashboardApiHeaders() })
```

Leave the `PATCH` call (line 43) untouched — gated by `authenticate_settings!`/`X-Settings-Update-Token`, already sent.

- [ ] **Step 10: `components/signals/SignalsSidebar.jsx`**

Add the import:
```jsx
import { createSignal, onMount, For, Show } from 'solid-js'
import { dashboardApiHeaders } from '../../lib/dashboardApi'
```

Current line 120:
```jsx
      const res = await fetch('/api/settings')
```
Replace with:
```jsx
      const res = await fetch('/api/settings', { headers: dashboardApiHeaders() })
```

Leave the `PATCH /api/settings/deep_merge` call (line 169) untouched — gated by `authenticate_settings!`, already sends its own token.

- [ ] **Step 11: `views/Signals.jsx`**

Add the import:
```jsx
import { createSignal, createMemo, onMount } from 'solid-js'
import { dashboardApiHeaders } from '../lib/dashboardApi'
```

Current line 123:
```jsx
      const res = await fetch(`/api/signals?${buildQuery()}`)
```
Replace with:
```jsx
      const res = await fetch(`/api/signals?${buildQuery()}`, { headers: dashboardApiHeaders() })
```

- [ ] **Step 12: `stores/useAnalysis.js`**

Add the import:
```js
import { createSignal, onMount, onCleanup } from 'solid-js'
import { dashboardApiHeaders } from '../lib/dashboardApi'
```

Current line 31 (inside `fetchOne` — the `show` action):
```js
      const res = await fetch(`/api/analysis/${index}`)
```
Replace with:
```js
      const res = await fetch(`/api/analysis/${index}`, { headers: dashboardApiHeaders() })
```

Current line 55 (inside `fetchHistorical` — the `historical` action):
```js
      const res = await fetch(`/api/analysis/${index}/historical?weeks=${weeks}`)
```
Replace with:
```js
      const res = await fetch(`/api/analysis/${index}/historical?weeks=${weeks}`, { headers: dashboardApiHeaders() })
```

Leave the `ai_snapshot` POST (line 89) untouched — `Api::AnalysisController`'s `before_action :authenticate_dashboard_token!, only: %i[show historical]` does not gate that action, so no header is required there today.

- [ ] **Step 13: `stores/usePositions.js`**

Add the import:
```js
import { createSignal, onMount, onCleanup } from 'solid-js'
import toast from 'solid-toast'
import cable from '../cable'
import { dashboardApiHeaders } from '../lib/dashboardApi'
```

Current line 22:
```js
      const res = await fetch('/api/positions')
```
Replace with:
```js
      const res = await fetch('/api/positions', { headers: dashboardApiHeaders() })
```

Current line 35:
```js
      const res = await fetch(`/api/positions/${id}/close`, { method: 'POST' })
```
Replace with:
```js
      const res = await fetch(`/api/positions/${id}/close`, { method: 'POST', headers: dashboardApiHeaders() })
```

- [ ] **Step 14: `stores/useDashboard.js`**

Add the import:
```js
import { dashboardApiHeaders } from '../lib/dashboardApi'
```
(place it with `useDashboard.js`'s existing top-level imports — check the file's current import block with `sed -n '1,5p' dashboard/src/stores/useDashboard.js` first and add alongside it, since this plan doesn't have the file's full import list captured).

Current line 102:
```js
      const res = await fetch('/api/dashboard', { headers: { 'Accept': 'application/json' } })
```
Replace with:
```js
      const res = await fetch('/api/dashboard', { headers: { 'Accept': 'application/json', ...dashboardApiHeaders() } })
```

- [ ] **Step 15: Verify no site was missed and no site was double-handled**

Run: `grep -rn "fetch(" dashboard/src/components dashboard/src/views dashboard/src/stores | grep -v "dashboardApiHeaders\|dashboardApi.js"`
Expected output should only be: `views/Settings.jsx` line 58 (`/settings/bulk`), `components/settings/FastEntryModePanel.jsx` line 43 (`/settings/fast_entry_mode` PATCH), `components/signals/SignalsSidebar.jsx` line 169 (`/settings/deep_merge`), `stores/useAnalysis.js` line 89 (`ai_snapshot`), and `components/settings/NetworkStatusPanel.jsx` line 40 (handled separately in Task 3 below with the settings token, not `dashboardApiHeaders`) — every other `fetch(` call should now show `dashboardApiHeaders()` on the same or an adjacent line. If anything else appears bare, go back and fix it before committing.

- [ ] **Step 16: Build check**

Run: `cd dashboard && npm run build`
Expected: clean build, no import errors.

- [ ] **Step 17: Commit**

```bash
git add dashboard/src/components/LedgerJournalPanel.jsx dashboard/src/components/research/ExpectancyReportPanel.jsx dashboard/src/components/ClosedTrades.jsx dashboard/src/views/Settings.jsx dashboard/src/components/LedgerWalletPanel.jsx dashboard/src/stores/useAlpha.js dashboard/src/components/research/LifecycleBoardPanel.jsx dashboard/src/components/research/SignalPipelinePanel.jsx dashboard/src/components/settings/FastEntryModePanel.jsx dashboard/src/components/signals/SignalsSidebar.jsx dashboard/src/views/Signals.jsx dashboard/src/stores/useAnalysis.js dashboard/src/stores/usePositions.js dashboard/src/stores/useDashboard.js
git commit -m "dashboard: attach X-Api-Key to every raw fetch() hitting a dashboard-token-gated route"
```

---

### Task 3: Wire the three missing settings routes on the Rails side

**Files:**
- Modify: `app/controllers/api/settings_controller.rb`
- Modify: `config/routes.rb:28-30`
- Modify: `spec/requests/api/settings_spec.rb`
- Modify: `dashboard/src/components/settings/NetworkStatusPanel.jsx:1,40`

**Interfaces:**
- Consumes: `Signal::FastEntryMode.status` (returns `{persisted:, effective:, env_override:}`), `Signal::FastEntryMode.reset!`, `AlgoConfig::DocumentStore.apply_deep_merge_patch!(patch, source:, actor:, request_id:, metadata:)`, `Dhan::IpService.fetch_ip_info` (returns `{public_ipv4:, public_ipv6:, registered_ips:}`), `Dhan::IpService.update_ip(ip)` (returns `{success: true, flag:}` or `{success: false, error:}`) — all existing, unchanged.
- Produces: `GET /api/settings/fast_entry_mode`, `PATCH /api/settings/fast_entry_mode`, `POST /api/settings/update_ip`, `PATCH /api/settings/deep_merge` — response shapes matching exactly what the dashboard components (`FastEntryModePanel.jsx`, `NetworkStatusPanel.jsx`, `SignalsSidebar.jsx`) already parse.

- [ ] **Step 1: Add the routes**

Current `config/routes.rb:28-30`:
```ruby
    get    'settings',              to: 'settings#index'
    get    'settings/change_logs',  to: 'settings#change_logs'
    patch  'settings/bulk',         to: 'settings#update_bulk'
```

Replace with:
```ruby
    get    'settings',              to: 'settings#index'
    get    'settings/change_logs',  to: 'settings#change_logs'
    patch  'settings/bulk',         to: 'settings#update_bulk'
    get    'settings/fast_entry_mode',   to: 'settings#fast_entry_mode'
    patch  'settings/fast_entry_mode',   to: 'settings#update_fast_entry_mode'
    post   'settings/update_ip',         to: 'settings#update_ip'
    patch  'settings/deep_merge',        to: 'settings#deep_merge'
```

- [ ] **Step 2: Add the four controller actions**

Current `app/controllers/api/settings_controller.rb:1-17`:
```ruby
# frozen_string_literal: true

module Api
  # Algo config read/update API.
  # When SETTINGS_UPDATE_TOKEN is set, PATCH requires header X-Settings-Update-Token or param token.
  class SettingsController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_dashboard_token!, only: :index
    before_action :authenticate_settings!, only: :update_bulk

    # Top-level keys allowed for algo config overrides (must match config/algo.yml structure)
    PERMITTED_SETTINGS_KEYS = %i[
      paper_trading trading_time_restrictions feature_flags indices trade_limits
      broker_fees risk position_sizing signals chain_analyzer option_chain
      data_freshness watchlist telegram ai
    ].freeze
```

Replace with:
```ruby
# frozen_string_literal: true

module Api
  # Algo config read/update API.
  # When SETTINGS_UPDATE_TOKEN is set, PATCH requires header X-Settings-Update-Token or param token.
  class SettingsController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_dashboard_token!, only: %i[index fast_entry_mode]
    before_action :authenticate_settings!, only: %i[update_bulk update_fast_entry_mode update_ip deep_merge]

    # Top-level keys allowed for algo config overrides (must match config/algo.yml structure)
    PERMITTED_SETTINGS_KEYS = %i[
      paper_trading trading_time_restrictions feature_flags indices trade_limits
      broker_fees risk position_sizing signals chain_analyzer option_chain
      data_freshness watchlist telegram ai
    ].freeze
```

Then, immediately after the existing `update_bulk` action (before `# GET /api/settings/change_logs`), insert:
```ruby
    # GET /api/settings/fast_entry_mode
    def fast_entry_mode
      render json: { success: true, fast_entry_mode: Signal::FastEntryMode.status }
    rescue StandardError => e
      Rails.logger.error("[SettingsController] fast_entry_mode error: #{e.class} - #{e.message}")
      render json: { error: e.message }, status: :internal_server_error
    end

    # PATCH /api/settings/fast_entry_mode
    # Requires a param `enabled` (boolean).
    def update_fast_entry_mode
      enabled = ActiveModel::Type::Boolean.new.cast(params.require(:enabled))

      AlgoConfig::DocumentStore.apply_deep_merge_patch!(
        { signals: { fast_entry_mode: { enabled: enabled } } },
        source: 'api_settings_fast_entry_mode',
        actor: 'api',
        request_id: request.request_id,
        metadata: { remote_ip: request.remote_ip }
      )
      Signal::FastEntryMode.reset!

      render json: { success: true, fast_entry_mode: Signal::FastEntryMode.status }
    rescue ActionController::ParameterMissing => e
      render json: { error: e.message }, status: :bad_request
    rescue StandardError => e
      Rails.logger.error("[SettingsController] update_fast_entry_mode error: #{e.class} - #{e.message}")
      render json: { error: e.message }, status: :internal_server_error
    end

    # POST /api/settings/update_ip
    # Detects the current public IPv4 and attempts to whitelist it on Dhan.
    def update_ip
      info = Dhan::IpService.fetch_ip_info
      ip = info[:public_ipv4]

      if ip.blank? || ip == 'Unknown'
        render json: { success: false, error: 'Could not detect current public IPv4' }
        return
      end

      render json: Dhan::IpService.update_ip(ip)
    rescue StandardError => e
      Rails.logger.error("[SettingsController] update_ip error: #{e.class} - #{e.message}")
      render json: { error: e.message }, status: :internal_server_error
    end

    # PATCH /api/settings/deep_merge
    # Requires a param `patch` (nested hash) — deep-merged into the algo config document.
    def deep_merge
      patch = params.require(:patch).permit!.to_h

      AlgoConfig::DocumentStore.apply_deep_merge_patch!(
        patch,
        source: 'api_settings_deep_merge',
        actor: 'api',
        request_id: request.request_id,
        metadata: { remote_ip: request.remote_ip }
      )

      render json: { success: true, message: 'Settings updated successfully' }
    rescue ActionController::ParameterMissing => e
      render json: { error: e.message }, status: :bad_request
    rescue StandardError => e
      Rails.logger.error("[SettingsController] deep_merge error: #{e.class} - #{e.message}")
      render json: { error: e.message }, status: :internal_server_error
    end

```

- [ ] **Step 3: Add the token header to `NetworkStatusPanel.jsx`'s update-IP call**

`update_ip` is gated by `authenticate_settings!` (same as `fast_entry_mode`'s PATCH and `deep_merge`) — but unlike those two, `NetworkStatusPanel.jsx` currently sends no `X-Settings-Update-Token` at all. This is a real gap: whitelisting a trading IP is exactly the kind of change that secret token exists to protect. Bring it in line with the other two settings-write panels.

Current `dashboard/src/components/settings/NetworkStatusPanel.jsx:1-3`:
```jsx
import { createSignal, createMemo } from 'solid-js'
import { Show } from 'solid-js'
import { useDashboardContext } from '../../context/DashboardContext'
```
No change needed here — the token-prompt pattern below is inlined the same way `FastEntryModePanel.jsx`/`SignalsSidebar.jsx` already do it, no new import required.

Current lines 36-51:
```jsx
  async function triggerIpUpdate() {
    if (!confirm(`This will attempt to whitelist your current IPv4 (${publicIpv4()}) on Dhan. Continue?`)) return
    setUpdating(true)
    try {
      const res = await fetch('/api/settings/update_ip', { method: 'POST', headers: { 'Content-Type': 'application/json' } })
      const data = await res.json()
      if (data.success) {
        alert(`Success! Updated ${data.flag} slot to ${publicIpv4()}`)
        location.reload()
      } else {
        alert('Update failed: ' + data.error)
      }
    } catch {
      alert('Failed to connect to server')
    } finally {
      setUpdating(false)
    }
  }
```

Replace with:
```jsx
  async function triggerIpUpdate() {
    if (!confirm(`This will attempt to whitelist your current IPv4 (${publicIpv4()}) on Dhan. Continue?`)) return

    let token = localStorage.getItem('algo_settings_token')
    if (!token) {
      token = window.prompt('Enter Settings Update Token (from your .env file):')
      if (!token) return
      localStorage.setItem('algo_settings_token', token)
    }

    setUpdating(true)
    try {
      const res = await fetch('/api/settings/update_ip', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-Settings-Update-Token': token }
      })
      const data = await res.json()
      if (res.status === 401) {
        localStorage.removeItem('algo_settings_token')
        alert('Invalid token. Try again.')
        return
      }
      if (data.success) {
        alert(`Success! Updated ${data.flag} slot to ${publicIpv4()}`)
        location.reload()
      } else {
        alert('Update failed: ' + data.error)
      }
    } catch {
      alert('Failed to connect to server')
    } finally {
      setUpdating(false)
    }
  }
```

- [ ] **Step 4: Add request specs to the existing `spec/requests/api/settings_spec.rb`**

The real spec for this controller already exists at `spec/requests/api/settings_spec.rb` (request-spec style, not controller-spec — `spec/controllers/api/settings_controller_spec.rb` is an unrelated, still-`pending` stub generated by scaffolding; leave it alone). Match its established conventions exactly: top-level `get`/`patch`/`post` with string paths, `response.parsed_body`, and the file's existing `after` block (already resets `Setting`/`AlgoConfigChangeLog`/`AlgoConfig` — no changes needed there since the new specs use the same document-store path).

Current full file — for reference, so the insertion point below is unambiguous:
```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::Settings' do
  let(:doc_key) { AlgoConfig::DocumentStore::DOCUMENT_KEY }

  after do
    Setting.where(key: doc_key).delete_all
    AlgoConfigChangeLog.delete_all
    AlgoConfig.reset!
  end

  describe 'GET /api/settings' do
    it 'returns 200 with config' do
      get '/api/settings'
      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json['success']).to be(true)
      expect(json['config']).to be_a(Hash)
    end
  end

  describe 'PATCH /api/settings/bulk' do
    # ... unchanged, see file
  end

  describe 'GET /api/settings/change_logs' do
    # ... unchanged, see file
  end
end
```

Insert three new `describe` blocks immediately before the final `end` that closes `RSpec.describe 'Api::Settings' do`:

```ruby
  describe 'GET/PATCH /api/settings/fast_entry_mode' do
    after { Signal::FastEntryMode.reset! }

    it 'GET returns the current status' do
      get '/api/settings/fast_entry_mode'
      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json['success']).to be(true)
      expect(json['fast_entry_mode']).to include('persisted', 'effective', 'env_override')
    end

    context 'when SETTINGS_UPDATE_TOKEN is set' do
      around do |example|
        prior = ENV.fetch('SETTINGS_UPDATE_TOKEN', nil)
        ENV['SETTINGS_UPDATE_TOKEN'] = 'test-token'
        example.run
      ensure
        if prior
          ENV['SETTINGS_UPDATE_TOKEN'] = prior
        else
          ENV.delete('SETTINGS_UPDATE_TOKEN')
        end
      end

      it 'PATCH rejects requests without the token' do
        patch '/api/settings/fast_entry_mode', params: { enabled: true }
        expect(response).to have_http_status(:unauthorized)
      end

      it 'PATCH toggles the persisted flag with a valid token' do
        patch '/api/settings/fast_entry_mode',
              params: { enabled: true },
              headers: { 'X-Settings-Update-Token' => 'test-token' }
        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json['success']).to be(true)
        expect(json['fast_entry_mode']['persisted']).to be(true)
      end
    end
  end

  describe 'POST /api/settings/update_ip' do
    context 'when SETTINGS_UPDATE_TOKEN is set' do
      around do |example|
        prior = ENV.fetch('SETTINGS_UPDATE_TOKEN', nil)
        ENV['SETTINGS_UPDATE_TOKEN'] = 'test-token'
        example.run
      ensure
        if prior
          ENV['SETTINGS_UPDATE_TOKEN'] = prior
        else
          ENV.delete('SETTINGS_UPDATE_TOKEN')
        end
      end

      it 'rejects requests without the token' do
        post '/api/settings/update_ip'
        expect(response).to have_http_status(:unauthorized)
      end

      it 'returns a graceful error when the current IP cannot be detected' do
        allow(Dhan::IpService).to receive(:fetch_ip_info).and_return(
          { public_ipv4: 'Unknown', public_ipv6: 'Unknown', registered_ips: nil }
        )
        post '/api/settings/update_ip', headers: { 'X-Settings-Update-Token' => 'test-token' }
        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json['success']).to be(false)
      end

      it 'delegates to Dhan::IpService.update_ip with the detected IP' do
        allow(Dhan::IpService).to receive(:fetch_ip_info).and_return(
          { public_ipv4: '1.2.3.4', public_ipv6: 'None', registered_ips: nil }
        )
        allow(Dhan::IpService).to receive(:update_ip).with('1.2.3.4').and_return(
          { success: true, flag: 'PRIMARY' }
        )
        post '/api/settings/update_ip', headers: { 'X-Settings-Update-Token' => 'test-token' }
        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json['success']).to be(true)
        expect(json['flag']).to eq('PRIMARY')
      end
    end
  end

  describe 'PATCH /api/settings/deep_merge' do
    context 'when SETTINGS_UPDATE_TOKEN is set' do
      around do |example|
        prior = ENV.fetch('SETTINGS_UPDATE_TOKEN', nil)
        ENV['SETTINGS_UPDATE_TOKEN'] = 'test-token'
        example.run
      ensure
        if prior
          ENV['SETTINGS_UPDATE_TOKEN'] = prior
        else
          ENV.delete('SETTINGS_UPDATE_TOKEN')
        end
      end

      it 'rejects requests without the token' do
        patch '/api/settings/deep_merge', params: { patch: { signals: { fast_entry_mode: { enabled: true } } } }
        expect(response).to have_http_status(:unauthorized)
      end

      it 'applies the patch with a valid token' do
        patch '/api/settings/deep_merge',
              params: { patch: { signals: { fast_entry_mode: { enabled: true } } } },
              headers: { 'X-Settings-Update-Token' => 'test-token' }
        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json['success']).to be(true)
        doc = JSON.parse(Setting.find_by!(key: doc_key).value)
        expect(doc.dig('signals', 'fast_entry_mode', 'enabled')).to be(true)
      end

      it 'requires the patch param' do
        patch '/api/settings/deep_merge', params: {}, headers: { 'X-Settings-Update-Token' => 'test-token' }
        expect(response).to have_http_status(:bad_request)
      end
    end
  end
```

- [ ] **Step 5: Run the new specs**

Run: `bundle exec rspec spec/requests/api/settings_spec.rb -f documentation`
Expected: all examples pass. If routing errors appear (`No route matches`), double check Step 1's route definitions match the controller action names exactly.

- [ ] **Step 6: Run rubocop**

Run: `bundle exec rubocop app/controllers/api/settings_controller.rb config/routes.rb spec/requests/api/settings_spec.rb`
Expected: no new offenses.

- [ ] **Step 7: Run brakeman**

Run: `bin/brakeman --no-pager`
Expected: no new warnings introduced by the `deep_merge` action's `params.require(:patch).permit!.to_h` (this mirrors the exact pattern `update_bulk` already uses one method above it — Brakeman should treat it identically, but confirm).

- [ ] **Step 8: Full RSpec suite**

Run: `bundle exec rspec`
Expected: green, no regressions elsewhere.

- [ ] **Step 9: Build check on the dashboard**

Run: `cd dashboard && npm run build`
Expected: clean.

- [ ] **Step 10: Manual smoke test against a running dev server**

Run: `./bin/dev`, open the dashboard, go to Settings. Toggle Fast Entry Mode — confirm it flips and persists on reload. In the Signals sidebar, toggle any config switch that uses the inline deep-merge editor — confirm it round-trips. If you have a real Dhan IP-whitelist slot available to modify safely, test "Whitelist Current IP" too; otherwise confirm it at least reaches the backend and returns a real (not 404) response.

- [ ] **Step 11: Commit**

```bash
git add app/controllers/api/settings_controller.rb config/routes.rb spec/requests/api/settings_spec.rb dashboard/src/components/settings/NetworkStatusPanel.jsx
git commit -m "rails+dashboard: wire fast_entry_mode/update_ip/deep_merge settings routes"
```
