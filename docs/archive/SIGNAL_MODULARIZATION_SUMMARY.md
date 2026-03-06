# Signal Generation Modularization - Summary

## Current State Analysis

### Signal Generation Entry Points

1. **Primary Path**: `Signal::Scheduler` → `evaluate_supertrend_signal()`
   - Uses `Signal::TrendScorer` if `enable_trend_scorer: true`
   - Falls back to `Signal::Engine.analyze_multi_timeframe()` if disabled

2. **Alternative Path**: `Signal::Engine.run_for()`
   - Supports strategy recommendations
   - Uses Supertrend + ADX analysis
   - Includes comprehensive validation

### Current Indicators Used

#### In TrendScorer (`app/services/signal/trend_scorer.rb`):

| Indicator | Period/Params | Location | Configurable? | Weight |
|-----------|---------------|----------|---------------|--------|
| RSI | 14 | `ind_score()` | ❌ No | 0-2 points |
| MACD | 12, 26, 9 | `ind_score()` | ❌ No | 0-2 points |
| ADX | 14 | `ind_score()` | ❌ No | 0-2 points |
| Supertrend | 10, 2.0 | `ind_score()` | ❌ No | 0-1 point |
| Price Action | N/A | `pa_score()` | ❌ No | 0-7 points |
| Multi-Timeframe | N/A | `mtf_score()` | ❌ No | 0-7 points |

#### In Engine (`app/services/signal/engine.rb`):

| Indicator | Period/Params | Location | Configurable? | Threshold |
|-----------|---------------|----------|---------------|-----------|
| Supertrend | 7, 3.0 | `analyze_timeframe()` | ✅ Yes (algo.yml) | N/A |
| ADX | 14 | `analyze_timeframe()` | ✅ Yes (algo.yml) | 18 (default) |

### Current Architecture Problems

1. **Hardcoded Values**
   - RSI period: 14 (hardcoded)
   - MACD periods: 12, 26, 9 (hardcoded)
   - ADX period: 14 (hardcoded)
   - Indicator thresholds: hardcoded in scoring logic
   - Indicator weights: hardcoded (RSI: 2pts, MACD: 2pts, etc.)

2. **No Toggle Mechanism**
   - Cannot disable individual indicators
   - Cannot disable price action scoring
   - Cannot disable multi-timeframe scoring
   - Must modify code to change indicator usage

3. **Tight Coupling**
   - `TrendScorer` directly calls `Indicators::Calculator`
   - Scoring logic embedded in `TrendScorer` class
   - Cannot swap indicator implementations
   - Cannot test indicators independently

4. **No Indicator Registry**
   - No central place to register indicators
   - Cannot add new indicators without modifying core classes
   - No way to define indicator combinations
   - No way to configure indicator relationships

5. **Mixed Responsibilities**
   - `TrendScorer` calculates AND scores indicators
   - `Engine` calculates AND decides direction
   - No separation between calculation and signal generation

6. **Limited Configuration**
   - Only Supertrend and ADX configurable via `algo.yml`
   - RSI, MACD parameters not configurable
   - Indicator weights not configurable
   - No per-index indicator customization

---

## Proposed Solution

### Architecture Components

1. **Indicators::Base** - Abstract base class for all indicators
2. **Indicators::Registry** - Singleton registry for indicator management
3. **Indicators::Composite** - Combines multiple indicators with configurable modes
4. **Individual Indicator Classes** - RSI, MACD, ADX, Supertrend, PriceAction

### Key Features

1. **Indicator Registry Pattern**
   - Central registration of all indicators
   - Enable/disable indicators via config
   - Per-indicator configuration
   - Per-index overrides

2. **Composite Indicator**
   - Multiple combination modes:
     - `weighted_sum`: Weighted average of indicator scores
     - `majority_vote`: Majority direction wins
     - `all_must_agree`: All indicators must agree
     - `any_one`: Any indicator can trigger signal
   - Configurable minimum confidence threshold
   - Configurable minimum number of agreeing indicators

3. **Configuration-Driven**
   - All indicators configurable via `algo.yml`
   - Per-index indicator overrides
   - Runtime configuration changes (no code deployment needed)

4. **Separation of Concerns**
   - Indicator calculation separate from scoring
   - Signal generation separate from indicator logic
   - Easy to test individual components

### Configuration Structure

```yaml
signals:
  indicators:
    enabled_indicators:
      - rsi
      - macd
      - adx
      - supertrend
      - price_action

    rsi:
      enabled: true
      period: 14
      weight: 0.2
      thresholds:
        strong_bullish: { min: 50, max: 70 }

    macd:
      enabled: true
      fast_period: 12
      slow_period: 26
      signal_period: 9
      weight: 0.2

    adx:
      enabled: true
      period: 14
      weight: 0.2
      min_strength: 18

    supertrend:
      enabled: true
      period: 7
      base_multiplier: 3.0
      weight: 0.3

    price_action:
      enabled: true
      weight: 0.1

    composite:
      mode: weighted_sum  # or: majority_vote, all_must_agree, any_one
      min_confidence: 0.6
      require_min_indicators: 2
```

### Benefits

1. **Flexibility**: Enable/disable indicators without code changes
2. **Extensibility**: Add new indicators by creating class and registering
3. **Maintainability**: Clear separation, easier debugging
4. **Observability**: Log individual indicator results
5. **Configuration-Driven**: Change behavior without deployment

---

## Implementation Plan

### Phase 1: Base Infrastructure (Week 1)
- [ ] Create `Indicators::Base` interface
- [ ] Create `Indicators::Registry` singleton
- [ ] Create `Indicators::Composite` class
- [ ] Add unit tests

### Phase 2: Extract Indicators (Week 2)
- [ ] Create `Indicators::Rsi` (extract from TrendScorer)
- [ ] Create `Indicators::Macd` (extract from TrendScorer)
- [ ] Create `Indicators::Adx` (extract from TrendScorer)
- [ ] Create `Indicators::SupertrendIndicator` (wrap existing)
- [ ] Create `Indicators::PriceAction` (extract from TrendScorer)
- [ ] Add unit tests for each indicator

### Phase 3: Configuration (Week 2)
- [ ] Add indicator configs to `algo.yml`
- [ ] Update `AlgoConfig` loader
- [ ] Add feature flag: `enable_modular_indicators`
- [ ] Add per-index indicator override support

### Phase 4: Refactor Signal Generation (Week 3)
- [ ] Update `TrendScorer.ind_score()` to use registry
- [ ] Update `TrendScorer.mtf_score()` to use registry
- [ ] Update `Engine.analyze_timeframe()` to use registry
- [ ] Add indicator result logging
- [ ] Add integration tests

### Phase 5: Testing & Validation (Week 4)
- [ ] Backtest with different indicator combinations
- [ ] Paper trading validation
- [ ] Performance testing
- [ ] Documentation updates

---

## Migration Strategy

1. **Backward Compatibility**: Keep existing logic as fallback
2. **Feature Flag**: `enable_modular_indicators` to toggle new system
3. **Gradual Migration**: Migrate one indicator at a time
4. **A/B Testing**: Run both systems in parallel
5. **Full Migration**: Remove legacy code after validation

---

## Example Use Cases

### Use Case 1: Enable Only RSI and ADX
```yaml
signals:
  indicators:
    enabled_indicators:
      - rsi
      - adx
```

### Use Case 2: Use Majority Vote Instead of Weighted Sum
```yaml
signals:
  indicators:
    composite:
      mode: majority_vote
      require_min_indicators: 3
```

### Use Case 3: Per-Index Indicator Override
```yaml
indices:
  - key: NIFTY
    indicators:
      rsi:
        period: 21  # Use longer period for NIFTY
```

### Use Case 4: Test New Indicator
```ruby
# 1. Create new indicator class
class Indicators::NewIndicator < Indicators::Base
  # ... implementation
end

# 2. Register in initializer
Indicators::Registry.instance.register(:new_indicator, Indicators::NewIndicator)

# 3. Enable in config
signals:
  indicators:
    enabled_indicators:
      - rsi
      - new_indicator
```

---

## Files to Create/Modify

### New Files
- `app/services/indicators/base.rb`
- `app/services/indicators/registry.rb`
- `app/services/indicators/composite.rb`
- `app/services/indicators/rsi_indicator.rb`
- `app/services/indicators/macd_indicator.rb`
- `app/services/indicators/adx_indicator.rb`
- `app/services/indicators/supertrend_indicator.rb`
- `app/services/indicators/price_action_indicator.rb`

### Modified Files
- `app/services/signal/trend_scorer.rb` - Use registry instead of direct calls
- `app/services/signal/engine.rb` - Use registry for indicator calculations
- `config/algo.yml` - Add indicator configuration section
- `config/initializers/algo_config.rb` - Load indicator configs

### Test Files
- `spec/services/indicators/base_spec.rb`
- `spec/services/indicators/registry_spec.rb`
- `spec/services/indicators/composite_spec.rb`
- `spec/services/indicators/rsi_indicator_spec.rb`
- `spec/services/indicators/macd_indicator_spec.rb`
- `spec/services/indicators/adx_indicator_spec.rb`
- `spec/services/indicators/supertrend_indicator_spec.rb`
- `spec/services/indicators/price_action_indicator_spec.rb`

---

## Success Criteria

1. ✅ All indicators can be enabled/disabled via config
2. ✅ Indicator parameters configurable via `algo.yml`
3. ✅ Multiple indicator combination modes supported
4. ✅ Per-index indicator overrides working
5. ✅ New indicators can be added without modifying core code
6. ✅ Backward compatibility maintained during migration
7. ✅ All tests passing
8. ✅ Performance impact < 10% overhead
9. ✅ Paper trading results match or exceed current system

---

## Next Steps

1. **Review**: Review this document and proposed architecture
2. **Approve**: Get approval for implementation plan
3. **Prioritize**: Decide which phase to start with
4. **Implement**: Begin Phase 1 (Base Infrastructure)
5. **Test**: Validate each phase before moving to next
6. **Deploy**: Gradual rollout with feature flags

---

## Questions to Consider

1. Should we support custom indicator weights per index?
2. Should we add indicator performance tracking/metrics?
3. Should we cache indicator calculations for performance?
4. Should we support indicator "groups" (e.g., momentum group, trend group)?
5. Should we add indicator confidence decay over time?
6. Should we support dynamic indicator selection based on market conditions?

---

## References

- Main Analysis: `docs/SIGNAL_GENERATION_MODULARIZATION.md`
- Flow Diagrams: `docs/SIGNAL_FLOW_DIAGRAMS.md`
- Current Code:
  - `app/services/signal/trend_scorer.rb`
  - `app/services/signal/engine.rb`
  - `app/services/signal/scheduler.rb`
  - `app/services/indicators/calculator.rb`






