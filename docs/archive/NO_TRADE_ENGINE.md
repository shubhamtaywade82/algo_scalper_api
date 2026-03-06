# No-Trade Engine

**Last Updated**: Based on current codebase implementation

---

## Overview

The No-Trade Engine is a volume-independent validation system that blocks option trades when multiple unfavorable market conditions are present. It integrates seamlessly with the Supertrend + ADX signal generator and eliminates 70-80% of bad option-buy trades through a two-phase validation approach.

## Architecture

### Two-Phase Implementation

The engine uses a **two-phase validation system** that optimizes for both speed and thoroughness:

1. **Phase 1: Quick Pre-Check** - Runs BEFORE expensive signal generation (fail-fast)
2. **Phase 2: Detailed Validation** - Runs AFTER signal generation with full context

### Components

#### Core Engine (`app/services/entries/`)
- **`NoTradeEngine`** - Main validation engine with 11-point scoring system
- **`NoTradeContextBuilder`** - Builds validation context from market data
- **`OptionChainWrapper`** - Wraps option chain data for easy access

#### Utility Classes (`app/services/entries/`)
- **`StructureDetector`** - Detects BOS, Order Blocks, FVG patterns
- **`VWAPUtils`** - VWAP/AVWAP calculations (using typical price when volume unavailable)
- **`RangeUtils`** - Volatility range calculations
- **`ATRUtils`** - ATR-based volatility analysis
- **`CandleUtils`** - Candle pattern analysis (wick ratios, engulfing patterns)

#### Integration Point (`app/services/signal/engine.rb`)
- `quick_no_trade_precheck()` - Phase 1 validation
- `validate_no_trade_conditions()` - Phase 2 validation
- Validates conditions before calling `EntryGuard.try_enter()`

---

## Execution Flow

```
Signal::Engine.run_for(index_cfg)
  ├─> Check market closed
  ├─> Fetch instrument
  │
  ├─> [PHASE 1] Quick No-Trade Pre-Check ← FAIL FAST
  │   ├─> Time windows check (no data needed)
  │   ├─> Fetch bars_1m
  │   ├─> Basic volatility (10m range < 0.1%)
  │   ├─> Fetch option chain
  │   ├─> Basic option chain (IV threshold, spread)
  │   └─> Return: {allowed, score, reasons, option_chain_data, bars_1m}
  │
  ├─> [IF BLOCKED] EXIT (no signal generation)
  │
  ├─> [IF ALLOWED] Signal Generation
  │   ├─> Strategy recommendation (if enabled)
  │   ├─> Supertrend + ADX calculations
  │   ├─> Multi-timeframe analysis
  │   ├─> Comprehensive validation
  │   └─> Pick option strikes
  │
  ├─> [PHASE 2] Detailed No-Trade Validation ← FULL CONTEXT
  │   ├─> Reuse bars_1m from Phase 1
  │   ├─> Fetch bars_5m (for ADX/DI)
  │   ├─> Reuse option_chain_data from Phase 1
  │   ├─> Build full context (ADX, DI, structure, VWAP, etc.)
  │   ├─> NoTradeEngine.validate(ctx)
  │   └─> Return: {allowed, score, reasons}
  │
  ├─> [IF BLOCKED] EXIT (log detailed reasons)
  │
  └─> [IF ALLOWED] EntryGuard.try_enter()
```

---

## Phase 1: Quick Pre-Check

### Purpose
Fail-fast validation to block obvious bad conditions before expensive signal generation.

### Execution Point
Runs immediately after fetching the instrument, **before** any signal generation.

### Checks Performed

1. **Time Windows** (fastest check - no data needed)
   - 09:15-09:18: Avoid first 3 minutes
   - 11:20-13:30: Lunch-time theta zone
   - After 15:05: Post 3:05 PM - theta crush

2. **Basic Volatility** (requires bars_1m)
   - 10m range < 0.1%: Low volatility

3. **Basic Option Chain** (requires option chain fetch)
   - IV too low: NIFTY < 10, BANKNIFTY < 13
   - Wide bid-ask spread: NIFTY > 2, BANKNIFTY > 3

### Data Fetched
- `bars_1m` - 1-minute candle series
- `option_chain_data` - Option chain for IV/spread checks

### Return Value
```ruby
{
  allowed: true/false,
  score: 0-11,
  reasons: ["reason1", "reason2", ...],
  option_chain_data: {...},  # For reuse in Phase 2
  bars_1m: CandleSeries      # For reuse in Phase 2
}
```

### Benefits
- ✅ **Fail Fast** - Blocks obvious bad conditions immediately
- ✅ **Saves Resources** - Avoids expensive Supertrend/ADX calculations
- ✅ **Single Option Chain Fetch** - Returns data for Phase 2 reuse

---

## Phase 2: Detailed Validation

### Purpose
Comprehensive validation with full market context after signal generation.

### Execution Point
Runs **after** signal generation and strike selection, but **before** `EntryGuard.try_enter()`.

### Checks Performed (11-Point Scoring System)

The engine uses an 11-point scoring system. If **3 or more** conditions trigger (score ≥ 3), the trade is blocked:

#### 1. Trend Weakness
- **ADX < 15**: Weak trend (threshold lowered from 18 to allow moderate trends)
- **DI overlap**: DI difference < 2 (threshold lowered from 3 for ranging markets)

#### 2. Market Structure Failures
- **No BOS in last 10m**: No Break of Structure detected
- **Inside opposite Order Block**: Price inside opposing order block
- **Inside opposing FVG**: Price inside opposing Fair Value Gap

#### 3. VWAP / AVWAP Filters
- **Near VWAP**: Price within ±0.1% of VWAP (magnet zone)
- **Trapped between VWAP & AVWAP**: Price stuck between VWAP and AVWAP

#### 4. Volatility Filters
- **10m range < 0.1%**: Low volatility
- **ATR decreasing**: Volatility compression (ATR downtrend)

#### 5. Option Chain Microstructure
- **Both CE & PE OI rising**: Writers controlling both sides
- **IV too low**: Below threshold (NIFTY < 10, BANKNIFTY < 13)
- **IV falling**: Implied volatility decreasing
- **Wide spreads**: Bid-ask spread too wide

#### 6. Candle Quality
- **High wick ratio**: Average wick ratio > 1.8

#### 7. Time Windows (with ADX context)
- **First 3 minutes**: 09:15-09:18
- **Lunch-time theta zone**: 11:20-13:30 (only if ADX < 20)
- **Post 3:05 PM**: After 15:05 (theta crush)

### Data Used
- **Reuses** `bars_1m` from Phase 1 (no duplicate fetch)
- **Reuses** `option_chain_data` from Phase 1 (no duplicate fetch)
- **Fetches** `bars_5m` (needed for ADX/DI calculations)
- **Uses** signal context (direction already determined)

### Benefits
- ✅ **Full Context** - Uses signal data already computed
- ✅ **No Duplicate Fetches** - Reuses Phase 1 data
- ✅ **Better Logging** - Distinguishes "blocked before signal" vs "blocked after signal"

---

## Scoring System

### Current Thresholds

| Condition | Points | Threshold |
|-----------|--------|-----------|
| ADX < 15 | +1 | ADX threshold: 15 (was 18) |
| DI overlap (<2 difference) | +1 | DI difference: 2 (was 3) |
| No BOS in last 10m | +1 | BOS detection in last 10 candles |
| Inside opposite OB | +1 | Order Block detection |
| Inside opposing FVG | +1 | Fair Value Gap detection |
| VWAP ±0.1% | +1 | VWAP magnet zone |
| Trapped between VWAP & AVWAP | +1 | VWAP/AVWAP trap |
| 10-min range < 0.1% | +1 | Low volatility |
| ATR decreasing | +1 | Volatility compression |
| Both CE & PE OI ↑ | +1 | Writers controlling |
| IV < threshold OR falling | +1 | IV: NIFTY < 10, BANKNIFTY < 13 |
| ATM spread wide | +1 | Spread: NIFTY > 2, BANKNIFTY > 3 |
| Wick ratio > 1.8 | +1 | High wick ratio |
| Bad time window | +1 | Time-based filters |

**Blocking Rule**: Score ≥ 3 → **NO BUY**

### Threshold Adjustments

The current implementation uses **relaxed thresholds** compared to initial design:
- **ADX**: 15 (was 18) - allows moderate trends through
- **DI difference**: 2 (was 3) - less strict for ranging markets
- **Lunch-time check**: Only blocks if ADX < 20 (strong trends can still be traded)

---

## Code Structure

### Phase 1 Method
```ruby
# app/services/signal/engine.rb
def quick_no_trade_precheck(index_cfg:, instrument:)
  # Fast checks only: time windows, basic volatility, basic option chain
  # Returns: {allowed, score, reasons, option_chain_data, bars_1m}
end
```

### Phase 2 Method
```ruby
# app/services/signal/engine.rb
def validate_no_trade_conditions(
  index_cfg:,
  instrument:,
  direction:,
  cached_option_chain: nil,  # From Phase 1
  cached_bars_1m: nil        # From Phase 1
)
  # Full validation with NoTradeEngine.validate()
  # Reuses cached data to avoid duplicate fetches
  # Returns: {allowed, score, reasons}
end
```

### Core Validation
```ruby
# app/services/entries/no_trade_engine.rb
class NoTradeEngine
  def self.validate(ctx)
    # Validates context and returns Result with allowed, score, reasons
    # Score < 3 → allowed, Score ≥ 3 → blocked
  end
end
```

### Context Builder
```ruby
# app/services/entries/no_trade_context_builder.rb
class NoTradeContextBuilder
  def self.build(index:, bars_1m:, bars_5m:, option_chain:, time:)
    # Builds OpenStruct with all validation fields:
    # - Trend: adx_5m, plus_di_5m, minus_di_5m
    # - Structure: bos_present, in_opposite_ob, inside_fvg
    # - VWAP: near_vwap, trapped_between_vwap
    # - Volatility: range_10m_pct, atr_downtrend
    # - Options: ce_oi_up, pe_oi_up, iv, iv_falling, spread_wide
    # - Candle: avg_wick_ratio
    # - Time: time, time_between
  end
end
```

---

## Performance Benefits

### Before (Single Phase After Signal)
- Option chain fetched: **2 times** (strike selection + validation)
- bars_1m fetched: **2 times** (signal + validation)
- Wasted computation: **100%** if blocked (all signal work done)

### After (Two-Phase)
- Option chain fetched: **1 time** (Phase 1, reused in Phase 2)
- bars_1m fetched: **1 time** (Phase 1, reused in Phase 2)
- Wasted computation: **0%** if Phase 1 blocks (no signal work done)

---

## Logging

### Phase 1 Block
```
[Signal] NO-TRADE pre-check blocked NIFTY: score=4/11, reasons=No BOS in last 10m; Low volatility: 10m range < 0.1%; IV too low (8.5 < 10); Wide bid-ask spread
```

### Phase 2 Block
```
[Signal] NO-TRADE detailed validation blocked NIFTY: score=5/11, reasons=Weak trend: ADX < 15; DI overlap: no directional strength; Inside opposite OB; VWAP magnet zone; Both CE & PE OI rising (writers controlling)
```

---

## Error Handling

Both phases use **fail-open** strategy:
- Errors in validation → allow trade to proceed
- Logs error for debugging
- Prevents No-Trade Engine from blocking trades due to technical issues

```ruby
rescue StandardError => e
  Rails.logger.error("[Signal] No-Trade Engine validation failed: #{e.class} - #{e.message}")
  # On error, allow trade (fail open) but log the error
  { allowed: true, score: 0, reasons: ["Validation error: #{e.message}"] }
end
```

---

## Volume-Independent Design

The No-Trade Engine is designed to work **without volume data**:
- Uses **typical price** (HLC/3) for VWAP calculations when volume unavailable
- Uses **price-based indicators** (ATR, range, structure) instead of volume
- Works with **option chain microstructure** (OI, IV, spreads) instead of volume

This makes it robust for:
- Low-volume periods
- Market data feed issues
- Historical backtesting (where volume may be unavailable)

---

## Configuration

### Current Defaults

No configuration needed - uses sensible defaults:

- **ADX threshold**: 15 (moderate trends allowed)
- **DI difference threshold**: 2 (less strict for ranging markets)
- **IV thresholds**: NIFTY=10, BANKNIFTY=13
- **Spread thresholds**: NIFTY=2, BANKNIFTY=3
- **Blocking threshold**: Score ≥ 3
- **Lunch-time ADX threshold**: 20 (strong trends can trade during lunch)

### Index-Specific Thresholds

- **NIFTY**: IV < 10, Spread > 2
- **BANKNIFTY**: IV < 13, Spread > 3

---

## Integration with Backtesting

The No-Trade Engine is integrated into `BacktestServiceWithNoTradeEngine` for historical validation:

- **Phase 1**: Simulated quick pre-check on historical data
- **Phase 2**: Full validation with historical context
- **Statistics**: Tracks Phase 1/Phase 2 block rates and reasons

---

## Future Enhancements

- [ ] Add configuration for thresholds (via `config/algo.yml`)
- [ ] Track OI/IV history for better detection
- [ ] Dashboard widget showing which rules triggered
- [ ] Diagnostic JSON log for debugging
- [ ] A/B testing framework for threshold optimization

---

## Related Documentation

- `BACKTEST_NO_TRADE_ENGINE.md` - Backtesting integration
- `COMPLETE_SIGNAL_FLOW.md` - Full signal generation flow
- `COMPLETE_TRADING_FLOW.md` - Complete trading system flow

