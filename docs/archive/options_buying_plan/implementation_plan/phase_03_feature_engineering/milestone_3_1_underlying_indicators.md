# Milestone 3.1: Underlying Indicators

**Phase:** 3 — Feature Engineering  
**Goal:** All technical indicators needed by downstream engines.  
**Estimated Tasks:** 17

---

## Tasks

### 1. Implement EMAIndicator
- [x] Create `app/services/calculations/indicators/ema_indicator.rb`
- [x] Configurable periods: 9, 21, 50, 200 (default from AppConfig)
- [x] Incremental update: `ema_new = (price * multiplier) + (ema_prev * (1 - multiplier))`
- [x] Handle initialization: first value = SMA of first N periods
- [x] Return: `current_value`, `slope`, `distance_from_price`
- [x] Cache in Redis with key: `ema:{instrument_id}:{period}:{timeframe}`

### 2. Implement VWAPIndicator
- [x] Create `app/services/calculations/indicators/vwap_indicator.rb`
- [x] Session VWAP: reset at market open (9:15)
- [x] Standard deviation bands: ±1σ, ±2σ, ±3σ
- [x] Incremental: `vwap = cumulative_pv / cumulative_volume`
- [x] Return: `vwap`, `upper_bands`, `lower_bands`, `distance_from_vwap`
- [x] Cache per session per instrument

### 3. Implement ATRIndicator
- [x] Create `app/services/calculations/indicators/atr_indicator.rb`
- [x] True Range: `max(high-low, |high-prev_close|, |low-prev_close|)`
- [x] ATR: EMA of True Range (default period 14)
- [x] Return: `atr_value`, `atr_percent` (ATR/close * 100)
- [x] Used for: stop loss distance, position sizing, regime detection

### 4. Implement ADXIndicator
- [x] Create `app/services/calculations/indicators/adx_indicator.rb`
- [x] +DI, -DI, ADX (period 14 default)
- [x] +DM = high - prev_high (if > prev_low - low - low), else 0
- [x] -DM = prev_low - low (if > high - prev_high), else 0
- [x] Return: `adx`, `plus_di`, `minus_di`, `trend_strength` (strong > 25)
- [x] Cache: ADX changes slowly, update every 5m

### 5. Implement RSIIndicator
- [x] Create `app/services/calculations/indicators/rsi_indicator.rb`
- [x] Period: 14 (configurable)
- [x] Wilder's smoothing (EMA with 1/period)
- [x] Return: `rsi`, `rsi_signal` (oversold < 30, overbought > 70)
- [x] Divergence detection: price HH + RSI LH = bearish divergence

### 6. Implement MACDIndicator
- [x] Create `app/services/calculations/indicators/macd_indicator.rb`
- [x] Fast EMA (12), Slow EMA (26), Signal EMA (9)
- [x] MACD Line = Fast - Slow
- [x] Signal Line = EMA(MACD, 9)
- [x] Histogram = MACD - Signal
- [x] Return: `macd`, `signal`, `histogram`, `crossover_signal`

### 7. Implement SupertrendIndicator
- [x] Create `app/services/calculations/indicators/supertrend_indicator.rb`
- [x] Parameters: ATR period (10), multiplier (3.0)
- [x] Basic Upper = (H+L)/2 + mult * ATR
- [x] Basic Lower = (H+L)/2 - mult * ATR
- [x] Final bands with trend logic
- [x] Return: `supertrend_line`, `trend` (up/down), `flip_signal`

### 8. Implement VolumeProfileIndicator
- [x] Create `app/services/calculations/indicators/volume_profile_indicator.rb`
- [x] Price levels with volume aggregation (tick size buckets)
- [x] POC (Point of Control): price with highest volume
- [x] Value Area: 70% volume range (VAH, VAL)
- [x] Return: `poc`, `vah`, `val`, `profile` (array of price/volume)
- [x] Session-based: reset at market open

### 9. Implement RelativeVolumeIndicator
- [x] Create `app/services/calculations/indicators/relative_volume_indicator.rb`
- [x] Current volume vs 20-day average for same time-of-day
- [x] Intraday seasonal pattern: compare 9:15-9:30 today vs avg 9:15-9:30
- [x] Return: `rv_ratio`, `rv_signal` (high > 2, low < 0.5)
- [x] Cache daily averages, update after market close

### 10. Implement OpeningRangeIndicator
- [x] Create `app/services/calculations/indicators/opening_range_indicator.rb`
- [x] First N minutes (configurable: 15, 30)
- [x] OR High, OR Low, OR Mid
- [x] Breakout detection: price > ORH + buffer, price < ORL - buffer
- [x] Return: `or_high`, `or_low`, `or_mid`, `breakout_direction`, `breakout_strength`

### 11. Implement ROCIndicator
- [x] Create `app/services/calculations/indicators/roc_indicator.rb`
- [x] Rate of Change: `(close - close_n_periods_ago) / close_n_periods_ago * 100`
- [x] Periods: 9, 21 (configurable)
- [x] Return: `roc`, `roc_signal` (accelerating/decelerating)

### 12. Implement BollingerBandsIndicator
- [x] Create `app/services/calculations/indicators/bollinger_bands_indicator.rb`
- [x] Period: 20, StdDev: 2 (configurable)
- [x] Middle = SMA(20), Upper = Middle + 2σ, Lower = Middle - 2σ
- [x] Bandwidth = (Upper - Lower) / Middle
- [x] %B = (Price - Lower) / (Upper - Lower)
- [x] Return: `upper`, `middle`, `lower`, `bandwidth`, `percent_b`, `squeeze` (bandwidth < 0.05)

### 13. Create IndicatorCache
- [x] Create `app/services/indicator_cache.rb`
- [x] Redis-backed with TTL per timeframe:
  - 1m: 30s TTL
  - 5m: 60s TTL
  - 15m: 2m TTL
  - 30m: 5m TTL
- [x] Key pattern: `indicator:{name}:{instrument_id}:{timeframe}:{params_hash}`
- [x] Invalidate on new candle close
- [x] Metrics: hit rate, miss rate, latency

### 14. Add IndicatorValidator
- [x] Create `app/services/validators/indicator_validator.rb`
- [x] Check: sufficient data points (min 2x period)
- [x] Check: data freshness (last candle < 2x timeframe old)
- [x] Check: no NaN/inf values
- [x] Return: `valid?`, `errors`, `warnings`

### 15. Implement IndicatorRegistry
- [x] Create `app/services/indicator_registry.rb`
- [x] Register all indicators with metadata:
  - name, required_params, output_schema, timeframes_supported
- [x] Dynamic loading: `IndicatorRegistry.get(:ema, period: 21)`
- [x] List available: `IndicatorRegistry.all`
- [x] Used by engines to declare required indicators

### 16. Add Mathematical Accuracy Tests
- [x] Create `spec/services/calculations/indicators/`
- [x] Test each indicator against known reference values
- [x] Use fixtures from `ta-lib` or `pandas-ta` for verification
- [x] Property tests: EMA smoothness, RSI bounds [0,100], ATR > 0
- [x] Edge cases: flat prices, gaps, zero volume, single candle

### 17. Add Performance Benchmarks
- [x] Create `spec/performance/indicators_benchmark.rb`
- [x] Benchmark: 1000 candles, all indicators
- [x] Targets:
  - EMA: < 0.1ms per update
  - VWAP: < 0.2ms per update
  - ATR: < 0.1ms per update
  - ADX: < 0.5ms per update (heavier)
  - Volume Profile: < 2ms per session build
  - All indicators combined: < 5ms per candle per instrument

---

## Acceptance Criteria
- [x] All 12 indicators implemented and tested
- [x] Mathematical accuracy verified against reference implementation
- [x] Incremental updates work correctly (no full recalc needed)
- [x] Cache hit rate > 90% in live trading
- [x] IndicatorRegistry loads all indicators dynamically
- [x] Performance benchmarks meet targets
- [x] IndicatorValidator catches stale/insufficient data
- [x] All indicators output structured domain objects with `to_h`

---

## Notes
- Indicators are pure functions: input candles → output values
- No side effects, no external dependencies
- Timezone: all timestamps UTC, market hours handled by ExchangeCalendar
- Consider using `numo-narray` for vectorized calculations if performance critical
- Indicators used by: Market Regime, Market Structure, Momentum, Liquidity engines