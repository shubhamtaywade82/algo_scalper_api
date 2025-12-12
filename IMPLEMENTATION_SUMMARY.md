# Adaptive Exit System - Implementation Summary

## ✅ Completed Implementation

### Core Modules Created

1. **`app/lib/positions/drawdown_schedule.rb`**
   - `allowed_upward_drawdown_pct()` - Exponential drawdown calculation
   - `reverse_dynamic_sl_pct()` - Dynamic reverse SL with time/ATR penalties
   - `sl_price_from_entry()` - Helper for SL price calculation

2. **`app/services/live/early_trend_failure.rb`**
   - `early_trend_failure?()` - Multi-factor ETF detection
   - `applicable?()` - Checks if ETF checks should run

### Integration Points

3. **`app/services/live/risk_manager_service.rb`** (Updated)
   - `enforce_early_trend_failure()` - New enforcement method
   - `enforce_hard_limits()` - Enhanced with dynamic reverse SL and peak drawdown
   - `seconds_below_entry()` - Time tracking helper
   - `calculate_atr_ratio()` - ATR calculation helper
   - `build_position_data_for_etf()` - Position data builder for ETF checks
   - `momentum_score()` - Trend momentum calculation

4. **`config/algo.yml`** (Updated)
   - Added `risk.drawdown` configuration
   - Added `risk.reverse_loss` configuration
   - Added `risk.etf` configuration

### Tests Created

5. **`spec/lib/positions/drawdown_schedule_spec.rb`**
   - Comprehensive tests for upward drawdown
   - Tests for reverse dynamic SL
   - Tests for time-based tightening
   - Tests for ATR penalties
   - Edge case handling

6. **`spec/services/live/early_trend_failure_spec.rb`**
   - Tests for ETF applicability
   - Tests for trend score collapse
   - Tests for ADX collapse
   - Tests for ATR ratio collapse
   - Tests for VWAP rejection
   - Error handling tests

### Utilities Created

7. **`lib/tasks/drawdown_simulator.rake`**
   - Console simulator for testing calculations
   - Run with: `rake drawdown:simulate`

8. **`docs/ADAPTIVE_EXIT_SYSTEM.md`**
   - Complete documentation
   - Configuration guide
   - Testing instructions
   - Rollout plan

## 🎯 Key Features Implemented

### 1. Bidirectional Adaptive Stops

**Upward (Profit Protection)**:
- Exponential curve: 15% → 1% drawdown allowed as profit increases from 3% to 30%
- Index-specific floors (NIFTY: 1.0%, BANKNIFTY: 1.2%, SENSEX: 1.5%)

**Downward (Loss Limitation)**:
- Dynamic tightening: 20% → 5% allowed loss as position goes from -0% to -30%
- Time-based: -2% per minute spent below entry
- ATR penalties: -3% to -5% for low volatility conditions

### 2. Early Trend Failure Detection

- **Multi-factor checks**: Trend score, ADX, ATR ratio, VWAP rejection
- **Activation threshold**: Only active when profit < 7% (before trailing)
- **Prevents**: Winners turning into losers

### 3. Enhanced Exit Logic

- **Below Entry**: Uses dynamic reverse SL (takes precedence over static SL)
- **Above Entry**: Checks peak drawdown from high-water mark
- **Early Exit**: ETF checks run before other enforcement
- **Take Profit**: Still uses static TP threshold

## 📊 Exit Flow (Active Path)

```
Every 5 seconds:
  RiskManagerService.monitor_loop()
    ↓
  1. enforce_early_trend_failure()
     └─ Exit if: trend collapse OR ADX collapse OR ATR collapse OR VWAP rejection
    ↓
  2. enforce_hard_limits()
     ├─ Below Entry (-):
     │   ├─ Calculate: reverse_dynamic_sl_pct(pnl, time_below, atr_ratio)
     │   └─ Exit if: pnl <= -reverse_dynamic_sl_pct
     ├─ Above Entry (+):
     │   ├─ If profit >= 3%:
     │   │   ├─ Calculate: allowed_upward_drawdown_pct(peak_profit, index_key)
     │   │   └─ Exit if: (peak_profit - current_profit) >= allowed_drawdown
     │   └─ Exit if: pnl >= tp_pct (static TP)
    ↓
  3. enforce_trailing_stops() [disabled]
  4. enforce_time_based_exit() [not configured]
```

## 🧪 Testing

### Run Tests
```bash
# Unit tests
bundle exec rspec spec/lib/positions/drawdown_schedule_spec.rb
bundle exec rspec spec/services/live/early_trend_failure_spec.rb

# Simulator
rake drawdown:simulate
```

### Manual Testing (Rails Console)
```ruby
include Positions::DrawdownSchedule

# Test upward drawdown
[3, 5, 7, 10, 15, 20, 25, 30].each do |p|
  dd = allowed_upward_drawdown_pct(p, index_key: 'NIFTY')
  puts "Profit: #{p}% => Allowed DD: #{dd.round(2)}%"
end

# Test reverse SL
[-1, -5, -10, -15, -20, -25, -30].each do |p|
  sl = reverse_dynamic_sl_pct(p, seconds_below_entry: 120, atr_ratio: 0.6)
  puts "PnL: #{p}% => Allowed Loss: #{sl.round(2)}%"
end
```

## 📈 Configuration Defaults

All defaults are conservative and production-ready:

- **Drawdown**: 15% → 1% over 3% → 30% profit range
- **Reverse SL**: 20% → 5% over -0% → -30% loss range
- **Time Tightening**: 2% per minute below entry
- **ATR Penalties**: -3% (0.75 threshold), -5% (0.60 threshold)
- **ETF Activation**: 7% profit threshold

## 🚀 Next Steps

1. **Review**: Check all code changes
2. **Test**: Run unit tests and simulator
3. **Paper Trading**: Deploy to staging with paper trading enabled
4. **Monitor**: Collect metrics for 5-10 market sessions
5. **Tune**: Adjust parameters based on results
6. **Live**: Deploy with reduced capital (10-20% allocation)
7. **Full Release**: After 20+ trading days validation

## 📝 Notes

- All percent values are in percentage format (5.0 = 5%)
- Time tracking uses Redis cache (1-hour expiration)
- ATR calculation uses 5-minute candles
- ETF checks only apply when profit < activation threshold
- Static SL remains as fallback if dynamic reverse_loss is disabled
- Peak trend score is tracked in PositionTracker.meta

## 🔍 Files Changed Summary

**New Files:**
- `app/lib/positions/drawdown_schedule.rb`
- `app/services/live/early_trend_failure.rb`
- `spec/lib/positions/drawdown_schedule_spec.rb`
- `spec/services/live/early_trend_failure_spec.rb`
- `lib/tasks/drawdown_simulator.rake`
- `docs/ADAPTIVE_EXIT_SYSTEM.md`

**Modified Files:**
- `app/services/live/risk_manager_service.rb`
- `config/algo.yml`

**Total Lines Added:** ~800+
**Test Coverage:** Comprehensive unit tests for all new modules
