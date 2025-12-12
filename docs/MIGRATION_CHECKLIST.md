# KISS Migration Checklist

## Phase 1: Add Simple Components (No Breaking Changes)

- [ ] Review `app/services/signal/simple_engine.rb`
- [ ] Review `app/services/live/unified_exit_checker.rb`
- [ ] Review `config/algo_simple.yml`
- [ ] Add simple config loader to `AlgoConfig`
- [ ] Test SimpleEngine in isolation
- [ ] Test UnifiedExitChecker in isolation

## Phase 2: Parallel Testing

- [ ] Run both systems in parallel (log which executed)
- [ ] Compare results for 1-2 trading sessions
- [ ] Verify simple system produces same/similar results
- [ ] Check performance tracking works correctly

## Phase 3: Switch to Simple System

- [ ] Update `Signal::Scheduler` to use `SimpleEngine`
- [ ] Update `RiskManagerService` to use `UnifiedExitChecker`
- [ ] Update config to use simple structure
- [ ] Test in paper trading for 5-10 sessions
- [ ] Monitor logs and metrics

## Phase 4: Cleanup (After Validation)

- [ ] Remove old complex entry code (if not needed)
- [ ] Remove old complex exit code (if not needed)
- [ ] Update documentation
- [ ] Update tests

---

## Quick Start (Testing)

### 1. Test Simple Engine

```ruby
# Rails console
index_cfg = { key: 'NIFTY', segment: 'IDX_I', sid: '13' }
Signal::SimpleEngine.run_for(index_cfg)
```

### 2. Test Unified Exit Checker

```ruby
# Rails console
tracker = PositionTracker.active.first
result = Live::UnifiedExitChecker.check_exit_conditions(tracker)
puts result.inspect
```

### 3. Compare Configs

```ruby
# Rails console
old_config = AlgoConfig.fetch[:signals]
new_config = AlgoConfig.fetch[:entry]
# Compare structures
```

---

## Rollback Plan

If issues arise:
1. Revert scheduler to use `Signal::Engine`
2. Revert risk manager to use old methods
3. Revert config to old structure
4. All old code remains functional
