# 07 — API & Frontend Contract

REST + ActionCable surface for the platform features, and the wiring plan for the dashboard views
that already exist without a backend. Dashboard is a **SolidJS** SPA (`dashboard/` — Vite,
`solid-js` + `@solidjs/router`, Tailwind v4, axios client in `dashboard/src/lib/api/`,
ActionCable via `@rails/actioncable`).

All endpoints live under the existing `namespace :api` and follow the existing auth pattern
(single-user). Rswag specs document each endpoint (regenerate `swagger/v1/swagger.yaml`).

## REST resources

### Strategies

| Verb & path | Purpose | Notes |
| --- | --- | --- |
| `GET /api/strategies` | List: slug, name, status, current version, last heartbeat, today's signal/PnL stats | Backs `Strategies.jsx` list |
| `POST /api/strategies` | Create from template: `{slug, name, template}` → scaffolds workspace + `draft` row | |
| `GET /api/strategies/:slug` | Detail: manifest, params schema, resolved variables (secrets masked), run history, performance stats | |
| `POST /api/strategies/:slug/deploy` | Run deploy pipeline; returns version row + `scan_report` | 422 with report on blocker findings |
| `POST /api/strategies/:slug/start` | Set `desired_status: running` (+ Redis nudge; daemon reconciles, D-02.4) | 202 Accepted; final state via channel |
| `POST /api/strategies/:slug/stop` | Set `desired_status: stopped` | 202 |
| `POST /api/strategies/:slug/restart` | Stop + start | 202 |
| `GET /api/strategies/:slug/versions` | Version list: number, checksum, deployed_at, scan summary | |
| `GET /api/strategies/:slug/signals` | Paginated `strategy_signals` (filter: date, action, outcome) | |
| `GET /api/strategies/:slug/logs` | Redis ring buffer (last ~1000 lines) | Live tail via channel |
| `GET /api/strategies/:slug/variables` | Strategy-scoped variables (secrets masked) | |
| `PUT /api/strategies/:slug/variables` | Upsert variables; notes hot-reload semantics in response | |

### Variables (global)

| Verb & path | Purpose |
| --- | --- |
| `GET /api/variables` | Global scope list (secrets masked) |
| `PUT /api/variables` | Upsert global variables |

### Replay & backtest — D-07.2 (async jobs, not blocking HTTP)

| Verb & path | Purpose |
| --- | --- |
| `POST /api/replays` | `{strategy_slug, version, from, to, kind: "replay"\|"backtest", params}` → creates `replay_sessions` row, enqueues `Replay::SessionJob`, returns `{id, status: "queued"}` (202) |
| `GET /api/replays` | Session list |
| `GET /api/replays/:id` | Status, progress, result (metrics + trade list + equity curve from `Backtest::Report`) |
| `DELETE /api/replays/:id` | Cancel a queued/running session |

`POST /api/backtests` is an alias route to the same controller with `kind: "backtest"` (kept so
`Backtester.jsx` and `Replay.jsx` read naturally); one implementation.

### Candles (extend existing)

`GET /api/candles/:index_key` already exists; add `?timeframe=` and `?from=/?to=` params served
from `Candles::Repository` once Phase 1 lands (broker-fetch fallback preserved).

## ActionCable channels (additions)

| Channel | Stream | Payloads | Broadcaster |
| --- | --- | --- | --- |
| `StrategyStatusChannel` | `strategy_status` | `{slug, status, version, heartbeat_at, error_count, last_signal}` on every transition + periodic heartbeat | `Strategies::Manager` control loop |
| `StrategyLogsChannel` | `strategy_logs_<slug>` | `{ts, level, line}` | `Strategies::LogStream` |
| `ReplayProgressChannel` | `replay_<id>` | `{progress, status, partial_metrics}` | `Replay::SessionJob` |

Existing channels (dashboard, positions, funds, holdings, option_chain, alerts) unchanged.

## Frontend wiring map

Current state: `Strategies.jsx` renders read-only config from `DashboardContext`;
`Backtester.jsx` / `Replay.jsx` are client-side only. All three get real backends:

| View | Wiring |
| --- | --- |
| `Strategies.jsx` | Rebuild around `GET /api/strategies` + `StrategyStatusChannel`. Cards: status badge, version, heartbeat, start/stop/restart/deploy buttons (202 → optimistic + channel confirm), deploy dialog rendering `scan_report`, params/variables editor (`PUT variables`), signals table, log tail pane (`StrategyLogsChannel`) |
| `Backtester.jsx` | Form → `POST /api/backtests`; subscribe `ReplayProgressChannel`; render `Backtest::Report` result (metrics, trades, equity curve — `lightweight-charts` already in deps) |
| `Replay.jsx` | Same session API with `kind: "replay"`; bar-by-bar playback reads the session's candle range from `GET /api/candles/:index_key?timeframe=&from=&to=` + the session's signal/trade markers |
| `Logs.jsx` | Keep global file-tail; add per-strategy selector backed by ring buffer + channel |
| `Scheduler.jsx` | Unchanged (Solid Queue tasks); strategy session-window display can link to strategy detail |

- **D-07.1** — Backend conforms to sane frontend expectations; where the existing views' shapes
  are placeholder (they mostly are — context-driven display), the API shapes above are canonical
  and the views adapt. Each endpoint's JSON shape is finalized in its Rswag spec, which is the
  binding contract.

## Routes sketch (`config/routes.rb`)

```ruby
namespace :api do
  resources :strategies, param: :slug, only: %i[index show create] do
    member do
      post :deploy, :start, :stop, :restart
      get  :versions, :signals, :logs
      get  :variables
      put  :variables, action: :update_variables
    end
  end
  resource  :variables, only: %i[show update]           # global scope
  resources :replays, only: %i[index show create destroy]
  post "backtests", to: "replays#create", defaults: { kind: "backtest" }
end
```
