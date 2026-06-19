# On-Demand Historical OHLC Backfill — Implementation Plan

## Problem

The current `algo_scalper_api` has two disjoint data paths:

1. **Live tick path**: `MarketFeedHub` (WebSocket) → `MinuteBarAggregator` → `StateStore: ticks:<security_id>:<bucket>` (Redis sorted set). Used by `BreakoutEvaluator`.
2. **Historical candle path**: `Instrument#intraday_ohlc` → DhanHQ REST → `CandleSeries`. Used by `IndexTechnicalAnalyzer` and backtesting.

The historical path is only used at boot or in backtest. The live tick path has **no gap recovery**:
- If the WebSocket drops and reconnects, missing minutes are never backfilled.
- When a new option strike is added to radar mid-session, it has zero tick history.
- Indicators (Supertrend, ADX, RSI) that depend on `CandleSeries` can’t consume live tick data.

## Goal

Create a lightweight, on-demand backfill service that:
1. Detects when historical gaps exist (reconnect, new instrument, explicit request).
2. Fetches missing OHLC from DhanHQ `POST /v2/charts/intraday`.
3. Hydrates the relevant caches (Redis tick store + CandleSeries cache) so downstream consumers see a continuous series.
4. Respects DhanHQ rate limits and static-IP requirements.

## Scope

### In-Scope
- `Live::HistoricalBackfillService` — fetch, normalize, store
- Integration with `MarketFeedHub#resubscribe_active_positions_after_reconnect`
- Integration with `OptionsBuying::StateStore` — backfill minute buckets
- Per-index `CandleSeries` cache in Redis for indicator reuse
- Trigger on WebSocket reconnect (auto-detect gap)
- Trigger on new radar strike subscription
- Safe retry + circuit breaker on DhanHQ errors

### Out-of-Scope
- Back-testing integration (already works via `BacktestService`)
- Replacing the existing WebSocket tick path (complements, does not replace)
- UI/API endpoint (could be added later; planed but not built)

---

## Chunk 1 — Core Service (`simple`)

**File:** `app/services/live/historical_backfill_service.rb`
**File:** `spec/services/live/historical_backfill_service_spec.rb`

**Interface:**

```ruby
module Live
  class HistoricalBackfillService
    # Fetch historical candles from DhanHQ and backfill Redis
    # @param instrument [Instrument] ActiveRecord instrument
    # @param interval [Integer] Minute interval: 1, 5, 15, 25, 60
    # @param from_date [String, nil] YYYY-MM-DD HH:MM:SS (default: gap start)
    # @param to_date [String, nil] YYYY-MM-DD HH:MM:SS (default: now)
    # @param reason [Symbol] :reconnect, :warmup, :on_demand
    # @return [Hash] { success: true/false, candles_fetched: N, min_bucket: nil, max_bucket: nil, error: nil }
    def backfill(instrument:, interval: 1, from_date: nil, to_date: nil, reason: :on_demand)

    # Convenience: backfill all active positions + watchlist indices
    def backfill_all(interval: 1, missing_minutes_threshold: 5)

    private
    def fetch_from_dhan(instrument, interval, from_date, to_date)
    def translate_to_tick_payloads(candle, interval)
    def store_in_redis(security_id, interval, payloads)
    def detect_gap(instrument, interval)
    def rate_limit_check
  end
end
```

**Key design decisions:**
- Translate each fetched candle into **two** synthetic ticks: one at bucket start (open), one at bucket end (close). This is enough for `BreakoutEvaluator` to see high/low/open/close when it reads the bucket. Volume and OI are also propagated.
- Store using `StateStore.append_minute_tick` (same Redis sorted-set key format) so consumers need zero changes.
- Cap at `MAX_CANDLES_PER_BACKFILL = 100` to avoid Redis bloat.

**Acceptance criteria:**
- Service fetches 1m candles for a test instrument and stores them in Redis.
- `StateStore.minute_ticks(security_id, bucket)` returns the backfilled data.
- Failed fetches retry once with exponential backoff, then return `success: false`.

---

## Chunk 2 — CandleSeries Cache (`simple`)

**File:** `app/services/live/candle_series_cache.rb`
**File:** `spec/services/live/candle_series_cache_spec.rb`

**Purpose:** Provide a Redis-backed `CandleSeries` so indicators don’t re-fetch from DhanHQ every time.

**Interface:**

```ruby
module Live
  class CandleSeriesCache
    TTL_SECONDS = 3600

    # Get or build a CandleSeries for an instrument + interval
    def self.fetch(instrument:, interval: 5, backfill: true)

    # Force refresh from DhanHQ + merge with live ticks
    def self.refresh(instrument:, interval: 5)

    # Append a live tick (called by MarketFeedHub on each tick) to update the forming candle
    def self.append_tick(instrument:, tick:, interval: 5)
  end
end
```

**Storage format in Redis (JSON string, per key):**

```
Key: live:candles:<security_id>:<interval>
Value: {
  "updated_at": 1718791200,
  "candles": [
    { "timestamp": "2026-06-19T09:15:00Z", "open": 24500.0, "high": 24520.0, "low": 24495.0, "close": 24510.0, "volume": 12500 }
  ]
}
```

**Acceptance criteria:**
- `fetch` returns a `CandleSeries` instance with at least `MIN_CANDLES = 20` candles.
- After `append_tick`, the forming candle updates (open stays, high/low/close adjust, volume increments).
- `backfill: true` calls `HistoricalBackfillService` if cached series has < `MIN_CANDLES`.

---

## Chunk 3 — Integration Hooks (`simple`)

**File:** `app/services/live/market_feed_hub.rb` (small diff)
**File:** `app/services/options_buying/minute_bar_aggregator.rb` (small diff)

**Changes:**

1. **Reconnect gap detection** in `MarketFeedHub#resubscribe_active_positions_after_reconnect`:
   ```ruby
   if last_tick_at && (Time.current - last_tick_at) > 120.seconds
     Rails.logger.info("[MarketFeedHub] Detected #{Time.current - last_tick_at}s gap; triggering backfill")
     Live::HistoricalBackfillService.new.backfill_all(interval: 1)
   end
   ```

2. **Radar strike warm-up** in `MinuteBarAggregator#record_tick!` — when a new security_id is seen for the first time in a session:
   ```ruby
   def record_tick!
     # existing code ...
     unless @seen_security_ids.include?(security_id)
       @seen_security_ids.add(security_id)
       instrument = Instrument.find_by(security_id: security_id)
       Live::HistoricalBackfillService.new.backfill(instrument: instrument, interval: 1, reason: :warmup) if instrument
     end
     # ...
   end
   ```

3. **CandleSeries cache update** in `MarketFeedHub#handle_tick`:
   ```ruby
   def update_market_caches!(tick, ltp)
     # existing tick cache code ...
     if tick[:instrument_type].to_s.upcase == 'INDEX' || index_like?(tick)
       Live::CandleSeriesCache.append_tick(
         instrument: instrument_from_tick(tick),
         tick: tick,
         interval: 5
       )
     end
   end
   ```

**Acceptance criteria:**
- After a simulated 3-minute WebSocket outage, reconnect triggers backfill and `StateStore.minute_ticks` contains the missing minutes.
- When a new radar strike is first ticked, its last 30 minutes are backfilled within 2 seconds.
- `CandleSeriesCache` is updated on every index tick without measurable latency (< 5ms).

---

## Chunk 4 — Indicator Bridge (`simple`)

**File:** `app/services/indicators/cached_indicator_source.rb` (new)

Replace the direct `instrument.candles(interval: 5)` calls in `IndexTechnicalAnalyzer` with the cache:

```ruby
# Before
series = instrument.candles(interval: tf.to_s)

# After
series = Live::CandleSeriesCache.fetch(instrument: instrument, interval: tf.to_i)
```

This avoids hitting DhanHQ REST on every tick-analysis cycle and ensures the series includes backfilled + live data.

**Acceptance criteria:**
- `IndexTechnicalAnalyzer` no longer calls `intraday_ohlc` during live trading.
- Indicators calculate correctly using cached + backfilled candles.
- Tests pass after refactoring.

---

## Verification Commands

```bash
# Chunk 1
bundle exec rspec spec/services/live/historical_backfill_service_spec.rb

# Chunk 2
bundle exec rspec spec/services/live/candle_series_cache_spec.rb

# Chunk 3
bundle exec rspec spec/services/options_buying/minute_bar_aggregator_spec.rb
bundle exec rspec spec/services/live/market_feed_hub_spec.rb

# Chunk 4
bundle exec rspec spec/services/indicators/cached_indicator_source_spec.rb
bundle exec rspec spec/services/index_technical_analyzer_spec.rb

# Full suite
bundle exec rspec
bundle exec rubocop app/services/live/ app/services/options_buying/
```

---

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| **Rate limit hit** (10 req/s on orders, but data API also throttled) | Backfill service uses `RateLimiter` with 1 req/2s cap. Batches all instruments into single calls where possible. |
| **Redis bloat** from backfilling many strikes | Cap at 100 candles per instrument. TTL 3600 on all candle keys. |
| **Incorrect synthetic ticks** (OHLC → open+close only) | Documented limitation; for true HLC accuracy, `BreakoutEvaluator` can be upgraded later to query candle cache directly. |
| **Race condition** between backfill and live tick | Backfill writes to Redis with pipeline; live tick handler uses same `append_minute_tick`. Redis atomic `zadd` prevents data loss. |
| **Static IP requirement** for data API | Same IP as order gateway; `DhanhqErrorHandler` manages token refresh. |

## Complexity Classification

- `HistoricalBackfillService` — **simple** (REST call + Redis write)
- `CandleSeriesCache` — **simple** (JSON serialization + merge logic)
- Integration hooks — **simple** (small diffs in existing services)
- `CachedIndicatorSource` — **simple** (wrapper / delegation)

No goroutines, no worker pools, no complex concurrency. All sequential, single-threaded Redis writes. Safe for `minimax-m2.7` builder.
