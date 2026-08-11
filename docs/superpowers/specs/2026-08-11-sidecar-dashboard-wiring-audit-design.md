# Rails / node-sidecar / dashboard wiring audit

Date: 2026-08-11

## Context

Triggered by a WebSocket `429` on the node-sidecar's market feed
(`node-sidecar/src/executor.ts`, `analytics.ts`). Chasing that root cause
turned into a full audit of every integration point between the three
processes that make up this app: Rails (`web`+`trading`), the node-sidecar
(`node-sidecar/`), and the SolidJS dashboard (`dashboard/`, Vite — not
Next.js as CLAUDE.md currently claims).

Three parallel read-only audits (Redis pub/sub, ActionCable, REST routes,
env vars, WS usage) turned up two genuinely broken things and a pile of
dead code / stale docs. The user's goal: get this app working as designed
end-to-end for paper trading against real market data — fix what's broken,
remove what's dead, don't add anything speculative.

## Findings

### 1. The 429, and what it's actually colliding with

Both Rails and the sidecar independently open their own Dhan WebSocket
connections with the same `DHAN_CLIENT_ID`/token:

- Rails: `Live::MarketFeedHub` (market ticks) + `Live::OrderUpdateHub`
  (order updates) — both singletons, both the canonical feeds per
  CLAUDE.md.
- Sidecar: `client.ws.market` (used in both `executor.ts` for
  `PositionMonitor.onTick` and separately in `analytics.ts` for an
  ad-hoc Greeks writer) + `client.ws.orders` (used in `executor.ts` for
  `OrderTracker`, feeding `LiveExecutionEngine.placeOrder`'s fill-wait).

On every reconnect (token rotation broadcasts `dhan:auth:rotated`, which
`node-sidecar/src/auth.ts` handles by immediately calling
`client.ws.disconnect()` + `client.ws.connect()`, racing Rails' own
`restart_websocket!` at the same moment) these collide and Dhan returns
`429` on the handshake.

### 2. The sidecar's execution path is fully built but never invoked

`Dhan::SidecarPublisher.publish_intent` — the only way anything gets
published to `dhan:execution:intents`, the channel `node-sidecar/src/
executor.ts` subscribes to for order execution — **has zero callers
anywhere in `app/` or `lib/`.** `Entries::EntryGuard#try_enter` places all
orders directly through `Orders::GatewayLive`/`GatewayPaper`, never
through the sidecar. So the sidecar's multi-leg spread skills
(`bull_call_spread`, `iron_condor`, etc. via `@shubhamtaywade82/
dhanhq-ts`) never run today.

Confirmed with the user this is genuinely dormant/future work, not a
regression — so its two connected WebSockets are serving no live purpose
right now, and are actively causing the collision in Finding 1. The intent
was also found to be internally broken anyway (see Appendix), but that's
moot while it's unreachable.

### 3. Dashboard: fake auth, silent auth-header gaps, and three missing routes

- **Login/Register don't work against Rails.** No `/api/auth/*` route
  exists anywhere in `config/routes.rb`. `stores/useAuth.js` POSTs there,
  gets a 404, and silently falls back to a fake `local_token` session
  (`useAuth.js:62-66,86-90`) that's never sent as a header anywhere. The
  login UI is decorative — the app is already gated for real by
  `X-Api-Key` / `API_DASHBOARD_TOKEN`.
- **~30 call sites use raw `fetch()` instead of the `apiClient`/
  `dashboardApi` wrapper**, so they never send `X-Api-Key`. Invisible
  today because dev has no `API_DASHBOARD_TOKEN` set; breaks the moment
  production sets one.
- **Three settings features are wired client-side but have no
  server route**: `FastEntryModePanel.jsx` (`GET`/`PATCH /api/settings/
  fast_entry_mode`), `NetworkStatusPanel.jsx` (`POST /api/settings/
  update_ip`), `SignalsSidebar.jsx`'s inline config editor (`PATCH /api/
  settings/deep_merge`). Not aspirational — the backend logic they need
  already exists (`Signal::FastEntryMode`, `Dhan::IpService.update_ip`,
  `AlgoConfig::DocumentStore.apply_deep_merge_patch!`), it's just never
  exposed through `Api::SettingsController`.

### 4. Dead code and stale docs

- A complete, unreferenced Vue 3 app sits inside `dashboard/src` next to
  the live SolidJS app: `main.js`, `App.vue`, `router/index.js`,
  `composables/*.js`, every `*.vue` file. `index.html` only loads
  `main.jsx`; `vite.config.js` only registers the Solid plugin. `vue`/
  `vue-router` are dead entries in `package.json`. Leftover from an
  abandoned migration.
- `dashboard/src/lib/smc/paperTrader.js` and its siblings
  (`setupScanner.js`, `ictEngine.js`, `smcEngine.js`, `canvasOverlay.js`)
  are unreferenced from anywhere reachable.
- Two Rails ActionCable broadcasts have no matching channel class and no
  subscriber: `paper_positions` and `positions_#{tracker.user_id}`
  (`app/services/dhan/sidecar_listener.rb:55,59`) — redundant with the
  `PositionTracker::Broadcastable` concern, which already broadcasts on
  the same `update!` calls via the real `positions`/`dashboard` channels.
  `PositionTracker` doesn't expose `user_id` (single-tenant app); that
  branch is defensive code that can't fire.
- CLAUDE.md is wrong on three counts: claims Solid Cable (actual
  `config/cable.yml` adapter is `redis`), claims Next.js dashboard
  (it's SolidJS+Vite), and documents only 4 `Procfile.dev` processes
  (there are 5 — `sidecar` is undocumented entirely, including all its
  Redis channel wiring).

## Goals

1. **Kill the WebSocket collision at the root.** Stop the sidecar from
   opening any Dhan WebSocket connection while its execution path is
   unreachable. Keep the Redis intent/fill/exit channel plumbing in place
   (dormant, harmless) so a future "wire up spreads" project has
   something to build on, but it must not touch `client.ws` at all until
   that happens.
2. **Make the dashboard's real auth path (`X-Api-Key`) the only one.**
   Remove the fake login/register flow entirely. Every REST call must
   consistently send the API key.
3. **Close the three settings feature gaps** by exposing existing backend
   logic through routes, not by building new logic.
4. **Delete dead code, fix the docs** so the next person (human or AI)
   reading CLAUDE.md gets the true shape of the system, including the
   node-sidecar's dormant status.

Explicitly out of scope: wiring the sidecar's spread-execution path end to
end (fixing its exit-payload field mismatch, adding the
`EntryGuard`→`SidecarPublisher` call, deciding exit authority for real).
That's a real feature project for later, not part of "make this work as
designed for paper trading today."

## Design

### Sub-project 1 — Sidecar dormancy fix

- `node-sidecar/src/analytics.ts`: delete. Its only output
  (`dhan:market:greeks:*`) has no reader anywhere in Rails or the
  dashboard, and its only input is the market WS this project is
  removing.
- `node-sidecar/src/executor.ts`: remove the `client.ws` block entirely
  (both `orders` and `market` listeners). `OrderTracker`/`PositionMonitor`
  wiring goes with it — both exist solely to support the dormant
  `LiveExecutionEngine`/paper engine fill-wait and exit-trigger, which
  have no caller. The Redis `intentSubscriber` subscription to
  `dhan:execution:intents` stays exactly as-is — that's the dormant
  plumbing worth preserving.
- `node-sidecar/src/auth.ts`: remove the `client.ws.disconnect()`/
  `connect()` calls from the `dhan:auth:rotated` handler — there's no
  longer a WebSocket to reconnect. Redis token read/cache stays (still
  used by the dormant execution path if it's ever invoked, and by nothing
  else right now — keep it since it's the one piece of auth plumbing the
  whole sidecar depends on structurally).
- `app/services/dhan/sidecar_listener.rb`: remove the `paper_positions`
  and `positions_#{tracker.user_id}` broadcasts (dead channels, no
  class, redundant with `Broadcastable`). Leave `process_fill`/
  `process_exit`'s model updates as-is.
- Verify: boot `bin/dev`, confirm sidecar log shows no WS
  connect/reconnect activity, confirm zero `429` in the sidecar log over
  a market-hours run, confirm `dhan:execution:intents` subscription log
  line still appears at boot.

### Sub-project 2 — Dashboard correctness

- Remove `dashboard/src/views/Login.jsx`, `Register.jsx`,
  `components/auth/AuthGuard.jsx`, `stores/useAuth.js`, and the
  `/login`/`/register` routes + `Protected`/`AuthGuard` wrapper in
  `App.jsx` — collapse straight to `AppShell`. Drop the
  `algo_scalper_token` localStorage key.
- Audit every raw `fetch('/api/...')` call site found in the audit
  (~30, listed by file in the audit transcript) and switch each to the
  existing `apiClient` (axios) or `dashboardApi` helper — whichever
  matches the pattern already used by neighboring calls in that file —
  so `X-Api-Key` is always attached. No new wrapper; reuse what's there.
- `Api::SettingsController`: add three actions following the existing
  `authenticate_settings!` pattern (already checks
  `X-Settings-Update-Token`, which is exactly what the dashboard already
  sends):
  - `GET`/`PATCH /api/settings/fast_entry_mode` → thin wrapper around
    `Signal::FastEntryMode` (read `.enabled?`, write via whatever it
    already exposes for toggling — check the service's public API before
    assuming a setter shape).
  - `POST /api/settings/update_ip` → wrap `Dhan::IpService.update_ip`,
    matching the response shape `NetworkStatusPanel.jsx` already expects
    (`{success, flag}` on success).
  - `PATCH /api/settings/deep_merge` → wrap
    `AlgoConfig::DocumentStore.apply_deep_merge_patch!`, matching what
    `SignalsSidebar.jsx`'s inline editor sends (a `patch` param — verify
    exact param name expected against what's sent).
  - Add matching routes in `config/routes.rb` next to the existing
    `settings` routes.
- Verify: `npm run build` (vite) compiles clean, manual click-through in
  a browser — app loads straight to the dashboard with no login gate,
  Settings → Fast Entry Mode toggle round-trips, Network Status → Update
  IP round-trips (or fails gracefully with a real IP, not a 404), the
  inline settings editor in the signals sidebar round-trips.

### Sub-project 3 — Cleanup + docs

- Delete `dashboard/src/main.js`, `App.vue`, `router/index.js`,
  `composables/*.js`, every `*.vue` file, `dashboard/src/lib/smc/
  paperTrader.js` + its four siblings — re-`grep` for zero references
  immediately before each delete, since files may have shifted since the
  audit.
- Remove `vue`, `vue-router` from `dashboard/package.json`, run
  `npm install` to update the lockfile.
- Update `CLAUDE.md`: `cable.yml` uses the `redis` adapter, not Solid
  Cable; dashboard is SolidJS+Vite, not Next.js; add the missing
  `sidecar` row to the process table; add a short section documenting
  the Redis channels between Rails and the sidecar
  (`dhan:execution:intents`/`fills`/`exits`, `dhan:auth:rotated`) and
  note explicitly that the sidecar's execution path is currently
  dormant (built, not invoked).
- Verify: `bundle exec rspec`, `bundle exec rubocop`, `bin/brakeman
  --no-pager` all clean on the Rails changes; `npm run build` clean on
  the sidecar (`tsc`) and dashboard (`vite build`).

## Error handling

No new error paths introduced — this project is subtractive (remove dead
WS connections, remove fake auth) or additive-but-thin (three controller
actions delegating to already-tested services). The three new controller
actions follow the existing `SettingsController` pattern: rescue
`StandardError`, log, return a JSON error with an appropriate status —
same as `index`/`update_bulk`/`change_logs` already do.

## Testing

- Rails: existing spec suite must stay green; add request specs for the
  three new settings actions (happy path + missing/wrong
  `X-Settings-Update-Token`) following the existing `settings_controller`
  spec's structure if one exists, otherwise a new one mirroring
  `update_bulk`'s spec shape.
- Sidecar: `npm test` (existing `__tests__/sidecar.test.ts`) must stay
  green; no new tests needed since this is deletion, not new logic.
- Dashboard: no existing test suite to preserve (none found in the
  audit) — verification is `npm run build` + manual click-through as
  above.
- End-to-end: after all three sub-projects, run `./bin/dev` for a full
  market-hours session in paper mode, confirm no `429`s, confirm the
  dashboard shows live positions/PnL updates via ActionCable, confirm
  Settings panels work.

## Appendix — sidecar exit-payload bug (documented, not fixed here)

For whoever picks up "wire up spreads for real" later: `PositionMonitor`'s
actual `"exit"` event shape is `{position, reason, price, pnl,
triggeredAt}` (per the installed `@shubhamtaywade82/dhanhq-ts@0.4.1`).
`node-sidecar/src/executor.ts`'s exit handler reads
`signal.positionId`/`signal.correlationId`/`signal.exitPrice`, none of
which exist — `JSON.stringify` drops the `undefined`s, so Rails receives
a payload with no id at all and `Dhan::SidecarListener#process_exit`
silently no-ops (both `correlation_id` and `position_id` blank). Even
fixed, `monitor.track(...)` never attaches an id to the tracked position
in the first place, so there's nothing for the exit event to echo back —
the fix needs an id threaded through both `.track()` and the exit reader.
Also: no instrument is ever subscribed on the market WS regardless of
connection state, so `PositionMonitor.onTick` gets zero ticks even before
any of the above. And per Finding 1's design decision, this whole
question is moot until something actually calls `SidecarPublisher.
publish_intent` — decide exit authority (Rails-only vs sidecar's own
trigger) at that point, not before.
