# 06 — Platform Services

Variables, deployment pipeline, security scanner, live logs, replay, scheduler, metrics/alerts.

## 1. Variables store

- **D-06.1 — Variables ≠ AlgoConfig.** `AlgoConfig` (DB document + audit, `app/lib/algo_config.rb`)
  remains the platform *trading* config (risk %, trailing tiers, feature flags). The new
  `platform_variables` store holds **strategy inputs** — the Dhan-Cloud-style `{{VARIABLE}}`
  concept. Separate tables, shared layering idiom. They are never merged.

```ruby
create_table :platform_variables do |t|
  t.string  :scope, null: false, default: "global"   # global | strategy
  t.references :strategy                              # null for global
  t.string  :key,   null: false
  t.jsonb   :value
  t.boolean :secret, null: false, default: false
  t.timestamps
end
add_index :platform_variables, [:scope, :strategy_id, :key], unique: true
```

- Resolution at strategy start (frozen into `context.params`):
  **strategy-scoped variable → global variable → manifest default**.
- `secret: true` values are masked in API reads (`"•••"`), logs, and signal metadata; full value
  available only to the runtime. (Advisory hygiene, not a vault — single-user machine. Broker
  credentials stay where they are: ENV + `Dhan::TokenManager`.)
- Changes to variables of a *running* strategy follow hot-reload semantics (applied when flat, or
  on explicit restart) so a run's params are stable and auditable via `strategy_runs.stats.params`.

## 2. Deployment pipeline

`Strategies::DeployPipeline.call(slug)` — mirrors Dhan Cloud's save→scan→deploy flow:

```text
validate            manifest parses; class_name resolvable; params match schema;
   │                Ruby syntax OK (RubyVM::AbstractSyntaxTree.parse)
   ▼
scan                AST security scan (below) → scan_report; blockers fail the deploy
   │
   ▼
snapshot            copy working strategy.rb → releases/v<N>/; compute SHA-256
   │
   ▼
register            insert strategy_versions row (path, checksum, manifest, scan_report);
   │                bump strategies.current_version
   ▼
(re)load            if strategy running → pending-reload (applied when flat, 05);
                    else status: deployed
```

Every step is synchronous and fast (single file); the API endpoint returns the version row +
scan report. Failures leave the previous version untouched — deploy is atomic from the runtime's
perspective.

## 3. Security scanner — D-06.2

AST-walk (Prism/`RubyVM::AbstractSyntaxTree`) over the strategy file. **Advisory guardrail, not a
sandbox** — single-user machine, the threat model is footguns (accidental writes, blocking calls
in the hot path), not adversaries. Honesty note recorded here deliberately.

| Severity | Finding examples | Effect |
| --- | --- | --- |
| `blocker` | `system`/`exec`/`spawn`/`` ` ``/`fork`, `eval`/`instance_eval`/`class_eval` on strings, `File.write`/`FileUtils`, `Net::HTTP`/`Faraday`/`Socket`, `Thread.new`, ActiveRecord writes (`save`/`update`/`destroy`/`create`/`insert`), references to `Orders::`/`Entries::`/`Live::`/`Redis` | Deploy fails |
| `warning` | `Time.now`/`Date.today` (use `context.clock`), `sleep`, rescue-all (`rescue => e` swallowing), `require` of non-allowlisted libs | Deploy proceeds; report shown |

Report stored in `strategy_versions.scan_report` and rendered in the dashboard deploy dialog.

## 4. Live logs — D-06.4

Per-strategy tagged logging, no ELK:

- `Strategies::LogStream` wraps a tagged logger writing `log/strategies/<slug>.log`
  (daily rotation) **and** pushing each line into a Redis ring buffer
  (`LPUSH`+`LTRIM strategy_logs:<slug>`, last ~1000 lines) **and** broadcasting on
  `StrategyLogsChannel` (`strategy_logs_<slug>` stream).
- Runner wraps every plugin invocation so a strategy's own `logger` calls, signal emissions, and
  errors all land in its stream with timestamps.
- `GET /api/strategies/:slug/logs` serves the ring buffer (instant history on page load); the
  channel streams the live tail. The existing global `GET /api/logs` file-tail endpoint stays
  as-is for platform logs.

## 5. Replay engine — D-06.3

**Reuse `app/services/backtest/*` wholesale** — the deliverable is a session model + API, not a new
engine. `Backtest::Engine`, `MarketReplayer`, `OptionTradeSimulator`, `Metrics`, `Report` already
cover tick/candle replay and simulated option fills; today they are only reachable via rake tasks.

New pieces:

- `Replay::SessionRunner` — orchestrates a run: load a `strategy_version` (checksum-verified),
  build contexts from **stored candles** (`Candles::Repository`, Phase-1 dependency; fallback
  `Backtest::ApiLoader` for uncovered ranges), drive the plugin bar-by-bar with a virtual
  `context.clock`, route signals through the existing simulator, collect metrics/report.
- `replay_sessions` table: `(strategy_id, strategy_version_id, kind [replay|backtest],
  date_range, params jsonb, status [queued|running|done|failed], progress, result jsonb,
  created_at)`.
- `Replay::SessionJob` (Solid Queue) — runs async; progress broadcast via cable (D-07.2).

Replay is also the **parity harness** for Phase 2 (compare plugin signals vs frozen
`Signal::Engine` over recorded sessions) — see [04](04_strategy_plugin_system.md) and
[08](08_migration_roadmap.md).

## 6. Scheduler

**No new component.** Solid Queue recurring (`config/recurring.yml`) keeps platform jobs; strategy
cadence is event-driven via the manager ([05](05_runtime_manager.md)). Strategy auto-start/stop at
session boundaries is manager behavior, not cron. If per-strategy time windows are wanted later
(e.g. "only trade 12:00–13:45"), that's a manifest field the manager enforces — still not cron.

## 7. Metrics & alerts

- Reuse the existing Telegram notifier for: deploy events, strategy errors/auto-stops, kill-switch
  interactions.
- Per-strategy performance = SQL over `strategy_signals` ⋈ `position_trackers` / `trade_analytics`
  (win rate, avg R, signal→execution ratio), rolled up into `strategy_runs.stats` at run close and
  served by `GET /api/strategies/:slug` for the dashboard.
- Prometheus/export **deferred** — the existing `Live::SystemStatusCache` + dashboard covers
  single-user observability.
