# Testing Guide

This document covers the test suite, paper trading validation approach, and post-session analysis for the Algo Scalper API.

## Test Suite

### Running Tests

```bash
# Full test suite
bundle exec rspec

# Single spec file
bundle exec rspec spec/path/file_spec.rb

# Specific directory
bundle exec rspec spec/services/entries/

# With documentation format
bundle exec rspec --format documentation spec/services/signal/
```

### Test Structure

```
spec/
  models/              # Model specs (PositionTracker, Derivative, TradingSignal, etc.)
  services/
    signal/            # Signal::Engine, Signal::Scheduler specs
    entries/           # EntryGuard, guard pipeline specs
    live/              # RiskManagerService, UnifiedExitChecker, ExitEngine specs
    orders/            # Gateway specs
    risk/              # CircuitBreaker, risk rules specs
    market_context/    # RegimeComposer, MarketPermissionGate specs
    options/           # ChainAnalyzer, ChainSignalExtractor specs
  integration/         # End-to-end integration specs
  lib/
    positions/         # DrawdownSchedule, TrailingConfig specs
```

### Key Test Files

```bash
# Entry guard pipeline
bundle exec rspec spec/services/entries/entry_guard_pipeline_spec.rb
bundle exec rspec spec/services/entries/entry_guard_spec.rb

# Signal engine
bundle exec rspec spec/services/signal/engine_spec.rb

# Exit system
bundle exec rspec spec/services/live/unified_exit_checker_spec.rb
bundle exec rspec spec/services/live/risk_manager_service_trailing_spec.rb

# Drawdown calculations
bundle exec rspec spec/lib/positions/drawdown_schedule_spec.rb

# Guards
bundle exec rspec spec/services/entries/guards/expiry_week_power_trend_guard_spec.rb
bundle exec rspec spec/services/entries/guards/time_regime_guard_spec.rb
```

### Test Tooling

- **RSpec** — test framework
- **FactoryBot** — test data factories
- **VCR** — records/replays DhanHQ HTTP/WebSocket interactions
- **Timecop** — time manipulation for time-regime guards, time-stop tests

---

## Paper Trading Validation

The primary validation approach is running in `paper_trading.enabled: true` mode with `run_mode: exit_testing` or `entry_testing`. All market data is real (live DhanHQ WebSocket); only order execution is simulated.

### Quick Pre-Session Checks

```bash
# Verify paper trading enabled
grep -A 3 "paper_trading" config/algo.yml

# Verify run mode
grep "run_mode" config/algo.yml

# Verify risk parameters
grep -A 10 "^risk:" config/algo.yml
```

### During Session — Rails Console Queries

```ruby
# Active positions
PositionTracker.active.count

# Recent signals
TradingSignal.order(created_at: :desc).limit(10).pluck(:index_key, :direction, "metadata->>'adx_value'")

# Entry paths
TradingSignal.group("metadata->>'entry_path'").count

# Active position details
PositionTracker.active.each do |t|
  puts "#{t.order_no}: #{t.meta['index_key']} #{t.meta['direction']} entry=#{t.entry_price}"
end
```

### Log Monitoring

```bash
# Watch signal generation + entries + exits
tail -f log/development.log | grep -E "Signal|Entry|Exit|RiskManager|ERROR|FATAL"

# Watch only exits
tail -f log/development.log | grep -E "exit|Exit|ExitEngine"

# Watch guard pipeline blocks
tail -f log/development.log | grep "blocked"
```

### Post-Session Analysis

```ruby
# === Performance Summary ===
today = Date.today.beginning_of_day

# Total PnL
total_pnl = PositionTracker.exited.where("exited_at >= ?", today).sum(:last_pnl_rupees)
puts "Total PnL: ₹#{total_pnl.round(2)}"

# Exit path distribution
puts "\nExit Paths:"
PositionTracker.exited.where("exited_at >= ?", today)
  .group("meta->>'exit_path'").count
  .sort_by { |_, c| -c }
  .each { |path, count| puts "  #{path}: #{count}" }

# Entry path distribution
puts "\nEntry Paths:"
TradingSignal.where("created_at >= ?", today)
  .group("metadata->>'entry_path'").count
  .each { |path, count| puts "  #{path}: #{count}" }

# Exit path performance
puts "\nExit Path Performance:"
PositionTracker.exited.where("exited_at >= ?", today)
  .group("meta->>'exit_path'")
  .select(
    "meta->>'exit_path' as exit_path",
    "COUNT(*) as count",
    "AVG(last_pnl_rupees) as avg_pnl",
    "SUM(CASE WHEN last_pnl_rupees > 0 THEN 1 ELSE 0 END)::float / COUNT(*) * 100 as win_rate"
  )
  .each { |r| puts "  #{r.exit_path}: count=#{r.count} avg=₹#{r.avg_pnl.to_f.round(2)} win=#{r.win_rate.to_f.round(1)}%" }

# Entry strategy → exit path analysis
puts "\nStrategy → Exit Analysis:"
PositionTracker.exited.where("exited_at >= ?", today)
  .group("meta->>'entry_strategy'", "meta->>'exit_path'")
  .count
  .each { |(strategy, path), count| puts "  #{strategy} → #{path}: #{count}" }
```

---

## Testing Specific Exit Rules

### Early Trend Failure (ETF)

```ruby
# Check if ETF exits occurred
PositionTracker.exited.where("meta->>'exit_path' = ?", "early_trend_failure").count

# Review ETF exit details
PositionTracker.exited.where("meta->>'exit_path' = ?", "early_trend_failure")
  .each { |t| puts "#{t.order_no}: PnL=#{t.last_pnl_pct.round(4)} reason=#{t.meta['exit_reason']}" }
```

**Expected behavior**: ETF triggers only when `exit.early_exit.profit_threshold` not yet reached AND trend has reversed.

### Trailing Stop

```ruby
# Upward trailing exits (profit protection)
PositionTracker.exited.where("meta->>'exit_path' LIKE ?", "%upward%")
  .pluck(:order_no, "meta->>'peak_profit_pct'", :last_pnl_pct)

# Downward trailing exits (loss limitation)
PositionTracker.exited.where("meta->>'exit_path' LIKE ?", "%downward%")
  .pluck(:order_no, :last_pnl_pct, "meta->>'seconds_below_entry'")
```

### Drawdown Calculations (Manual Verification)

```ruby
# In Rails console — verify adaptive trailing math
# At 10% profit, how much drawdown is allowed?
include Positions::DrawdownSchedule
profit_pct = 0.10
allowed_dd = allowed_upward_drawdown_pct(profit_pct, index_key: 'NIFTY')
puts "At #{(profit_pct * 100).round(1)}% profit, allowed drawdown: #{(allowed_dd * 100).round(2)}%"

# At -10% loss, how much more loss is allowed (adaptive SL)?
loss_pct = -0.10
seconds_below = 120
atr_ratio = 0.75
allowed_loss = reverse_dynamic_sl_pct(loss_pct, seconds_below_entry: seconds_below, atr_ratio: atr_ratio)
puts "At #{(loss_pct.abs * 100).round(1)}% loss, #{seconds_below}s below entry: allowed=#{(allowed_loss * 100).round(2)}%"
```

### Circuit Breaker

```ruby
# Check status
Risk::CircuitBreaker.instance.tripped?
Risk::CircuitBreaker.instance.trip_reason

# Manual trip (testing)
Risk::CircuitBreaker.instance.trip!(reason: "Test trip")

# Reset
Risk::CircuitBreaker.instance.reset!
```

---

## Run Modes for Testing

See `docs/development/testing_profiles.md` for full details.

| Mode | Purpose | How to enable |
|------|---------|---------------|
| `production` | Full guards, real conditions | `run_mode: production` or omit |
| `exit_testing` | Many entries → test exit rules | `run_mode: exit_testing` or `RUN_MODE=exit_testing` |
| `entry_testing` | Relaxed guards → test entry pipeline | `run_mode: entry_testing` or `RUN_MODE=entry_testing` |

```bash
# Start in exit testing mode
RUN_MODE=exit_testing ENABLE_TRADING_SERVICES=true bundle exec rake trading:daemon

# Start in entry testing mode
RUN_MODE=entry_testing ENABLE_TRADING_SERVICES=true bundle exec rake trading:daemon
```

---

## Code Quality

```bash
# Lint
bundle exec rubocop

# Security scan
bin/brakeman --no-pager

# Complexity analysis
bundle exec rubycritic app/services/

# Dead method candidates
bundle exec rake code_health:debride
```

---

## Common Troubleshooting

### No entries firing

```ruby
# Check circuit breaker
Risk::CircuitBreaker.instance.tripped?

# Check edge failure detector
Live::EdgeFailureDetector.instance.entries_paused?(index_key: 'NIFTY')

# Recent signals (any blocked?)
TradingSignal.order(created_at: :desc).limit(5).pluck(:index_key, "metadata->>'block_reason'")

# Check guard blocks in logs
tail -f log/development.log | grep "blocked"
```

### Exit not triggering

```ruby
# Check if exit was requested
PositionTracker.active.pluck(:id, :exit_requested_at, :exit_sent_at)

# Check PnL cache
tracker = PositionTracker.active.first
Live::RedisPnlCache.instance.fetch_pnl(tracker.id)

# Check RiskManager running
Live::RiskManagerService.instance.running?
```

### LTP not updating

```ruby
# Check tick cache
Live::TickCache.fetch('IDX_I', '13')  # NIFTY
Live::TickCache.fetch('IDX_I', '25')  # BANKNIFTY

# Check WebSocket
Live::MarketFeedHub.instance.connected?
```
