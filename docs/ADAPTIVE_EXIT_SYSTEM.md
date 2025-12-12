# Adaptive Exit System Implementation

## Overview

This document describes the implementation of a comprehensive bidirectional adaptive exit system with early trend failure detection, replacing the simple static stop-loss/take-profit approach.

## Components

### 1. Positions::DrawdownSchedule (`app/lib/positions/drawdown_schedule.rb`)

Pure calculation module for:
- **Upward exponential drawdown**: Tightens allowed drawdown as profit increases (15% → 1% over 3% to 30% profit range)
- **Reverse dynamic SL**: Tightens stop loss when position falls below entry (20% → 5% over -0% to -30% loss range)
- **Time-based tightening**: Additional tightening based on time spent below entry
- **ATR penalty**: Volatility-based adjustments

### 2. Live::EarlyTrendFailure (`app/services/live/early_trend_failure.rb`)

Early exit detection module that triggers exits when:
- **Trend score collapse**: 30%+ drop from peak trend score
- **ADX collapse**: ADX falls below threshold (default: 10)
- **ATR ratio collapse**: Volatility compression detected
- **VWAP rejection**: Price moves against position direction relative to VWAP

### 3. RiskManagerService Updates

Enhanced `enforce_hard_limits` method now:
- Uses dynamic reverse SL instead of static SL for positions below entry
- Checks upward peak drawdown for profitable positions
- Integrates Early Trend Failure checks
- Tracks time spent below entry price
- Calculates ATR ratios for volatility adjustments

## Configuration

### New Config Parameters (`config/algo.yml`)

```yaml
risk:
  # Upward exponential drawdown
  drawdown:
    activation_profit_pct: 3.0
    profit_min: 3.0
    profit_max: 30.0
    dd_start_pct: 15.0
    dd_end_pct: 1.0
    exponential_k: 3.0
    index_floors:
      NIFTY: 1.0
      BANKNIFTY: 1.2
      SENSEX: 1.5

  # Reverse (below entry) dynamic loss tightening
  reverse_loss:
    enabled: true
    max_loss_pct: 20.0
    min_loss_pct: 5.0
    loss_span_pct: 30.0
    time_tighten_per_min: 2.0
    atr_penalty_thresholds:
      - { threshold: 0.75, penalty_pct: 3.0 }
      - { threshold: 0.60, penalty_pct: 5.0 }

  # Early Trend Failure Exit
  etf:
    enabled: true
    activation_profit_pct: 7.0
    trend_score_drop_pct: 30.0
    adx_collapse_threshold: 10
    atr_ratio_threshold: 0.55
    confirmation_ticks: 2
```

## Exit Flow

```
Every 5 seconds:
  RiskManagerService.monitor_loop()
    ↓
  1. enforce_early_trend_failure()
     ├─ Check if pnl < activation_profit_pct
     ├─ Build position_data (trend_score, ADX, ATR, VWAP)
     └─ Trigger exit if ETF conditions met
    ↓
  2. enforce_hard_limits()
     ├─ Below Entry:
     │   ├─ Calculate dynamic_reverse_sl_pct (based on loss, time, ATR)
     │   └─ Exit if pnl <= -dynamic_reverse_sl_pct
     ├─ Above Entry:
     │   ├─ Check peak drawdown (if profit >= 3%)
     │   └─ Exit if (peak_profit - current_profit) >= allowed_drawdown
     └─ Take Profit: Exit if pnl >= tp_pct
    ↓
  3. enforce_trailing_stops() [disabled in current config]
  4. enforce_time_based_exit() [not configured]
```

## Key Features

### Bidirectional Adaptive Stops

1. **Upward (Profit Protection)**:
   - Starts at 15% allowed drawdown when profit = 3%
   - Exponentially tightens to 1% when profit = 30%
   - Index-specific floors prevent over-tightening

2. **Downward (Loss Limitation)**:
   - Starts at 20% allowed loss when just below entry
   - Tightens to 5% when loss reaches -30%
   - Time-based tightening: -2% per minute below entry
   - ATR penalties: -3% to -5% for low volatility

### Early Trend Failure Detection

- **Activation**: Only active when profit < 7% (before trailing kicks in)
- **Multi-factor**: Checks trend score, ADX, ATR, and VWAP
- **Early exit**: Prevents winners from turning into losers

## Testing

### Unit Tests

- `spec/lib/positions/drawdown_schedule_spec.rb`: Tests drawdown calculations
- `spec/services/live/early_trend_failure_spec.rb`: Tests ETF detection

### Console Simulator

```bash
rake drawdown:simulate
```

Shows drawdown schedules and reverse SL calculations for various scenarios.

### Manual Testing

```ruby
# Rails console
include Positions::DrawdownSchedule

# Test upward drawdown
[3, 5, 7, 10, 15, 20, 25, 30].each do |p|
  puts "profit=#{p}% => dd=#{allowed_upward_drawdown_pct(p, index_key: 'NIFTY')}%"
end

# Test reverse SL
[-1, -5, -10, -15, -20, -25, -30].each do |p|
  puts "pnl=#{p}% => reverse_sl=#{reverse_dynamic_sl_pct(p, seconds_below_entry: 120, atr_ratio: 0.6)}%"
end
```

## Metrics to Monitor

- `drawdown_exit_count` (tags: index, reason)
- `reverse_sl_update_count`
- `early_trend_failure_exit_count`
- `avg_sl_at_exit`
- `avg_pnl_at_exit`
- `time_to_exit_from_activation`
- `positions_in_reverse_mode`

## Rollout Plan

1. **Local Testing**: Run unit tests and simulator
2. **Paper Trading**: Deploy to staging with `paper_trading.enabled: true`
3. **Tuning**: Adjust parameters based on 5-10 market sessions
4. **Live (Reduced Capital)**: Enable on 10-20% allocation
5. **Full Release**: After 20+ trading days of paper + 2-3 live sessions

## Configuration Tuning

### Conservative (Safer)
- `dd_start_pct: 10.0` (tighter upward protection)
- `max_loss_pct: 15.0` (tighter reverse SL)
- `min_loss_pct: 3.0` (very tight floor)

### Aggressive (More Room)
- `dd_start_pct: 20.0` (more drawdown allowed)
- `max_loss_pct: 25.0` (wider reverse SL)
- `min_loss_pct: 7.0` (looser floor)

## Files Changed

1. `app/lib/positions/drawdown_schedule.rb` (new)
2. `app/services/live/early_trend_failure.rb` (new)
3. `app/services/live/risk_manager_service.rb` (updated)
4. `config/algo.yml` (updated)
5. `spec/lib/positions/drawdown_schedule_spec.rb` (new)
6. `spec/services/live/early_trend_failure_spec.rb` (new)
7. `lib/tasks/drawdown_simulator.rake` (new)

## Notes

- All calculations use percent values (e.g., 5.0 = 5%)
- Time tracking uses Redis cache with 1-hour expiration
- ATR calculation uses 5-minute candles (configurable)
- ETF checks only apply before trailing activation (profit < 7%)
- Static SL (`sl_pct`) remains as fallback if dynamic reverse_loss is disabled
