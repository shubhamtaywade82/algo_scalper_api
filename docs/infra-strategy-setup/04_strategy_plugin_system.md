# 04 — Strategy Plugin System

The centerpiece of the upgrade. Supersedes `docs/NEW_ANALYTICS_AND_STRATEGY_LAYER.md` and the dead
`app/services/strategy/` scaffold (deleted per D-01.1). New namespace: **`Strategies::`** (plural),
avoiding collision with the legacy `Strategy::` constants during migration.

## Plugin contract — `Strategies::Base`

```ruby
# app/services/strategies/base.rb
module Strategies
  class Base
    # -- declarations (read from manifest, exposed for introspection) --
    class << self
      def timeframes  = %w[1m]          # candle events this strategy wakes on
      def instruments = %w[NIFTY]       # instrument_keys it trades
      def params_schema = {}            # JSON-schema-ish param declaration
    end

    def initialize(params:) = @params = params.freeze

    # -- required --
    # context : Strategies::StrategyContext (read-only snapshot)
    # returns : Signals::BuyCall | Signals::BuyPut | Signals::Exit | Signals::Hold
    def call(context)
      raise NotImplementedError
    end

    # -- optional lifecycle hooks (no-ops by default) --
    def on_start(context) = nil     # manager started this strategy
    def on_stop(context)  = nil     # graceful stop / market close
    def on_position_opened(context) = nil
    def on_position_closed(context) = nil
  end
end
```

Rules:

- `#call` is invoked once per subscribed candle-close event, with a fresh immutable context.
- Plugins are **pure decision functions plus optional private state** (e.g. an opening-range
  memo). Any state a plugin keeps must be reconstructible from context — the manager may restart
  it at any time.
- Exceptions propagate to the manager (crash policy → [05](05_runtime_manager.md)); plugins do
  not rescue-and-continue silently.

## Signal value objects

```ruby
# app/services/signals/  (immutable Data/Struct classes)
Signals::BuyCall.new(confidence:, reason:, metadata: {})
Signals::BuyPut.new(confidence:, reason:, metadata: {})
Signals::Exit.new(reason:, metadata: {})     # advisory — routed through Live::ExitEngine
Signals::Hold.new(reason: nil)
```

- `confidence` ∈ 0.0..1.0; `reason` is a human-readable one-liner (surfaced in logs/dashboard);
  `metadata` carries diagnostics (indicator values at decision time) persisted with the signal.
- **Plugins never place orders, never touch gateways, never call `Entries::EntryGuard`.** The
  manager routes actionable signals into the unchanged platform path (D-02.2, D-02.3).

## `StrategyContext` — the read-only facade

Built per invocation by `Strategies::ContextBuilder`; harvests the shape of the dead
`Domain::TradingContext` and the transcript's design.

| Accessor | Backed by | Notes |
| --- | --- | --- |
| `context.candles(tf = "1m")` | `Candles::Repository` (+ forming bar from `Live::CandleSeriesCache`) | Returns `CandleSeries` |
| `context.indicators` | `Indicators::*` over the series | e.g. `.supertrend`, `.adx`, `.rsi`, `.ema(20)` — memoized per snapshot |
| `context.structure` | `Smc::*` / `MarketState::MarketStateEngine` reads | trend, BOS/CHOCH, zones, bias |
| `context.option_chain` | `Options::ChainAnalyzer` / chain snapshot | ATM, strikes, broker greeks, IV rank |
| `context.position` | `PositionTracker` / `Positions::ActiveCacheService` snapshot | `open?`, entry, qty, pnl |
| `context.risk` | `Risk::CircuitBreaker`, daily-limit reads | `can_trade?` (advisory — EntryGuard re-checks authoritatively) |
| `context.session` | `TradingSession::Service` | `market_open?`, `seconds_until_close`, expiry info |
| `context.clock` | injected time source | replay substitutes a virtual clock — plugins must never call `Time.now` directly |
| `context.params` | resolved params (variables → manifest defaults) | frozen hash |
| `context.config` | `AlgoConfig` read-only slice | trading config, not strategy params |

**Forbidden from plugins** (enforced by not exposing it, plus the scanner in
[06](06_platform_services.md)): ActiveRecord writes, Redis clients, `Orders::*`, `Entries::*`,
`Live::*` services, HTTP clients, `Time.now`/`Date.today` (use `context.clock`), threads,
`system`/`exec`/`eval`, filesystem writes.

Thread-safety contract (D-05.2): each invocation gets its own immutable snapshot; plugins never
share context objects across invocations.

## Workspace layout — D-04.1

```text
strategies/                          # repo root, git-tracked
  supertrend_v1/
    strategy.rb                      # class SupertrendV1 < Strategies::Base
    manifest.yml
    README.md                        # optional
    releases/
      v1/strategy.rb                 # immutable snapshot created by deploy pipeline
      v2/strategy.rb
  _templates/
    basic/strategy.rb.tt             # generator templates (ORB, EMA-cross, blank)
    basic/manifest.yml.tt
```

`manifest.yml`:

```yaml
name: Supertrend V1
slug: supertrend_v1
class_name: SupertrendV1
timeframes: ["1m"]
instruments: ["NIFTY", "BANKNIFTY", "SENSEX"]
params:
  supertrend_period:     { type: integer, default: 10 }
  supertrend_multiplier: { type: float,   default: 2.0 }
  adx_min:               { type: float,   default: 20.0 }
```

- Working copy (`strategy.rb`) is what you edit; `releases/vN/` snapshots are what runs. The DB
  stores the release path + SHA-256; the loader verifies the checksum before load (tamper/drift
  detection). **Never eval from DB** (D-00.2).
- Git remains the real VCS; `releases/` gives the platform deterministic rollback independent of
  git state.

## Registry schema — D-04.2

```ruby
create_table :strategies do |t|
  t.string  :slug,   null: false, index: { unique: true }
  t.string  :name,   null: false
  t.string  :status, null: false, default: "draft"
  # draft | deployed | running | stopped | errored | archived
  t.string  :desired_status                      # API → daemon reconciliation (D-02.4)
  t.references :current_version
  t.timestamps
end

create_table :strategy_versions do |t|
  t.references :strategy, null: false
  t.integer :version,     null: false            # unique per strategy
  t.string  :file_path,   null: false            # strategies/<slug>/releases/v<N>/strategy.rb
  t.string  :checksum,    null: false            # SHA-256 of the release file
  t.jsonb   :manifest,    null: false, default: {}
  t.jsonb   :scan_report, default: {}            # security scanner output (06)
  t.datetime :deployed_at
  t.timestamps
end

create_table :strategy_runs do |t|
  t.references :strategy, :strategy_version
  t.datetime :started_at, :stopped_at
  t.string   :stop_reason                        # manual | crash | kill_switch | market_close | error_limit
  t.jsonb    :stats, default: {}                 # invocations, signals, errors, last_heartbeat
  t.timestamps
end

create_table :strategy_signals do |t|
  t.references :strategy, :strategy_version, :strategy_run
  t.string   :instrument_key, null: false
  t.string   :action,   null: false              # buy_call | buy_put | exit | hold
  t.float    :confidence
  t.string   :reason
  t.jsonb    :metadata, default: {}
  t.string   :outcome                            # executed | blocked_by_guard | ignored_hold
  t.references :position_tracker                 # when executed
  t.datetime :emitted_at, null: false
  t.timestamps
end
```

`strategy_signals` is a dedicated table (D-02.5) — queryable, joinable to versions/runs and
`position_trackers`, feeding per-strategy performance stats. `Hold` signals are sampled
(persist state changes + periodic heartbeat holds, not every 1m hold) to keep volume sane.

## Loading & reloading — D-04.3

- Loader reads `strategy_versions.file_path`, verifies SHA-256, then `load`s the file inside the
  `Strategies::Runtime` namespace (explicit `load` with an anonymous-module wrapper or
  const-tracking — **not** Zeitwerk-managed, so redeploys can swap the constant).
- Reload = stop instance → remove constant → load new release → instantiate → start. Hot-reload is
  **deferred until the strategy is flat** (no open position attributed to it) — see risk register
  in [09](09_risks_and_change_policy.md).
- Load failures (syntax error, checksum mismatch, missing class) mark the strategy `errored` and
  alert; they never take down the manager or other strategies.

## Plugin #1 — extracting `Signal::Engine` → `supertrend_v1` (D-04.4)

The migration's proof of concept and parity anchor:

| Today (`Signal::Engine.run_for`) | Destination |
| --- | --- |
| Supertrend 1m flip detection, chop gate (ADX), trend/quality checks | `strategies/supertrend_v1/strategy.rb` — the plugin's `#call` |
| Index iteration, 30s cadence (`Signal::Scheduler`) | `Strategies::Manager` event-driven dispatch |
| Candle fetch (`instrument.candle_series`) | `context.candles` via `Candles::Repository` |
| DTE guard, session checks | stay platform-side (context/session + EntryGuard) |
| `Options::ChainAnalyzer` strike pick, `TradingSignal.create_from_analysis`, `Entries::EntryGuard.try_enter` | stay platform-side, invoked by the manager on actionable signals |

Migration mechanics (Phase 2, [08](08_migration_roadmap.md)): extract the alpha logic; run the
plugin in **shadow mode** alongside the frozen `Signal::Engine` (plugin emits signals persisted
with `outcome: "shadow"`, engine keeps trading); gate = **replay parity** — identical
buy/sell/hold decisions on ≥3 recorded sessions plus one clean live paper session. Then the plugin
takes over and `Signal::Engine`/`Signal::Scheduler` are deleted (user-confirmed D-01.3).

## Templates

`rails g strategy <slug>` (or `rake strategies:new[<slug>,<template>]`) scaffolds from
`strategies/_templates/`: manifest, strategy class with commented context examples, README.
Initial template set: `blank`, `ema_cross`, `orb` — enough to demonstrate the contract without
committing to unproven alpha.
