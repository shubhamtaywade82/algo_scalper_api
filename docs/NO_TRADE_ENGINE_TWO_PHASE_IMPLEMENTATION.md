# Two-Phase No-Trade Engine Implementation

## Overview

The No-Trade Engine is implemented as a **two-phase validation system** that optimizes for both speed and thoroughness:

1. **Phase 1: Quick Pre-Check** - Runs BEFORE expensive signal generation
2. **Phase 2: Detailed Validation** - Runs AFTER signal generation with full context

## Phase 1: Quick Pre-Check

### Execution Point
Runs immediately after fetching the instrument, **before** any signal generation.

### Checks Performed (Fast/Cheap Conditions)

1. **Time Windows** (no data fetch needed)
   - 09:15-09:18 (avoid first 3 minutes)
   - 11:20-13:30 (lunch-time theta zone)
   - After 15:05 (theta crush)

2. **Basic Structure** (requires bars_1m)
   - No BOS in last 10m

3. **Basic Volatility** (uses bars_1m)
   - 10m range < 0.1%

4. **Basic Option Chain** (requires option chain fetch)
   - IV too low (NIFTY < 10, BANKNIFTY < 13)
   - Wide bid-ask spread

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

## Phase 2: Detailed Validation

### Execution Point
Runs **after** signal generation, strike selection, but **before** `EntryGuard.try_enter()`.

### Checks Performed (Full Context)

Uses the complete `NoTradeEngine.validate()` with all 11 conditions:

1. **Trend Weakness**
   - ADX < 18
   - DI overlap (<3 difference)

2. **Market Structure**
   - No BOS in last 10m
   - Inside opposite Order Block
   - Inside opposing FVG

3. **VWAP/AVWAP**
   - Near VWAP (±0.1%)
   - Trapped between VWAP & AVWAP

4. **Volatility**
   - 10m range < 0.1%
   - ATR downtrend

5. **Option Chain Microstructure**
   - Both CE & PE OI rising
   - IV too low or falling
   - Wide spreads

6. **Candle Quality**
   - High wick ratio (>1.8)

7. **Time Windows**
   - Bad time windows (with ADX context)

### Data Used
- **Reuses** `bars_1m` from Phase 1 (no duplicate fetch)
- **Reuses** `option_chain_data` from Phase 1 (no duplicate fetch)
- **Fetches** `bars_5m` (needed for ADX/DI calculations)
- **Uses** signal context (ADX/DI already calculated)

### Benefits
- ✅ **Full Context** - Uses signal data already computed
- ✅ **No Duplicate Fetches** - Reuses Phase 1 data
- ✅ **Better Logging** - Distinguishes "blocked before signal" vs "blocked after signal"

## Execution Flow

```
Signal::Engine.run_for(index_cfg)
  ├─> Check market closed
  ├─> Fetch instrument
  │
  ├─> [PHASE 1] Quick No-Trade Pre-Check ← FAIL FAST
  │   ├─> Time windows check
  │   ├─> Fetch bars_1m
  │   ├─> Basic structure (BOS)
  │   ├─> Basic volatility (10m range)
  │   ├─> Fetch option chain
  │   ├─> Basic option chain (IV, spread)
  │   └─> Return: {allowed, score, reasons, option_chain_data, bars_1m}
  │
  ├─> [IF ALLOWED] Signal Generation
  │   ├─> Strategy recommendation (if enabled)
  │   ├─> Supertrend + ADX calculations
  │   ├─> Multi-timeframe analysis
  │   └─> Comprehensive validation
  │
  ├─> Pick option strikes
  │
  ├─> [PHASE 2] Detailed No-Trade Validation ← FULL CONTEXT
  │   ├─> Reuse bars_1m from Phase 1
  │   ├─> Fetch bars_5m (for ADX/DI)
  │   ├─> Reuse option_chain_data from Phase 1
  │   ├─> Build full context (ADX, DI, structure, VWAP, etc.)
  │   ├─> NoTradeEngine.validate(ctx)
  │   └─> Return: {allowed, score, reasons}
  │
  └─> [IF ALLOWED] EntryGuard.try_enter()
```

## Code Structure

### Phase 1 Method
```ruby
def quick_no_trade_precheck(index_cfg:, instrument:)
  # Fast checks only
  # Returns: {allowed, score, reasons, option_chain_data, bars_1m}
end
```

### Phase 2 Method
```ruby
def validate_no_trade_conditions(
  index_cfg:, 
  instrument:, 
  direction:,
  cached_option_chain: nil,  # From Phase 1
  cached_bars_1m: nil        # From Phase 1
)
  # Full validation with NoTradeEngine.validate()
  # Reuses cached data to avoid duplicate fetches
end
```

## Performance Benefits

### Before (Single Phase After Signal)
- Option chain fetched: **2 times** (strike selection + validation)
- bars_1m fetched: **2 times** (signal + validation)
- Wasted computation: **100%** if blocked (all signal work done)

### After (Two-Phase)
- Option chain fetched: **1 time** (Phase 1, reused in Phase 2)
- bars_1m fetched: **1 time** (Phase 1, reused in Phase 2)
- Wasted computation: **0%** if Phase 1 blocks (no signal work done)

## Logging

### Phase 1 Block
```
[Signal] NO-TRADE pre-check blocked NIFTY: score=4/11, reasons=No BOS in last 10m; Low volatility: 10m range < 0.1%; IV too low (8.5 < 10); Wide bid-ask spread
```

### Phase 2 Block
```
[Signal] NO-TRADE detailed validation blocked NIFTY: score=5/11, reasons=Weak trend: ADX < 18; DI overlap: no directional strength; Inside opposite OB; VWAP magnet zone; Both CE & PE OI rising (writers controlling)
```

## Error Handling

Both phases use **fail-open** strategy:
- Errors in validation → allow trade to proceed
- Logs error for debugging
- Prevents No-Trade Engine from blocking trades due to technical issues

## Configuration

No configuration needed - uses sensible defaults:
- **ADX threshold**: 18
- **IV thresholds**: NIFTY=10, BANKNIFTY=13
- **Spread thresholds**: NIFTY=2, BANKNIFTY=3
- **Blocking threshold**: Score ≥ 3

## Future Enhancements

- Add configuration for thresholds
- Track OI/IV history for better detection
- Dashboard widget showing which rules triggered
- Diagnostic JSON log for debugging
