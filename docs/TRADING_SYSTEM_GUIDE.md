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

### Current Config Structure (`config/algo.yml`)

The system uses the existing `config/algo.yml` structure. Key sections:

#### Entry Configuration

```yaml
signals:
  primary_timeframe: "1m"
  confirmation_timeframe: "5m"
  enable_confirmation_timeframe: false
  enable_adx_filter: false
  use_strategy_recommendations: false
  validation_mode: "aggressive"
  supertrend:
    period: 10
    base_multiplier: 2.0
    training_period: 50
    num_clusters: 3
    performance_alpha: 0.1
    multiplier_candidates: [1.5, 2.0, 2.5, 3.0, 3.5]
  adx:
    min_strength: 18
    confirmation_min_strength: 20
  validation_modes:
    conservative: { ... }
    balanced: { ... }
    aggressive: { ... }
```

#### Exit Configuration

```yaml
risk:
  sl_pct: 0.03        # Static SL fallback
  tp_pct: 0.05        # Take profit
  trail_step_pct: 0.03
  breakeven_after_gain: 0.05
  exit_drop_pct: 0.03  # Fixed trailing fallback
  
  # Upward exponential drawdown (bidirectional trailing)
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
  
  # Reverse (below entry) dynamic loss tightening (bidirectional trailing)
  reverse_loss:
    enabled: true
    max_loss_pct: 20.0
    min_loss_pct: 5.0
    loss_span_pct: 30.0
    time_tighten_per_min: 2.0
    atr_penalty_thresholds:
      - { threshold: 0.75, penalty_pct: 3.0 }
      - { threshold: 0.60, penalty_pct: 5.0
  
  # Early Trend Failure Exit
  etf:
    enabled: true
    activation_profit_pct: 7.0
    trend_score_drop_pct: 30.0
    adx_collapse_threshold: 10
    atr_ratio_threshold: 0.55
    confirmation_ticks: 2
```

### Organized Config Structure (Reference: `config/algo_organized.yml`)

For better organization, see `config/algo_organized.yml` which shows:
- Clear entry/exit sections
- Bidirectional trailing clearly separated (upward/downward)
- All features preserved but better organized

---

## Analysis

### Compare Strategies

```ruby
# Count entries by strategy
TradingSignal.group("metadata->>'strategy'").count
# => { "supertrend_adx" => 50, "simple_momentum" => 30, "inside_bar" => 20 }

# Average PnL by strategy
TradingSignal.joins("LEFT JOIN position_trackers ON position_trackers.meta->>'index_key' = trading_signals.index_key")
  .where("position_trackers.status = 'exited'")
  .group("trading_signals.metadata->>'strategy'")
  .average("position_trackers.last_pnl_rupees")

# Win rate by strategy
TradingSignal.joins("LEFT JOIN position_trackers ON ...")
  .where("position_trackers.status = 'exited'")
  .group("trading_signals.metadata->>'strategy'")
  .select(
    "trading_signals.metadata->>'strategy' as strategy",
    "COUNT(*) as total",
    "SUM(CASE WHEN position_trackers.last_pnl_rupees > 0 THEN 1 ELSE 0 END)::float / COUNT(*) * 100 as win_rate"
  )
```

### Compare Entry Paths

```ruby
# Count entries by path
TradingSignal.group("metadata->>'entry_path'").count
# => { "supertrend_adx_1m_none" => 30, "supertrend_adx_5m_5m" => 20, "recommended_5m_none" => 10 }

# Performance by entry path
TradingSignal.joins("LEFT JOIN position_trackers ON ...")
  .where("position_trackers.status = 'exited'")
  .group("trading_signals.metadata->>'entry_path'")
  .average("position_trackers.last_pnl_rupees")

# Compare different configurations
paths = ["supertrend_adx_1m_none", "supertrend_adx_5m_none", "supertrend_adx_5m_5m"]
paths.each do |path|
  signals = TradingSignal.where("metadata->>'entry_path' = ?", path)
  positions = PositionTracker.joins("INNER JOIN trading_signals ON ...")
    .where("trading_signals.metadata->>'entry_path' = ?", path)
    .exited
  
  puts "#{path}:"
  puts "  Entries: #{signals.count}"
  puts "  Exits: #{positions.count}"
  puts "  Avg PnL: ₹#{positions.average('last_pnl_rupees').round(2)}"
end
```

### Compare Exit Paths

```ruby
# Count exits by path
PositionTracker.exited.group("meta->>'exit_path'").count
# => { 
#   "trailing_stop_adaptive_upward" => 20,
#   "stop_loss_adaptive_downward" => 10,
#   "take_profit" => 15,
#   "early_trend_failure" => 5
# }

# Performance by exit path
PositionTracker.exited.group("meta->>'exit_path'")
  .average("last_pnl_rupees")

# Win rate by exit path
PositionTracker.exited.group("meta->>'exit_path'")
  .select(
    "meta->>'exit_path' as exit_path",
    "COUNT(*) as count",
    "AVG(last_pnl_rupees) as avg_pnl",
    "AVG(last_pnl_pct) as avg_pnl_pct",
    "SUM(CASE WHEN last_pnl_rupees > 0 THEN 1 ELSE 0 END)::float / COUNT(*) * 100 as win_rate"
  )
```

### Compare Bidirectional Trailing

```ruby
# Upward trailing (profit protection)
upward = PositionTracker.exited.where("meta->>'exit_path' LIKE ?", "%upward%")
puts "Upward Trailing:"
puts "  Count: #{upward.count}"
puts "  Avg PnL: ₹#{upward.average('last_pnl_rupees').round(2)}"
puts "  Avg Profit %: #{upward.average('last_pnl_pct').round(2)}%"
puts "  Win Rate: #{(upward.where('last_pnl_rupees > 0').count.to_f / upward.count * 100).round(2)}%"

# Downward trailing (loss limitation via reverse SL)
downward = PositionTracker.exited.where("meta->>'exit_path' LIKE ?", "%downward%")
puts "Downward Trailing:"
puts "  Count: #{downward.count}"
puts "  Avg PnL: ₹#{downward.average('last_pnl_rupees').round(2)}"
puts "  Avg Loss %: #{downward.average('last_pnl_pct').round(2)}%"

# Compare performance
PositionTracker.exited.group("CASE WHEN meta->>'exit_path' LIKE '%upward%' THEN 'upward' WHEN meta->>'exit_path' LIKE '%downward%' THEN 'downward' ELSE 'other' END")
  .average("last_pnl_rupees")
```

### Complete Strategy Performance Report

```ruby
# Full analysis: Entry strategy → Exit path → Performance
TradingSignal.joins("LEFT JOIN position_trackers ON position_trackers.meta->>'index_key' = trading_signals.index_key AND position_trackers.status = 'exited'")
  .where("position_trackers.id IS NOT NULL")
  .group("trading_signals.metadata->>'strategy'", "position_trackers.meta->>'exit_path'")
  .select(
    "trading_signals.metadata->>'strategy' as strategy",
    "position_trackers.meta->>'exit_path' as exit_path",
    "COUNT(*) as count",
    "AVG(position_trackers.last_pnl_rupees) as avg_pnl",
    "AVG(position_trackers.last_pnl_pct) as avg_pnl_pct",
    "SUM(CASE WHEN position_trackers.last_pnl_rupees > 0 THEN 1 ELSE 0 END)::float / COUNT(*) * 100 as win_rate"
  )
  .order("strategy", "exit_path")
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

**Upward Trailing** (Profit Protection):
- **Adaptive Drawdown Schedule**: Exponential curve (15% → 1%) as profit increases from 3% → 30%
- **Activation**: Only when profit ≥ 3% (`drawdown.activation_profit_pct`)
- **Index-Specific Floors**: NIFTY (1.0%), BANKNIFTY (1.2%), SENSEX (1.5%)
- **Calculation**: Uses `Positions::DrawdownSchedule.allowed_upward_drawdown_pct()`
- **Example**: At 10% profit, allowed drawdown ≈ 8%. If profit drops from 10% to 1% (9% drop), exit triggered.

**Downward Trailing** (Loss Limitation):
- **Adaptive Reverse SL**: Dynamic tightening (20% → 5%) as loss deepens from -0% → -30%
- **Time-Based Tightening**: -2% per minute spent below entry (`time_tighten_per_min`)
- **ATR Penalties**: -3% to -5% for low volatility conditions
- **Calculation**: Uses `Positions::DrawdownSchedule.reverse_dynamic_sl_pct()`
- **Example**: At -10% loss, allowed loss ≈ 15%. With 2 min below entry + low ATR, allowed loss ≈ 6%.

**How They Work Together**:
- **Above Entry**: Upward trailing protects profits (adaptive drawdown)
- **Below Entry**: Downward trailing limits losses (adaptive reverse SL)
- **Both Active**: System protects both directions simultaneously

### ✅ Multiple Strategies

**Strategy Recommendations** (if `use_strategy_recommendations: true`):
- Uses `StrategyRecommender.best_for_index()` to select best strategy
- Available strategies: SimpleMomentum, InsideBar, SupertrendAdx
- Uses recommended strategy's timeframe (5m or 15m)
- Skips confirmation timeframe (strategies are standalone)

**Supertrend+ADX** (default, if recommendations disabled):
- Traditional Supertrend + ADX analysis
- Configurable timeframe (currently 1m)
- ADX filter can be enabled/disabled
- Supports multi-timeframe confirmation

**Easy to Add**: New strategies can be added by implementing `generate_signal(index)` method

### ✅ All Exit Types

**Early Trend Failure** (ETF):
- **When**: Profit < 7% (before trailing activates)
- **Conditions**: Trend score drop ≥ 30%, ADX < 10, ATR ratio < 0.55, VWAP rejection
- **Purpose**: Exit early when trend shows signs of failure

**Stop Loss**:
- **Dynamic Reverse SL**: Adaptive tightening when below entry (20% → 5%)
- **Static SL**: Fixed -3% fallback
- **Bidirectional**: Works both above and below entry

**Take Profit**:
- Fixed +5% threshold
- Simple and clear

**Trailing Stops** (Bidirectional):
- **Adaptive Upward**: Exponential drawdown schedule (15% → 1%)
- **Fixed Upward**: 3% drop from HWM (fallback)
- **Breakeven Lock**: Locks at +5% (protection, not exit)

**Time-Based Exit**:
- Configurable exit time (e.g., 15:20)
- Currently not configured

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
# Count by strategy
TradingSignal.group("metadata->>'strategy'").count

# Count by entry path
TradingSignal.group("metadata->>'entry_path'").count

# Performance by strategy
TradingSignal.joins("...").group("metadata->>'strategy'").average("last_pnl_rupees")
```

### Exit Analysis
```ruby
# Count by exit path
PositionTracker.exited.group("meta->>'exit_path'").count

# Upward trailing exits
PositionTracker.exited.where("meta->>'exit_path' LIKE ?", "%upward%")

# Downward trailing exits
PositionTracker.exited.where("meta->>'exit_path' LIKE ?", "%downward%")

# Performance by exit path
PositionTracker.exited.group("meta->>'exit_path'").average("last_pnl_rupees")
```

### Configuration Examples

**Enable Strategy Recommendations**:
```yaml
signals:
  use_strategy_recommendations: true
```

**Enable Multi-Timeframe Confirmation**:
```yaml
signals:
  enable_confirmation_timeframe: true
  confirmation_timeframe: "5m"
```

**Switch Validation Mode**:
```yaml
signals:
  validation_mode: "balanced"  # or "conservative" or "aggressive"
```

**Enable/Disable Bidirectional Trailing**:
```yaml
risk:
  drawdown: { ... }        # Upward trailing config
  reverse_loss: { enabled: true }  # Downward trailing config
```

**Disable Early Trend Failure**:
```yaml
risk:
  etf:
    enabled: false
```

---

## Implementation Details

### Entry Path Tracking Implementation

Path tracking is added in `Signal::Engine`:
- `build_entry_path_identifier()` - Creates path identifier
- Stored in `TradingSignal.metadata['entry_path']`
- Format: `"strategy_timeframe_confirmation"`

### Exit Path Tracking Implementation

Path tracking is added in `RiskManagerService`:
- `track_exit_path()` - Stores exit path in tracker meta
- Stored in `PositionTracker.meta['exit_path']`
- Format: `"type_direction"` or `"type"`

### Bidirectional Trailing Implementation

**Upward** (in `enforce_trailing_stops()`):
- Uses `Positions::DrawdownSchedule.allowed_upward_drawdown_pct()`
- Checks peak profit vs current profit
- Tracks as: `"trailing_stop_adaptive_upward"` or `"trailing_stop_fixed_upward"`

**Downward** (in `enforce_hard_limits()`):
- Uses `Positions::DrawdownSchedule.reverse_dynamic_sl_pct()`
- Checks current loss vs allowed loss
- Tracks as: `"stop_loss_adaptive_downward"`

---

## Rollout & Testing

### Testing Strategy

1. **Unit Tests**: All calculation modules tested
2. **Integration Tests**: Full flow tested
3. **Paper Trading**: Test with paper trading enabled
4. **Live (Small Capital)**: Test with 10-20% allocation
5. **Full Release**: After validation

### Monitoring

Monitor these metrics:
- Entry path distribution
- Exit path distribution
- Bidirectional trailing performance (upward vs downward)
- Strategy performance comparison
- Win rates by path

---

## Feature Preservation Summary

### ✅ Everything Preserved from Previous Implementation

**Entry Features**:
- ✅ Strategy Recommendations (via `StrategyRecommender`)
- ✅ Supertrend+ADX strategy
- ✅ Multi-timeframe confirmation
- ✅ Validation modes (conservative/balanced/aggressive)
- ✅ All validation checks (IV rank, Theta risk, Trend confirmation)

**Exit Features**:
- ✅ Early Trend Failure (ETF) detection
- ✅ Dynamic Reverse SL (adaptive tightening below entry)
- ✅ Static SL (fallback)
- ✅ Take Profit
- ✅ Adaptive Upward Trailing (exponential drawdown schedule)
- ✅ Fixed Upward Trailing (fallback)
- ✅ Breakeven Locking
- ✅ Time-Based Exit (configurable)

**Bidirectional Trailing**:
- ✅ Upward: Adaptive drawdown schedule (15% → 1%)
- ✅ Downward: Adaptive reverse SL (20% → 5%)
- ✅ Both active simultaneously
- ✅ Index-specific floors
- ✅ Time-based tightening
- ✅ ATR penalties

**Tracking & Analysis**:
- ✅ Entry path tracking (`entry_path` in `TradingSignal.metadata`)
- ✅ Exit path tracking (`exit_path` in `PositionTracker.meta`)
- ✅ Strategy tracking
- ✅ Direction tracking (upward/downward)
- ✅ Type tracking (adaptive/fixed)
- ✅ Complete analysis queries

**Configuration**:
- ✅ All existing config parameters preserved
- ✅ Organized reference structure (`algo_organized.yml`)
- ✅ Backward compatible with existing `algo.yml`

**Testing**:
- ✅ Unit tests for all calculation modules
- ✅ Configuration variation tests
- ✅ Integration tests
- ✅ Drawdown simulator rake task

### What Changed (Organization Only)

**Structure Improvements**:
- ✅ Clear path tracking (entry_path, exit_path)
- ✅ Organized documentation (single comprehensive guide)
- ✅ Better analysis queries (with examples)
- ✅ Clearer configuration reference

**No Features Removed**:
- ❌ No strategies removed
- ❌ No exit types removed
- ❌ No configuration options removed
- ❌ No functionality removed

**Result**: All features preserved, better organized, easier to analyze and maintain.
