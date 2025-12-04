# No-Trade Engine Timeframes

**Last Updated**: Includes complete timeframe usage documentation

---

## Overview

The No-Trade Engine uses **two timeframes** for validation:

1. **1-minute (1m)** - Primary timeframe for most checks
2. **5-minute (5m)** - Used specifically for ADX/DI trend strength calculations

---

## Timeframe Usage Breakdown

### 1-Minute (1m) Timeframe

**Used For**:
- ✅ **Structure Detection** (BOS, Order Blocks, FVG)
- ✅ **VWAP Calculations** (VWAP and AVWAP)
- ✅ **Volatility Checks** (Range, ATR)
- ✅ **Candle Quality Analysis** (Wick ratios, patterns)
- ✅ **Phase 1 Pre-Check** (Quick validation before signal generation)

**Specific Checks Using 1m**:

| Check | Method | Lookback Period |
|-------|--------|----------------|
| Break of Structure (BOS) | `StructureDetector.bos?()` | Last 10 minutes (10 candles) |
| Inside Opposite Order Block | `StructureDetector.inside_opposite_ob?()` | Last 5 candles |
| Inside Fair Value Gap | `StructureDetector.inside_fvg?()` | Last 5 candles |
| Near VWAP | `VWAPUtils.near_vwap?()` | All available candles |
| Trapped Between VWAP/AVWAP | `VWAPUtils.trapped_between_vwap_avwap?()` | All available candles |
| 10-Minute Range | `RangeUtils.range_pct()` | Last 10 candles |
| ATR Downtrend | `ATRUtils.atr_downtrend?()` | Last 14+ candles (sliding windows) |
| Average Wick Ratio | `CandleUtils.avg_wick_ratio()` | Last 5 candles |

**Code Reference**:
```ruby
# Phase 1: Quick pre-check
bars_1m = instrument.candle_series(interval: '1')

# Phase 2: Detailed validation
bars_1m = cached_bars_1m || instrument.candle_series(interval: '1')
```

---

### 5-Minute (5m) Timeframe

**Used For**:
- ✅ **ADX Calculation** (Average Directional Index)
- ✅ **DI+ Calculation** (Positive Directional Indicator)
- ✅ **DI- Calculation** (Negative Directional Indicator)
- ✅ **Trend Strength Validation** (Phase 2 detailed validation)

**Specific Checks Using 5m**:

| Check | Method | Lookback Period |
|-------|--------|----------------|
| ADX Value | `NoTradeContextBuilder.calculate_adx_data()` | Last 14+ candles (period=14) |
| DI+ Value | `NoTradeContextBuilder.calculate_adx_data()` | Last 14+ candles (period=14) |
| DI- Value | `NoTradeContextBuilder.calculate_adx_data()` | Last 14+ candles (period=14) |
| ADX Threshold | `NoTradeEngine.validate()` | ADX < 15 (weak trend) |
| DI Overlap | `NoTradeEngine.validate()` | \|DI+ - DI-\| < 2 (no directional strength) |

**Code Reference**:
```ruby
# Phase 2: Detailed validation
bars_5m = instrument.candle_series(interval: '5')

# ADX calculation from 5m bars
adx_data = calculate_adx_data(bars_5m)
# Returns: { adx: Float, plus_di: Float, minus_di: Float }
```

---

## Why These Timeframes?

### 1-Minute for Structure & Volatility

**Rationale**:
- **Structure Detection**: BOS, Order Blocks, and FVG patterns are best detected on shorter timeframes (1m) for precision
- **VWAP Calculations**: 1m candles provide granular VWAP/AVWAP calculations without volume
- **Volatility Checks**: Range and ATR on 1m capture intraday volatility accurately
- **Candle Quality**: Wick ratios and patterns are most meaningful on 1m candles

**Benefits**:
- ✅ Captures intraday structure changes quickly
- ✅ Provides granular volatility measurements
- ✅ Detects short-term price behavior patterns

### 5-Minute for Trend Strength

**Rationale**:
- **ADX/DI Calculations**: Trend strength indicators (ADX, DI+, DI-) are more reliable on 5m timeframe
- **Noise Reduction**: 5m timeframe filters out 1m noise while maintaining responsiveness
- **Industry Standard**: ADX is typically calculated on 5m or higher timeframes for intraday trading

**Benefits**:
- ✅ More reliable trend strength signals
- ✅ Reduces false signals from 1m noise
- ✅ Aligns with standard technical analysis practices

---

## Phase-by-Phase Timeframe Usage

### Phase 1: Quick No-Trade Pre-Check

**Timeframes Used**:
- ✅ **1m** - For basic structure and volatility checks

**Data Fetched**:
```ruby
bars_1m = instrument.candle_series(interval: '1')
```

**Checks Performed**:
- Time windows (no data needed)
- Basic volatility (10-minute range from 1m bars)
- Basic option chain (IV, spread)

**Returns**:
- `bars_1m` - Cached for reuse in Phase 2
- `option_chain_data` - Cached for reuse in Phase 2

---

### Phase 2: Detailed No-Trade Validation

**Timeframes Used**:
- ✅ **1m** - Reused from Phase 1 (or fetched if not cached)
- ✅ **5m** - Fetched for ADX/DI calculations

**Data Fetched**:
```ruby
bars_1m = cached_bars_1m || instrument.candle_series(interval: '1')
bars_5m = instrument.candle_series(interval: '5')
```

**Checks Performed**:
- ADX/DI values (from 5m bars)
- Structure indicators (BOS, OB, FVG from 1m bars)
- VWAP indicators (from 1m bars)
- Volatility indicators (from 1m bars)
- Option chain indicators (reused from Phase 1)
- Candle quality (from 1m bars)

---

## Data Flow

```
Signal::Engine.run_for()
  │
  ├─> Phase 1: Quick Pre-Check
  │   └─> Fetch bars_1m (interval: '1')
  │       └─> Cache for Phase 2
  │
  ├─> Signal Generation
  │   └─> Uses primary_timeframe (typically '5m' from config)
  │
  └─> Phase 2: Detailed Validation
      ├─> Reuse bars_1m from Phase 1
      └─> Fetch bars_5m (interval: '5')
          └─> Build context with both timeframes
              └─> NoTradeEngine.validate(ctx)
```

---

## Context Builder Timeframe Mapping

The `NoTradeContextBuilder` receives both timeframes and maps them to specific checks:

```ruby
NoTradeContextBuilder.build(
  index: index_key,
  bars_1m: bars_1m.candles,      # 1-minute candles
  bars_5m: bars_5m.candles,      # 5-minute candles
  option_chain: option_chain_data,
  time: Time.current
)
```

**Context Fields by Timeframe**:

| Field | Timeframe | Source |
|-------|-----------|--------|
| `adx_5m` | 5m | `calculate_adx_data(bars_5m)` |
| `plus_di_5m` | 5m | `calculate_adx_data(bars_5m)` |
| `minus_di_5m` | 5m | `calculate_adx_data(bars_5m)` |
| `bos_present` | 1m | `StructureDetector.bos?(bars_1m)` |
| `in_opposite_ob` | 1m | `StructureDetector.inside_opposite_ob?(bars_1m)` |
| `inside_fvg` | 1m | `StructureDetector.inside_fvg?(bars_1m)` |
| `near_vwap` | 1m | `VWAPUtils.near_vwap?(bars_1m)` |
| `trapped_between_vwap` | 1m | `VWAPUtils.trapped_between_vwap_avwap?(bars_1m)` |
| `range_10m_pct` | 1m | `RangeUtils.range_pct(bars_1m.last(10))` |
| `atr_downtrend` | 1m | `ATRUtils.atr_downtrend?(bars_1m)` |
| `avg_wick_ratio` | 1m | `CandleUtils.avg_wick_ratio(bars_1m.last(5))` |

---

## Summary

**No-Trade Engine Timeframes**:
- ✅ **1-minute (1m)**: Primary timeframe for structure, volatility, VWAP, and candle quality checks
- ✅ **5-minute (5m)**: Used specifically for ADX/DI trend strength calculations

**Key Points**:
- 1m provides granular intraday analysis
- 5m provides reliable trend strength signals
- Data is cached between phases for efficiency
- Both timeframes are required for complete validation

**No other timeframes are used** - the No-Trade Engine is designed to work with these two timeframes only.
