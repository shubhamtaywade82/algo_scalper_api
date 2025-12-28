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
  exit_reason: "ADAPTIVE_TRAILING_STOP",
  exit_triggered_at: "2024-01-15T10:30:00Z"
}
```

### Complete Position Tracking (Entry + Exit)

Every `PositionTracker` now stores both entry and exit information:
```ruby
meta: {
  # Entry Information (set during position creation)
  entry_path: "supertrend_adx_1m_none",        # Entry path identifier
  entry_strategy: "supertrend_adx",            # Strategy used
  entry_strategy_mode: "supertrend_adx",       # Strategy mode
  entry_timeframe: "1m",                       # Timeframe used
  entry_confirmation_timeframe: nil,           # Confirmation timeframe (if any)
  entry_validation_mode: "aggressive",        # Validation mode
  
  # Exit Information (set when position exits)
  exit_path: "trailing_stop_adaptive_upward",  # Exit path identifier
  exit_direction: "upward",                     # upward/downward
  exit_type: "adaptive",                        # adaptive/fixed
  exit_reason: "ADAPTIVE_TRAILING_STOP",       # Human-readable reason
  exit_triggered_at: "2024-01-15T10:30:00Z"    # Exit timestamp
  
  # Other metadata
  index_key: "NIFTY",
  direction: "long_ce",
  placed_at: "2024-01-15T09:00:00Z"
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

### Analyze Entry Strategy → Exit Path Performance

**Now you can analyze directly from PositionTracker without joining TradingSignal**:
```ruby
# Performance by entry strategy and exit path
PositionTracker.exited.group("meta->>'entry_strategy'", "meta->>'exit_path'")
  .select(
    "meta->>'entry_strategy' as entry_strategy",
    "meta->>'exit_path' as exit_path",
    "COUNT(*) as count",
    "AVG(last_pnl_rupees) as avg_pnl",
    "AVG(last_pnl_pct) as avg_pnl_pct",
    "SUM(CASE WHEN last_pnl_rupees > 0 THEN 1 ELSE 0 END)::float / COUNT(*) * 100 as win_rate"
  )
  .order("entry_strategy", "exit_path")
  .each do |r|
    puts "#{r.entry_strategy} → #{r.exit_path}: Count=#{r.count}, Avg PnL=₹#{r.avg_pnl.round(2)}, Win Rate=#{r.win_rate.round(2)}%"
  end

# Which entry strategies work best with which exit paths?
PositionTracker.exited
  .where("meta->>'entry_strategy' = ?", "supertrend_adx")
  .group("meta->>'exit_path'")
  .average("last_pnl_rupees")
```

### Quick Position Analysis

**View complete entry + exit information for any position**:
```ruby
# Get all position details including entry/exit paths
PositionTracker.exited.select(
  :order_no,
  :symbol,
  :entry_price,
  :exit_price,
  :last_pnl_rupees,
  :last_pnl_pct,
  "meta->>'entry_path' as entry_path",
  "meta->>'entry_strategy' as entry_strategy",
  "meta->>'exit_path' as exit_path",
  "meta->>'exit_reason' as exit_reason"
).limit(10).each do |t|
  puts "#{t.order_no}: Entry=#{t.entry_strategy} (#{t.entry_path}) → Exit=#{t.exit_path} | PnL: ₹#{t.last_pnl_rupees.round(2)} (#{t.last_pnl_pct.round(2)}%)"
end
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

> **📖 For detailed testing instructions, see [TESTING_GUIDE.md](TESTING_GUIDE.md)**

### Test Files Created

**Unit Tests**:
- `spec/lib/positions/drawdown_schedule_spec.rb` - Core drawdown calculations
- `spec/lib/positions/drawdown_schedule_config_spec.rb` - Config variations (conservative/aggressive)
- `spec/services/live/early_trend_failure_spec.rb` - ETF detection logic
- `spec/services/live/early_trend_failure_config_spec.rb` - ETF config variations

**Integration Tests**:
- `spec/services/live/risk_manager_service_trailing_spec.rb` - Trailing stops integration
- `spec/integration/adaptive_exit_integration_spec.rb` - Full exit flow (conservative/balanced/aggressive)

**Test Coverage**:
- ✅ Upward drawdown calculations (all profit thresholds)
- ✅ Reverse SL calculations (all loss thresholds, time tightening, ATR penalties)
- ✅ ETF detection (all 4 conditions)
- ✅ Configuration variations (conservative, balanced, aggressive)
- ✅ Integration with `RiskManagerService`
- ✅ Edge cases (nil values, missing config, zero values)

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

# Run all adaptive exit tests
bundle exec rspec spec/lib/positions/ spec/services/live/early_trend_failure* spec/integration/adaptive_exit*
```

### Simulate Drawdowns

**Rake Task**: `lib/tasks/drawdown_simulator.rake`

```bash
rake drawdown:simulate
```

**What it does**:
- Simulates drawdown calculations for different profit levels
- Shows allowed drawdown % at each profit threshold
- Tests with different index keys (NIFTY, BANKNIFTY, SENSEX)
- Useful for understanding how the exponential curve works

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

**File**: `app/services/signal/engine.rb`

**Method Added**: `build_entry_path_identifier()` (lines 678-694)
```ruby
def build_entry_path_identifier(strategy_recommendation:, use_strategy_recommendations:, primary_tf:, effective_timeframe:, confirmation_tf:, enable_confirmation:)
  strategy_part = if use_strategy_recommendations && strategy_recommendation&.dig(:recommended)
                    strategy_recommendation[:strategy_name].downcase.gsub(/\s+/, '_')
                  else
                    'supertrend_adx'
                  end
  
  timeframe_part = effective_timeframe
  
  confirmation_part = if enable_confirmation && confirmation_tf.present?
                      confirmation_tf
                    else
                      'none'
                    end
  
  "#{strategy_part}_#{timeframe_part}_#{confirmation_part}"
end
```

**Integration** (lines 149-180):
- Called in `run_for()` method before creating `TradingSignal`
- Stored in `TradingSignal.metadata['entry_path']`
- Also stores: `strategy`, `strategy_mode`, `timeframe`, `confirmation_timeframe`, `validation_mode`

**Format**: `"strategy_timeframe_confirmation"` (e.g., `"supertrend_adx_1m_none"`)

---

### Exit Path Tracking Implementation

**File**: `app/services/live/risk_manager_service.rb`

**Method Added**: `track_exit_path()` (lines 952-971)
```ruby
def track_exit_path(tracker, exit_path, reason)
  meta = tracker.meta.is_a?(Hash) ? tracker.meta : {}
  direction = exit_path.include?('upward') ? 'upward' : (exit_path.include?('downward') ? 'downward' : nil)
  type = exit_path.include?('adaptive') ? 'adaptive' : (exit_path.include?('fixed') ? 'fixed' : nil)
  
  tracker.update!(meta: meta.merge(
    'exit_path' => exit_path,
    'exit_reason' => reason,
    'exit_direction' => direction,
    'exit_type' => type,
    'exit_triggered_at' => Time.current
  ))
rescue StandardError => e
  Rails.logger.error("[RiskManager] track_exit_path failed: #{e.class} - #{e.message}")
end
```

**Integration**: Called in all exit enforcement methods:
- `enforce_early_trend_failure()` (line 180)
- `enforce_trailing_stops()` (lines 241, 259)
- `enforce_hard_limits()` (lines 312, 321, 328)

**Stored Fields**:
- `exit_path`: Clear identifier (e.g., `"trailing_stop_adaptive_upward"`)
- `exit_direction`: `"upward"`, `"downward"`, or `nil`
- `exit_type`: `"adaptive"`, `"fixed"`, or `nil`
- `exit_reason`: Human-readable reason
- `exit_triggered_at`: Timestamp

---

### Early Trend Failure Implementation

**File**: `app/services/live/early_trend_failure.rb` (New Module)

**Main Method**: `early_trend_failure?(position_data)` (lines 18-77)
- Checks 4 conditions (any one triggers exit):
  1. **Trend Score Collapse**: Drop from peak ≥ `trend_score_drop_pct` (default 30%)
  2. **ADX Collapse**: ADX < `adx_collapse_threshold` (default 10)
  3. **ATR Ratio Collapse**: ATR ratio < `atr_ratio_threshold` (default 0.55)
  4. **VWAP Rejection**: Price crosses VWAP against position direction

**Helper Method**: `applicable?(pnl_pct, activation_profit_pct:)` (lines 80-85)
- Returns `true` if profit < activation threshold (default 7%)

**Integration** (in `RiskManagerService.enforce_early_trend_failure()`, lines 148-186):
```ruby
def enforce_early_trend_failure(exit_engine:)
  # ... config loading ...
  
  PositionTracker.active.find_each do |tracker|
    snapshot = pnl_snapshot(tracker)
    pnl_pct_value = snapshot[:pnl_pct].to_f * 100.0
    
    next unless Live::EarlyTrendFailure.applicable?(pnl_pct_value, activation_profit_pct: activation_profit)
    
    position_data = build_position_data_for_etf(tracker, snapshot, instrument)
    
    if Live::EarlyTrendFailure.early_trend_failure?(position_data)
      track_exit_path(tracker, "early_trend_failure", reason)
      dispatch_exit(exit_engine, tracker, reason)
    end
  end
end
```

**Helper Method**: `build_position_data_for_etf()` (lines 698-735)
- Builds data hash with: `trend_score`, `peak_trend_score`, `adx`, `atr_ratio`, `underlying_price`, `vwap`, `is_long?`

---

### Drawdown Schedule Implementation

**File**: `app/lib/positions/drawdown_schedule.rb` (New Module)

**Upward Drawdown Method**: `allowed_upward_drawdown_pct(profit_pct, index_key:)` (lines 19-38)
```ruby
def allowed_upward_drawdown_pct(profit_pct, index_key: nil)
  # Exponential curve: dd_start_pct → dd_end_pct as profit increases
  # Formula: dd_end + (dd_start - dd_end) * exp(-k * normalized_profit)
  # Applies index-specific floor
end
```

**Parameters**:
- `profit_pct`: Current profit (e.g., 10.0 for +10%)
- `index_key`: "NIFTY", "BANKNIFTY", "SENSEX" (for floor values)
- Returns: Allowed drawdown % (e.g., 8.5 means 8.5% drawdown allowed)
- Returns `nil` if profit < activation threshold

**Reverse SL Method**: `reverse_dynamic_sl_pct(pnl_pct, seconds_below_entry:, atr_ratio:)` (lines 45-82)
```ruby
def reverse_dynamic_sl_pct(pnl_pct, seconds_below_entry: 0, atr_ratio: 1.0)
  # Linear interpolation: max_loss_pct → min_loss_pct as loss deepens
  # Applies time-based tightening: -time_tighten_per_min per minute
  # Applies ATR penalties for low volatility
end
```

**Parameters**:
- `pnl_pct`: Negative value (e.g., -12.5 for -12.5% loss)
- `seconds_below_entry`: Time spent below entry (for time tightening)
- `atr_ratio`: Current ATR ratio (for volatility penalty)
- Returns: Allowed loss % (e.g., 12.5 means -12.5% loss allowed)

**Helper Method**: `sl_price_from_entry(entry_price, loss_pct)` (lines 86-88)
- Converts loss percentage to stop-loss price

---

### Bidirectional Trailing Implementation

#### Upward Trailing (Profit Protection)

**File**: `app/services/live/risk_manager_service.rb`

**Method**: `enforce_trailing_stops()` (lines 188-274)

**Flow**:
1. Check if profit ≥ activation threshold (default 3%)
2. Calculate allowed drawdown using `Positions::DrawdownSchedule.allowed_upward_drawdown_pct()`
3. Compare current profit vs peak profit
4. If drawdown exceeds allowed → exit with `"trailing_stop_adaptive_upward"`
5. Fallback to fixed threshold (`exit_drop_pct`) if adaptive unavailable
6. Breakeven lock at +5% profit (protection, not exit)

**Key Code** (lines 217-247):
```ruby
# Adaptive upward trailing
allowed_dd = Positions::DrawdownSchedule.allowed_upward_drawdown_pct(
  peak_profit_pct,
  index_key: tracker.index_key
)

if allowed_dd
  current_drawdown = peak_profit_pct - current_profit_pct
  if current_drawdown > allowed_dd
    track_exit_path(tracker, "trailing_stop_adaptive_upward", reason)
    dispatch_exit(exit_engine, tracker, reason)
  end
end
```

#### Downward Trailing (Loss Limitation)

**File**: `app/services/live/risk_manager_service.rb`

**Method**: `enforce_hard_limits()` (lines 282-340)

**Flow**:
1. Check if position is below entry (negative PnL)
2. Calculate `seconds_below_entry` (time tracking)
3. Calculate `atr_ratio` (volatility check)
4. Get allowed loss using `Positions::DrawdownSchedule.reverse_dynamic_sl_pct()`
5. Compare current loss vs allowed loss
6. If loss exceeds allowed → exit with `"stop_loss_adaptive_downward"`
7. Fallback to static SL (`sl_pct`) if adaptive unavailable

**Key Code** (lines 299-316):
```ruby
# Dynamic reverse SL (below entry)
if pnl_pct_value < 0
  seconds_below = seconds_below_entry(tracker)
  atr_ratio = calculate_atr_ratio(tracker)
  
  allowed_loss_pct = Positions::DrawdownSchedule.reverse_dynamic_sl_pct(
    pnl_pct_value,
    seconds_below_entry: seconds_below,
    atr_ratio: atr_ratio
  )
  
  if allowed_loss_pct && loss_pct > allowed_loss_pct
    track_exit_path(tracker, "stop_loss_adaptive_downward", reason)
    dispatch_exit(exit_engine, tracker, reason)
  end
end
```

---

### Helper Methods Added

**File**: `app/services/live/risk_manager_service.rb`

**`seconds_below_entry(tracker)`** (lines 768-791):
- Tracks time spent below entry price using Redis cache
- Cache key: `"position:below_entry:#{tracker.id}"`
- Returns seconds since first going below entry

**`calculate_atr_ratio(tracker)`** (lines 795-845):
- Calculates current ATR / recent ATR average
- Returns 1.0 if calculation fails (normal volatility)
- Used for volatility-based penalties

**`build_position_data_for_etf(tracker, snapshot, instrument)`** (lines 698-735):
- Builds data hash for ETF checks
- Includes: trend_score, peak_trend_score, adx, atr_ratio, underlying_price, vwap, is_long?

**`momentum_score(candles)`** (lines 738-750):
- Calculates momentum from recent candles
- Used for trend score calculation

**`calculate_atr(candles)`** (lines 677-695):
- Calculates Average True Range from candles
- Used for ATR ratio calculation

---

### Exit Enforcement Flow

**File**: `app/services/live/risk_manager_service.rb`

**Main Loop**: `monitor_loop()` (runs every 5 seconds)

**Order of Enforcement**:
1. **Early Trend Failure** (`enforce_early_trend_failure`) - Only if profit < 7%
2. **Hard Limits** (`enforce_hard_limits`) - Always checked
   - Dynamic Reverse SL (below entry)
   - Static SL (fallback)
   - Take Profit
3. **Trailing Stops** (`enforce_trailing_stops`) - Only if profit ≥ 3%
   - Adaptive Upward (exponential drawdown)
   - Fixed Upward (fallback)
   - Breakeven Lock
4. **Time-Based Exit** (`enforce_time_based_exit`) - If configured

**Each enforcement method**:
- Iterates through `PositionTracker.active`
- Checks conditions
- Calls `track_exit_path()` if exit triggered
- Calls `dispatch_exit()` to execute exit

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
