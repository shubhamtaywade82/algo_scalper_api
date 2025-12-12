# Trading System Guide - Entry & Exit Paths

## Overview

Complete guide to entry and exit paths, configuration, and analysis. All advanced features (bidirectional trailing, multiple strategies) are preserved with clear organization and tracking.

---

## Entry Paths

### Flow

```
Signal::Scheduler (every 30s)
  ↓
Signal::Engine.run_for()
  ├─→ Strategy Selection (recommended or supertrend_adx)
  ├─→ Timeframe Analysis (with/without confirmation)
  ├─→ Validation (conservative/balanced/aggressive)
  ├─→ Strike Selection
  └─→ EntryGuard.try_enter()
```

### Strategy Selection

**Path 1A: Strategy Recommendations** (if `use_strategy_recommendations: true`)
- Uses backtested strategy (SimpleMomentum, InsideBar, SupertrendAdx)
- Timeframe: Uses recommended strategy's timeframe
- Confirmation: Skipped

**Path 1B: Supertrend+ADX** (default)
- Traditional Supertrend + ADX analysis
- Timeframe: Primary timeframe (configurable)
- ADX Filter: Can be enabled/disabled

### Timeframe Confirmation

**Path 2A: With Confirmation** (if `enable_confirmation_timeframe: true`)
- Analyzes primary + confirmation timeframes
- Both must align

**Path 2B: Without Confirmation** (default)
- Uses primary timeframe only

### Validation Modes

**Path 3A: Conservative** - Strict validation
**Path 3B: Balanced** - Moderate validation
**Path 3C: Aggressive** - Minimal validation (current)

### Entry Tracking

Every entry tracks its path:
```ruby
metadata: {
  entry_path: "supertrend_adx_1m_none",  # Format: strategy_timeframe_confirmation
  strategy: "supertrend_adx",
  strategy_mode: "supertrend_adx",
  timeframe: "1m"
}
```

---

## Exit Paths

### Flow

```
RiskManagerService.monitor_loop() (every 5s)
  ↓
1. Early Trend Failure (if profit < 7%)
  ↓
2. Hard Limits (always checked)
   ├─→ Dynamic Reverse SL (below entry)
   ├─→ Static SL (fallback)
   └─→ Take Profit
  ↓
3. Trailing Stops (if profit ≥ 3%)
   ├─→ Adaptive Drawdown (upward)
   ├─→ Fixed Threshold (fallback)
   └─→ Breakeven Lock
  ↓
4. Time-Based Exit (if configured)
```

### Exit Types

**Path 1: Early Trend Failure**
- When: Profit < 7% (before trailing activates)
- Conditions: Trend collapse, ADX drop, ATR compression, VWAP rejection
- Tracked as: `"early_trend_failure"`

**Path 2: Hard Limits**
- **2A. Dynamic Reverse SL** (below entry): Adaptive tightening 20% → 5%
- **2B. Static SL** (fallback): Fixed -3%
- **2C. Take Profit**: Fixed +5%
- Tracked as: `"stop_loss_adaptive_downward"`, `"stop_loss_static_downward"`, `"take_profit"`

**Path 3: Trailing Stops** (Bidirectional)
- **3A. Adaptive Upward**: Exponential drawdown (15% → 1%)
- **3B. Fixed Upward**: Fixed 3% drop from HWM
- **3C. Breakeven Lock**: Locks at +5% (no exit, just protection)
- Tracked as: `"trailing_stop_adaptive_upward"`, `"trailing_stop_fixed_upward"`

**Path 4: Time-Based**
- When: Configured exit time reached
- Tracked as: `"time_based"`

### Exit Tracking

Every exit tracks its path:
```ruby
meta: {
  exit_path: "trailing_stop_adaptive_upward",  # Clear identifier
  exit_direction: "upward",                     # upward/downward
  exit_type: "adaptive",                        # adaptive/fixed
  exit_reason: "ADAPTIVE_TRAILING_STOP"
}
```

---

## Configuration

### Entry Config

```yaml
entry:
  strategy_mode: "supertrend_adx"  # or "recommended"
  strategies:
    supertrend_adx:
      timeframe: "1m"
      confirmation_enabled: false
      adx_min: 18
    recommended:
      enabled: false
  validation:
    mode: "aggressive"  # conservative/balanced/aggressive
```

### Exit Config

```yaml
exit:
  stop_loss:
    type: "adaptive"  # Bidirectional (upward + downward)
    adaptive:
      enabled: true
      max_loss_pct: 20.0
      min_loss_pct: 5.0
  take_profit: 5.0
  trailing:
    enabled: true
    upward:
      enabled: true
      type: "adaptive"
      activation_profit: 3.0
    downward:
      enabled: true
      type: "adaptive"
  early_exit:
    enabled: true
    profit_threshold: 7.0
```

---

## Analysis

### Compare Strategies

```ruby
# All entries by strategy
TradingSignal.group("metadata->>'strategy'").count

# Performance by strategy
TradingSignal.joins("LEFT JOIN position_trackers ON ...")
  .group("metadata->>'strategy'")
  .average("last_pnl_rupees")
```

### Compare Entry Paths

```ruby
# All entries by path
TradingSignal.group("metadata->>'entry_path'").count

# Performance by entry path
TradingSignal.joins("...")
  .group("metadata->>'entry_path'")
  .average("last_pnl_rupees")
```

### Compare Exit Paths

```ruby
# All exits by path
PositionTracker.exited.group("meta->>'exit_path'").count

# Performance by exit path
PositionTracker.exited.group("meta->>'exit_path'")
  .average("last_pnl_rupees")
```

### Compare Bidirectional Trailing

```ruby
# Upward trailing (profit protection)
PositionTracker.exited.where("meta->>'exit_path' LIKE ?", "%upward%")

# Downward trailing (loss limitation)
PositionTracker.exited.where("meta->>'exit_path' LIKE ?", "%downward%")

# Compare performance
PositionTracker.exited.group("meta->>'exit_direction'")
  .average("last_pnl_rupees")
```

---

## Current Active Configuration

### Entry (Active Path)

- Strategy: Supertrend+ADX
- Timeframe: 1m (no confirmation)
- Validation: Aggressive (IV rank only)
- Execution: Paper trading

### Exit (Active Paths)

- Early Trend Failure: ✅ Active (profit < 7%)
- Dynamic Reverse SL: ✅ Active (20% → 5% adaptive)
- Static SL: ✅ Active (fallback -3%)
- Take Profit: ✅ Active (+5%)
- Adaptive Trailing: ✅ Active (15% → 1% exponential)
- Fixed Trailing: ✅ Active (fallback 3%)
- Breakeven Lock: ✅ Active (+5%)

---

## Key Features

### ✅ Bidirectional Trailing

**Upward** (Profit Protection):
- Adaptive drawdown schedule: 15% → 1% as profit increases
- Activation: Profit ≥ 3%
- Index-specific floors

**Downward** (Loss Limitation):
- Adaptive reverse SL: 20% → 5% as loss deepens
- Time-based tightening: -2% per minute
- ATR penalties: -3% to -5%

### ✅ Multiple Strategies

- Strategy Recommendations (via StrategyRecommender)
- Supertrend+ADX (traditional)
- Simple Momentum (available)
- Inside Bar (available)

### ✅ All Exit Types

- Early Trend Failure
- Stop Loss (Static + Adaptive)
- Take Profit
- Trailing Stops (Adaptive + Fixed)
- Time-Based Exit

---

## Path Tracking

### Entry Path Format

`"strategy_timeframe_confirmation"`

Examples:
- `"supertrend_adx_1m_none"` - Supertrend+ADX, 1m, no confirmation
- `"recommended_5m_none"` - Strategy recommendations, 5m, no confirmation
- `"supertrend_adx_5m_5m"` - Supertrend+ADX, 5m primary, 5m confirmation

### Exit Path Format

`"type_direction"` or `"type"`

Examples:
- `"trailing_stop_adaptive_upward"` - Adaptive trailing, upward
- `"stop_loss_adaptive_downward"` - Adaptive reverse SL, downward
- `"take_profit"` - Take profit
- `"early_trend_failure"` - Early trend failure

---

## Testing

### Run Tests

```bash
# Drawdown schedule tests
bundle exec rspec spec/lib/positions/drawdown_schedule_spec.rb
bundle exec rspec spec/lib/positions/drawdown_schedule_config_spec.rb

# Early trend failure tests
bundle exec rspec spec/services/live/early_trend_failure_spec.rb
bundle exec rspec spec/services/live/early_trend_failure_config_spec.rb

# Trailing stops tests
bundle exec rspec spec/services/live/risk_manager_service_trailing_spec.rb

# Integration tests
bundle exec rspec spec/integration/adaptive_exit_integration_spec.rb
```

### Simulate Drawdowns

```bash
rake drawdown:simulate
```

---

## Files Reference

### Core Modules
- `app/lib/positions/drawdown_schedule.rb` - Drawdown calculations
- `app/services/live/early_trend_failure.rb` - ETF detection
- `app/services/signal/engine.rb` - Entry engine (with path tracking)
- `app/services/live/risk_manager_service.rb` - Exit management (with path tracking)

### Configuration
- `config/algo.yml` - Main configuration
- `config/algo_organized.yml` - Organized structure (reference)

### Tests
- `spec/lib/positions/drawdown_schedule_spec.rb`
- `spec/lib/positions/drawdown_schedule_config_spec.rb`
- `spec/services/live/early_trend_failure_spec.rb`
- `spec/services/live/early_trend_failure_config_spec.rb`
- `spec/services/live/risk_manager_service_trailing_spec.rb`
- `spec/integration/adaptive_exit_integration_spec.rb`

### Utilities
- `lib/tasks/drawdown_simulator.rake` - Drawdown simulator

---

## Quick Reference

### Entry Analysis
```ruby
TradingSignal.group("metadata->>'strategy'").count
TradingSignal.group("metadata->>'entry_path'").count
```

### Exit Analysis
```ruby
PositionTracker.exited.group("meta->>'exit_path'").count
PositionTracker.exited.where("meta->>'exit_path' LIKE ?", "%upward%")
PositionTracker.exited.where("meta->>'exit_path' LIKE ?", "%downward%")
```

### Configuration
```yaml
entry:
  strategy_mode: "supertrend_adx"
  strategies: { ... }
  validation: { mode: "aggressive" }

exit:
  stop_loss: { type: "adaptive" }
  trailing: { upward: {...}, downward: {...} }
```
