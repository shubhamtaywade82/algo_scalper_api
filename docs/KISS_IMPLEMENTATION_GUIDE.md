# KISS Implementation Guide

## Quick Start: Simplified System

### 1. Use Simple Config

Replace `config/algo.yml` with `config/algo_simple.yml` structure:

```yaml
trading:
  mode: "paper"
  preset: "balanced"

entry:
  strategy: "supertrend_adx"
  timeframe: "5m"
  adx_min: 18

exit:
  stop_loss: { type: "adaptive", value: 3.0 }
  take_profit: 5.0
  trailing: { enabled: true, type: "adaptive" }
  early_exit: { enabled: true }
```

### 2. Use Simple Engine

Replace `Signal::Engine` with `Signal::SimpleEngine`:

```ruby
# In Signal::Scheduler
Signal::SimpleEngine.run_for(index_cfg)  # Instead of Signal::Engine
```

### 3. Use Unified Exit Checker

Replace multiple exit methods with single unified check:

```ruby
# In RiskManagerService.monitor_loop
PositionTracker.active.find_each do |tracker|
  exit_result = Live::UnifiedExitChecker.check_exit_conditions(tracker)
  
  if exit_result
    dispatch_exit(exit_engine, tracker, exit_result[:reason])
    tracker.update(meta: tracker.meta.merge('exit_path' => exit_result[:path]))
  end
end
```

## Benefits

1. **One Entry Path**: Clear, simple flow
2. **One Exit Check**: Single method, easy to understand
3. **Clear Config**: Flat structure, easy to read
4. **Easy Analysis**: Track which path executed
5. **Easy Changes**: Change one place, not multiple

## Migration Steps

1. **Phase 1**: Add simple config alongside existing (no breaking changes)
2. **Phase 2**: Add SimpleEngine and UnifiedExitChecker (test in parallel)
3. **Phase 3**: Switch to simple system (update scheduler/risk manager)
4. **Phase 4**: Remove old complex code (after validation)

## Analysis Made Easy

### Track Entry Path
```ruby
# In TradingSignal
metadata: {
  strategy: "supertrend_adx",
  timeframe: "5m",
  entry_path: "supertrend_adx_5m"
}
```

### Track Exit Path
```ruby
# In PositionTracker
meta: {
  exit_path: "trailing_stop_adaptive",
  exit_reason: "TRAILING_STOP"
}
```

### Query Performance
```ruby
# All entries with strategy X
TradingSignal.where("metadata->>'strategy' = ?", "supertrend_adx")

# All exits via trailing stop
PositionTracker.where("meta->>'exit_path' = ?", "trailing_stop_adaptive")

# Compare strategies
TradingSignal.group("metadata->>'strategy'").count
```

## Example: Switching Presets

```yaml
# Change one line
trading:
  preset: "conservative"  # Was "balanced"
```

That's it! Everything else adjusts automatically.
