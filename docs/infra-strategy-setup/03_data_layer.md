# 03 — Data Layer: Durable Candle Persistence

## Why persist candles at all

Today candles live only in Redis (`Live::CandleSeriesCache`, TTL 3600s) or are refetched from
DhanHQ (`app/models/concerns/candle_extension.rb` → `intraday_ohlc`) on every cold start,
restart, or backtest. Persisting finalized bars buys:

- **Replay & backtesting without API round-trips** — `Backtest::DataLoader`/`ApiLoader` currently
  hit the broker per run; a local store is orders of magnitude faster and rate-limit-free.
- **Restart resilience** — after a crash at 11:32, warm indicators from the DB and backfill only
  the crash window via `Live::HistoricalBackfillService` instead of re-downloading the session.
- **Multi-timeframe derivation** — one 1m base series → 3m/5m/15m/1h on read, replacing today's
  per-timeframe broker fetches.
- **Indicator warm-up** — EMA200 needs 200 bars, not another API call.

**What we deliberately do NOT persist: ticks.** No `ticks` table. The tick path
(WebSocket → `TickCache` → forming bar) stays ephemeral. Tick storage only pays off for
order-flow/footprint/ML work, none of which is in scope. (Reaffirms the transcript's analysis.)

## Decisions

- **D-03.1 — Schema.** New `candles` table:

  ```ruby
  create_table :candles do |t|
    t.string   :instrument_key,   null: false   # e.g. "NIFTY", "BANKNIFTY", "SENSEX"
    t.string   :exchange_segment, null: false   # e.g. "IDX_I"
    t.string   :security_id,      null: false
    t.string   :timeframe,        null: false, default: "1m"
    t.datetime :ts,               null: false   # bar open time, IST-normalized, stored UTC
    t.decimal  :open,  precision: 12, scale: 4, null: false
    t.decimal  :high,  precision: 12, scale: 4, null: false
    t.decimal  :low,   precision: 12, scale: 4, null: false
    t.decimal  :close, precision: 12, scale: 4, null: false
    t.bigint   :volume, default: 0
    t.bigint   :oi                               # null for indices
    t.string   :source, null: false, default: "live"  # live | backfill | import
    t.timestamps
  end
  add_index :candles, [:instrument_key, :timeframe, :ts], unique: true
  add_index :candles, [:security_id, :timeframe, :ts]
  ```

  Upserts (`insert_all ... unique_by:`) make live-write vs backfill idempotent — a backfilled bar
  silently reconciles with (or fills in for) a live-built one.

- **D-03.2 — Persist finalized 1m bars only; derive higher timeframes on read.** No double-writing
  3m/5m/15m rows. `Candles::Repository` derives higher TFs via SQL rollup
  (`date_bin`/`time_bucket`-style grouping) or in-process aggregation over the 1m series.
  Materialized rollups are a later optimization if profiling demands (revisit trigger: derived-TF
  query > 50ms for a session's data). Redis remains the source of truth for the *forming* bar;
  Postgres is the durable historical store.

- **D-03.3 — Scope: indices only** (user-confirmed). NIFTY, BANKNIFTY, SENSEX spot 1m bars.
  ~375 bars/day/index → ~280k rows/index/year — trivially small. Option-strike bars stay
  Redis-only (`OptionsBuying::MinuteBarAggregator` unchanged). Revisit trigger: option-premium
  replay fidelity becomes a requirement (would add "traded strikes only" persistence, not full chain).

- **D-03.4 — Async write path.** Bar finalization must not add latency to the tick path
  (CLAUDE.md: never write to the DB from tick handlers). When `Live::CandleSeriesCache` /
  the minute-close path finalizes a bar, it hands the bar to `Candles::Persister` — a small
  batching writer (dedicated thread with a queue, flushing every few seconds or N bars;
  Solid Queue job as the fallback implementation if the thread proves fiddly). Persister failure
  degrades gracefully: log + retry; live trading is unaffected because Redis still holds the series.

- **D-03.5 — Plain table first; partition later.** No partitioning/TimescaleDB at these volumes.
  A nightly retention job (Solid Queue, `config/recurring.yml`) prunes rows older than the
  configured horizon (default: keep 2 years of 1m index bars ≈ 1.7M rows total). Partition only
  if the table passes ~10M rows.

## Components

| Component | Kind | Responsibility |
| --- | --- | --- |
| `Candles::Persister` | NEW service (daemon) | Receives finalized bars, batches, upserts into `candles` |
| `Candles::Repository` | NEW read API | `series(instrument_key, timeframe:, from:, to:)` → `CandleSeries`; 1m from table, higher TFs derived; merges the forming bar from `Live::CandleSeriesCache` when `include_forming: true` |
| `Candle` (AR model) | NEW model | Thin ActiveRecord over the table. Namespaced or renamed carefully: the existing `app/models/candle.rb` PORO keeps its role as the in-memory value object — the AR model lives at `Candles::Record` to avoid a breaking rename |
| `Candles::BackfillJob` | NEW job | Bulk-imports historical 1m bars via existing `Backtest::ApiLoader` / DhanHQ historical API (startup sync, gap fill, initial seed) |
| `Candles::RetentionJob` | NEW job | Nightly prune per D-03.5 |

## Write path (live)

```text
tick → MarketFeedHub → TickCache → CandleSeriesCache.append_tick (forming bar, Redis)
                                        │ minute closes
                                        ├─→ Candles::Persister.enqueue(bar)  ──async──→ candles table
                                        └─→ Core::EventBus.publish(:candle_closed, …)
```

Integration point: the bar-finalization seam in `Live::CandleSeriesCache` (and the session-close
flush). This is a **non-LOCKED** addition — a hook at the point the forming bar rolls over, not a
change to feed/caching semantics.

## Backfill & recovery

Reuse, don't rebuild:

- **Startup / gap recovery** — `Live::HistoricalBackfillService` already detects gaps and fetches
  DhanHQ intraday candles (rate-limited, circuit-broken). Extend its sink: in addition to feeding
  the Redis series, emit recovered bars to `Candles::Persister` with `source: "backfill"`.
- **Bulk seed / backtest prep** — `Candles::BackfillJob` wraps the fetch logic already in
  `Backtest::ApiLoader` and `candle_extension.rb#fetch_fresh_candles`, writing to the table.
- **On-demand fallback** — `Candles::Repository` falls back to the broker fetch when the table
  lacks the requested range (and persists what it fetched), so callers never care about coverage.

## Migration of readers (gradual)

Hot-path readers move from `instrument.candle_series` (broker fetch + in-memory cache) to
`Candles::Repository` opportunistically — first the new strategy runtime (which only ever uses the
repository), then backtest loaders, then remaining callers. `candle_extension.rb` stays as the
broker-fetch primitive the repository uses internally; it is not deleted.

## Verification (Phase 1 gate, see [08](08_migration_roadmap.md))

1. Run a full market session with the persister enabled; compare the day's stored 1m bars against
   a fresh DhanHQ `intraday_ohlc` pull for the same day — OHLCV must match bar-for-bar.
2. Kill the daemon mid-session, restart: gap detected, backfilled rows appear with
   `source: "backfill"`, no duplicate `(instrument_key, timeframe, ts)` rows.
3. Derived 5m/15m series from the repository matches DhanHQ's native 5m/15m fetch for the same window.
4. Tick-path latency unchanged (persister is async; spot-check PnL flush cadence).
