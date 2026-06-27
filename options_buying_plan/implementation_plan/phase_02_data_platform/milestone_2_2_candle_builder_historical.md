# Milestone 2.2: Candle Builder & Historical Database

**Phase:** 2 — Data Platform  
**Goal:** Reliable OHLC generation from ticks with gap handling.  
**Estimated Tasks:** 12

---

## Tasks

### 1. Implement CandleBuilder
- [x] Create `app/services/calculations/candle_builder.rb`
- [x] Input: stream of `MarketTick` objects (ordered by timestamp)
- [x] Output: `Candle` objects for configurable timeframes
- [x] State machine per instrument/timeframe:
  - `OPEN` - accepting ticks
  - `CLOSED` - candle complete, ready to persist
- [x] Thread-safe: use `Concurrent::Map` for builder instances

### 2. Add TickAggregator for Incomplete Candles
- [x] Handle ticks arriving out of order (within tolerance)
- [x] Late ticks (within 5s of candle close): update OHLCV
- [x] Very late ticks (>5s): log, drop, increment `late_ticks` metric
- [x] Maintain `current_candle` and `previous_candle` for each timeframe
- [x] Publish `candle.update` events for real-time charts

### 3. Implement CandleGapDetector
- [x] Create `app/services/engines/candle_gap_detector.rb`
- [x] Scan `candles` table for missing intervals per instrument/timeframe
- [x] Detection: expected count vs actual count in time range
- [x] Output: `GapReport` with `missing_intervals` array
- [x] Schedule: run every 5 minutes during market hours

### 4. Create HistoricalDataSyncJob
- [x] Create `app/jobs/historical_data_sync_job.rb`
- [x] Consume `GapReport` from EventBus
- [x] Call `HistoricalDataService.fetch_ohlcv` for each gap
- [x] Respect rate limits: 10 req/sec, batch 100 candles per request
- [x] Priority: fill gaps < 1 hour old first
- [x] Retry failed gaps with exponential backoff
- [x] Publish `candles.filled` event on completion

### 5. Add VWAPCalculator
- [x] Create `app/services/calculations/vwap_calculator.rb`
- [x] Per-candle VWAP: `SUM(price * volume) / SUM(volume)`
- [x] Session VWAP: cumulative from market open
- [x] Anchored VWAP: from specific time (e.g., gap up open)
- [x] Rolling VWAP: last N candles (configurable)

### 6. Implement OIChangeCalculator
- [x] Create `app/services/calculations/oi_change_calculator.rb`
- [x] Per-candle OI change: `close_oi - open_oi`
- [x] Cumulative OI change from session start
- [x] OI change rate: `change / time_elapsed`
- [x] Classify: `long_build_up`, `short_build_up`, `long_unwinding`, `short_covering`

### 7. Create RelativeVolumeCalculator
- [x] Create `app/services/calculations/relative_volume_calculator.rb`
- [x] Compare current candle volume to 20-day average for same timeframe
- [x] `relative_volume = current_volume / avg_volume_20d`
- [x] Flag: `high` (>2x), `normal` (0.5-2x), `low` (<0.5x)
- [x] Use for volume confirmation in strategies

### 8. Add OpeningRangeCalculator
- [x] Create `app/services/calculations/opening_range_calculator.rb`
- [x] First 15 minutes: `high_15m - low_15m`
- [x] First 30 minutes: `high_30m - low_30m`
- [x] Track: OR high, OR low, OR midpoint, OR range size
- [x] Breakout levels: OR high + 0.5% buffer, OR low - 0.5% buffer
- [x] Publish `opening_range.established` event at 9:30 and 9:45

### 9. Implement PreviousHighLowTracker
- [x] Create `app/services/calculations/previous_high_low_tracker.rb`
- [x] Daily: previous day high/low
- [x] Weekly: previous week high/low (Mon-Fri)
- [x] Monthly: previous month high/low
- [x] All-time: highest high, lowest low in lookback period
- [x] Update at market close, cache in Redis

### 10. Create CandleRepository
- [x] Create `app/services/repositories/candle_repository.rb`
- [x] Methods:
  - `candles(instrument_id, timeframe, from:, to:, limit:)`
  - `latest_candle(instrument_id, timeframe)`
  - `candle_at(instrument_id, timeframe, timestamp)`
  - `vwap_range(instrument_id, timeframe, from:, to:)`
  - `opening_range(instrument_id, minutes: 15)`
  - `previous_high_low(instrument_id, period: :daily)`
- [x] Use continuous aggregates for < 1h timeframes
- [x] Fall back to raw ticks for custom timeframes

### 11. Add Candles API Endpoint
- [x] Create `app/controllers/api/v1/candles_controller.rb`
- [x] `GET /api/v1/candles?instrument_id=&timeframe=&from=&to=&limit=`
- [x] Response: array of `{timestamp, open, high, low, close, volume, vwap, oi}`
- [x] Support `format=chart` for lightweight charting (timestamp, close only)
- [x] Cache-Control: 5s for live, 1h for historical

### 12. Write Unit Tests for Candle Math
- [x] Create `spec/services/calculations/candle_builder_spec.rb`
- [x] Test cases:
  - Basic OHLCV from ordered ticks
  - Ticks out of order (late arrival)
  - Zero volume ticks
  - Price gaps (large jumps)
  - VWAP calculation accuracy
  - Candle rollover at timeframe boundaries
  - Multiple timeframes from same tick stream
  - Gap detection with known missing intervals
  - Historical sync fills gaps correctly
- [x] Use property-based testing for mathematical invariants

---

## Acceptance Criteria
- [x] `CandleBuilder` produces identical candles to TimescaleDB continuous aggregates
- [x] Gap detector finds all missing intervals in test data
- [x] Historical sync fills gaps within 5 minutes of detection
- [x] VWAP matches manual calculation to 2 decimal places
- [x] OI classification matches known patterns
- [x] Relative volume uses correct 20-day baseline
- [x] Opening range levels used by ORB strategy correctly
- [x] Previous high/low levels match NSE published data
- [x] API returns data in < 50ms for 500 candles
- [x] All unit tests pass with 100% coverage on calculations

---

## Notes
- Continuous aggregates handle 95% of candle building; custom builder for real-time updates
- Tick timestamps from WebSocket may have millisecond precision; align to timeframe boundaries
- Handle corporate actions (splits, bonuses) - adjust historical prices
- Pre-market ticks (9:00-9:15) build separate `pre_market` candles
- Consider `time_bucket_gapfill` for chart-ready data with no gaps