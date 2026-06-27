# Milestone 2.2: Candle Builder & Historical Database

**Phase:** 2 — Data Platform  
**Goal:** Reliable OHLC generation from ticks with gap handling.  
**Estimated Tasks:** 12

---

## Tasks

### 1. Implement CandleBuilder
- [ ] Create `app/services/calculations/candle_builder.rb`
- [ ] Input: stream of `MarketTick` objects (ordered by timestamp)
- [ ] Output: `Candle` objects for configurable timeframes
- [ ] State machine per instrument/timeframe:
  - `OPEN` - accepting ticks
  - `CLOSED` - candle complete, ready to persist
- [ ] Thread-safe: use `Concurrent::Map` for builder instances

### 2. Add TickAggregator for Incomplete Candles
- [ ] Handle ticks arriving out of order (within tolerance)
- [ ] Late ticks (within 5s of candle close): update OHLCV
- [ ] Very late ticks (>5s): log, drop, increment `late_ticks` metric
- [ ] Maintain `current_candle` and `previous_candle` for each timeframe
- [ ] Publish `candle.update` events for real-time charts

### 3. Implement CandleGapDetector
- [ ] Create `app/services/engines/candle_gap_detector.rb`
- [ ] Scan `candles` table for missing intervals per instrument/timeframe
- [ ] Detection: expected count vs actual count in time range
- [ ] Output: `GapReport` with `missing_intervals` array
- [ ] Schedule: run every 5 minutes during market hours

### 4. Create HistoricalDataSyncJob
- [ ] Create `app/jobs/historical_data_sync_job.rb`
- [ ] Consume `GapReport` from EventBus
- [ ] Call `HistoricalDataService.fetch_ohlcv` for each gap
- [ ] Respect rate limits: 10 req/sec, batch 100 candles per request
- [ ] Priority: fill gaps < 1 hour old first
- [ ] Retry failed gaps with exponential backoff
- [ ] Publish `candles.filled` event on completion

### 5. Add VWAPCalculator
- [ ] Create `app/services/calculations/vwap_calculator.rb`
- [ ] Per-candle VWAP: `SUM(price * volume) / SUM(volume)`
- [ ] Session VWAP: cumulative from market open
- [ ] Anchored VWAP: from specific time (e.g., gap up open)
- [ ] Rolling VWAP: last N candles (configurable)

### 6. Implement OIChangeCalculator
- [ ] Create `app/services/calculations/oi_change_calculator.rb`
- [ ] Per-candle OI change: `close_oi - open_oi`
- [ ] Cumulative OI change from session start
- [ ] OI change rate: `change / time_elapsed`
- [ ] Classify: `long_build_up`, `short_build_up`, `long_unwinding`, `short_covering`

### 7. Create RelativeVolumeCalculator
- [ ] Create `app/services/calculations/relative_volume_calculator.rb`
- [ ] Compare current candle volume to 20-day average for same timeframe
- [ ] `relative_volume = current_volume / avg_volume_20d`
- [ ] Flag: `high` (>2x), `normal` (0.5-2x), `low` (<0.5x)
- [ ] Use for volume confirmation in strategies

### 8. Add OpeningRangeCalculator
- [ ] Create `app/services/calculations/opening_range_calculator.rb`
- [ ] First 15 minutes: `high_15m - low_15m`
- [ ] First 30 minutes: `high_30m - low_30m`
- [ ] Track: OR high, OR low, OR midpoint, OR range size
- [ ] Breakout levels: OR high + 0.5% buffer, OR low - 0.5% buffer
- [ ] Publish `opening_range.established` event at 9:30 and 9:45

### 9. Implement PreviousHighLowTracker
- [ ] Create `app/services/calculations/previous_high_low_tracker.rb`
- [ ] Daily: previous day high/low
- [ ] Weekly: previous week high/low (Mon-Fri)
- [ ] Monthly: previous month high/low
- [ ] All-time: highest high, lowest low in lookback period
- [ ] Update at market close, cache in Redis

### 10. Create CandleRepository
- [ ] Create `app/services/repositories/candle_repository.rb`
- [ ] Methods:
  - `candles(instrument_id, timeframe, from:, to:, limit:)`
  - `latest_candle(instrument_id, timeframe)`
  - `candle_at(instrument_id, timeframe, timestamp)`
  - `vwap_range(instrument_id, timeframe, from:, to:)`
  - `opening_range(instrument_id, minutes: 15)`
  - `previous_high_low(instrument_id, period: :daily)`
- [ ] Use continuous aggregates for < 1h timeframes
- [ ] Fall back to raw ticks for custom timeframes

### 11. Add Candles API Endpoint
- [ ] Create `app/controllers/api/v1/candles_controller.rb`
- [ ] `GET /api/v1/candles?instrument_id=&timeframe=&from=&to=&limit=`
- [ ] Response: array of `{timestamp, open, high, low, close, volume, vwap, oi}`
- [ ] Support `format=chart` for lightweight charting (timestamp, close only)
- [ ] Cache-Control: 5s for live, 1h for historical

### 12. Write Unit Tests for Candle Math
- [ ] Create `spec/services/calculations/candle_builder_spec.rb`
- [ ] Test cases:
  - Basic OHLCV from ordered ticks
  - Ticks out of order (late arrival)
  - Zero volume ticks
  - Price gaps (large jumps)
  - VWAP calculation accuracy
  - Candle rollover at timeframe boundaries
  - Multiple timeframes from same tick stream
  - Gap detection with known missing intervals
  - Historical sync fills gaps correctly
- [ ] Use property-based testing for mathematical invariants

---

## Acceptance Criteria
- [ ] `CandleBuilder` produces identical candles to TimescaleDB continuous aggregates
- [ ] Gap detector finds all missing intervals in test data
- [ ] Historical sync fills gaps within 5 minutes of detection
- [ ] VWAP matches manual calculation to 2 decimal places
- [ ] OI classification matches known patterns
- [ ] Relative volume uses correct 20-day baseline
- [ ] Opening range levels used by ORB strategy correctly
- [ ] Previous high/low levels match NSE published data
- [ ] API returns data in < 50ms for 500 candles
- [ ] All unit tests pass with 100% coverage on calculations

---

## Notes
- Continuous aggregates handle 95% of candle building; custom builder for real-time updates
- Tick timestamps from WebSocket may have millisecond precision; align to timeframe boundaries
- Handle corporate actions (splits, bonuses) - adjust historical prices
- Pre-market ticks (9:00-9:15) build separate `pre_market` candles
- Consider `time_bucket_gapfill` for chart-ready data with no gaps