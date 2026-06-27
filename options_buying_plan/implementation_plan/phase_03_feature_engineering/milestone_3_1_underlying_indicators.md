# Milestone 3.1: Underlying Indicators

**Phase:** 3 — Feature Engineering  
**Goal:** All technical indicators needed by downstream engines.  
**Estimated Tasks:** 17

---

## Tasks

### 1. Implement EMAIndicator
- [ ] Create `app/services/calculations/indicators/ema_indicator.rb`
- [ ] Configurable periods: 9, 21, 50, 200 (default from AppConfig)
- [ ] Incremental update: `ema_new = (price * multiplier) + (ema_prev * (1 - multiplier))`
- [ ] Handle initialization: first value = SMA of first N periods
- [ ] Return: `current_value`, `slope`, `distance_from_price`
- [ ] Cache in Redis with key: `ema:{instrument_id}:{period}:{timeframe}`

### 2. Implement VWAPIndicator
- [ ] Create `app/services/calculations/indicators/vwap_indicator.rb`
- [ ] Session VWAP: reset at market open (9:15)
- [ ] Standard deviation bands: ±1σ, ±2σ, ±3σ
- [ ] Incremental: `vwap = cumulative_pv / cumulative_volume`
- [ ] Return: `vwap`, `upper_bands`, `lower_bands`, `distance_from_vwap`
- [ ] Cache per session per instrument

### 3. Implement ATRIndicator
- [ ] Create `app/services/calculations/indicators/atr_indicator.rb`
- [ ] True Range: `max(high-low, |high-prev_close|, |low-prev_close|)`
- [ ] ATR: EMA of True Range (default period 14)
- [ ] Return: `atr_value`, `atr_percent` (ATR/close * 100)
- [ ] Used for: stop loss distance, position sizing, regime detection

### 4. Implement ADXIndicator
- [ ] Create `app/services/calculations/indicators/adx_indicator.rb`
- [ ] +DI, -DI, ADX (period 14 default)
- [ ] +DM = high - prev_high (if > prev_low - low - low), else 0
- [ ] -DM = prev_low - low (if > high - prev_high), else 0
- [ ] Return: `adx`, `plus_di`, `minus_di`, `trend_strength` (strong > 25)
- [ ] Cache: ADX changes slowly, update every 5m

### 5. Implement RSIIndicator
- [ ] Create `app/services/calculations/indicators/rsi_indicator.rb`
- [ ] Period: 14 (configurable)
- [ ] Wilder's smoothing (EMA with 1/period)
- [ ] Return: `rsi`, `rsi_signal` (oversold < 30, overbought > 70)
- [ ] Divergence detection: price HH + RSI LH = bearish divergence

### 6. Implement MACDIndicator
- [ ] Create `app/services/calculations/indicators/macd_indicator.rb`
- [ ] Fast EMA (12), Slow EMA (26), Signal EMA (9)
- [ ] MACD Line = Fast - Slow
- [ ] Signal Line = EMA(MACD, 9)
- [ ] Histogram = MACD - Signal
- [ ] Return: `macd`, `signal`, `histogram`, `crossover_signal`

### 7. Implement SupertrendIndicator
- [ ] Create `app/services/calculations/indicators/supertrend_indicator.rb`
- [ ] Parameters: ATR period (10), multiplier (3.0)
- [ ] Basic Upper = (H+L)/2 + mult * ATR
- [ ] Basic Lower = (H+L)/2 - mult * ATR
- [ ] Final bands with trend logic
- [ ] Return: `supertrend_line`, `trend` (up/down), `flip_signal`

### 8. Implement VolumeProfileIndicator
- [ ] Create `app/services/calculations/indicators/volume_profile_indicator.rb`
- [ ] Price levels with volume aggregation (tick size buckets)
- [ ] POC (Point of Control): price with highest volume
- [ ] Value Area: 70% volume range (VAH, VAL)
- [ ] Return: `poc`, `vah`, `val`, `profile` (array of price/volume)
- [ ] Session-based: reset at market open

### 9. Implement RelativeVolumeIndicator
- [ ] Create `app/services/calculations/indicators/relative_volume_indicator.rb`
- [ ] Current volume vs 20-day average for same time-of-day
- [ ] Intraday seasonal pattern: compare 9:15-9:30 today vs avg 9:15-9:30
- [ ] Return: `rv_ratio`, `rv_signal` (high > 2, low < 0.5)
- [ ] Cache daily averages, update after market close

### 10. Implement OpeningRangeIndicator
- [ ] Create `app/services/calculations/indicators/opening_range_indicator.rb`
- [ ] First N minutes (configurable: 15, 30)
- [ ] OR High, OR Low, OR Mid
- [ ] Breakout detection: price > ORH + buffer, price < ORL - buffer
- [ ] Return: `or_high`, `or_low`, `or_mid`, `breakout_direction`, `breakout_strength`

### 11. Implement ROCIndicator
- [ ] Create `app/services/calculations/indicators/roc_indicator.rb`
- [ ] Rate of Change: `(close - close_n_periods_ago) / close_n_periods_ago * 100`
- [ ] Periods: 9, 21 (configurable)
- [ ] Return: `roc`, `roc_signal` (accelerating/decelerating)

### 12. Implement BollingerBandsIndicator
- [ ] Create `app/services/calculations/indicators/bollinger_bands_indicator.rb`
- [ ] Period: 20, StdDev: 2 (configurable)
- [ ] Middle = SMA(20), Upper = Middle + 2σ, Lower = Middle - 2σ
- [ ] Bandwidth = (Upper - Lower) / Middle
- [ ] %B = (Price - Lower) / (Upper - Lower)
- [ ] Return: `upper`, `middle`, `lower`, `bandwidth`, `percent_b`, `squeeze` (bandwidth < 0.05)

### 13. Create IndicatorCache
- [ ] Create `app/services/indicator_cache.rb`
- [ ] Redis-backed with TTL per timeframe:
  - 1m: 30s TTL
  - 5m: 60s TTL
  - 15m: 2m TTL
  - 30m: 5m TTL
- [ ] Key pattern: `indicator:{name}:{instrument_id}:{timeframe}:{params_hash}`
- [ ] Invalidate on new candle close
- [ ] Metrics: hit rate, miss rate, latency

### 14. Add IndicatorValidator
- [ ] Create `app/services/validators/indicator_validator.rb`
- [ ] Check: sufficient data points (min 2x period)
- [ ] Check: data freshness (last candle < 2x timeframe old)
- [ ] Check: no NaN/inf values
- [ ] Return: `valid?`, `errors`, `warnings`

### 15. Implement IndicatorRegistry
- [ ] Create `app/services/indicator_registry.rb`
- [ ] Register all indicators with metadata:
  - name, required_params, output_schema, timeframes_supported
- [ ] Dynamic loading: `IndicatorRegistry.get(:ema, period: 21)`
- [ ] List available: `IndicatorRegistry.all`
- [ ] Used by engines to declare required indicators

### 16. Add Mathematical Accuracy Tests
- [ ] Create `spec/services/calculations/indicators/`
- [ ] Test each indicator against known reference values
- [ ] Use fixtures from `ta-lib` or `pandas-ta` for verification
- [ ] Property tests: EMA smoothness, RSI bounds [0,100], ATR > 0
- [ ] Edge cases: flat prices, gaps, zero volume, single candle

### 17. Add Performance Benchmarks
- [ ] Create `spec/performance/indicators_benchmark.rb`
- [ ] Benchmark: 1000 candles, all indicators
- [ ] Targets:
  - EMA: < 0.1ms per update
  - VWAP: < 0.2ms per update
  - ATR: < 0.1ms per update
  - ADX: < 0.5ms per update (heavier)
  - Volume Profile: < 2ms per session build
  - All indicators combined: < 5ms per candle per instrument

---

## Acceptance Criteria
- [ ] All 12 indicators implemented and tested
- [ ] Mathematical accuracy verified against reference implementation
- [ ] Incremental updates work correctly (no full recalc needed)
- [ ] Cache hit rate > 90% in live trading
- [ ] IndicatorRegistry loads all indicators dynamically
- [ ] Performance benchmarks meet targets
- [ ] IndicatorValidator catches stale/insufficient data
- [ ] All indicators output structured domain objects with `to_h`

---

## Notes
- Indicators are pure functions: input candles → output values
- No side effects, no external dependencies
- Timezone: all timestamps UTC, market hours handled by ExchangeCalendar
- Consider using `numo-narray` for vectorized calculations if performance critical
- Indicators used by: Market Regime, Market Structure, Momentum, Liquidity engines