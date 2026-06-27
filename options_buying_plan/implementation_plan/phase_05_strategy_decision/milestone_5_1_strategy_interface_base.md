# Milestone 5.1: Strategy Interface & Base Classes

**Phase:** 5 — Strategy & Decision Layer  
**Goal:** Plugin architecture where strategies are interchangeable.  
**Estimated Tasks:** 12

---

## Tasks

### 1. Create BaseStrategy Class
- [ ] Create `app/strategies/base_strategy.rb`
- [ ] Abstract interface (use `abstract_method` or raise `NotImplementedError`):
  - `should_enter?(context) -> StrategySignal`
  - `should_exit?(position, context) -> ExitSignal`
  - `confidence(context) -> Float (0-100)`
  - `required_features -> Array<Symbol>`
  - `parameters -> Hash` (default parameters)
- [ ] Common functionality:
  - Parameter validation
  - Logging with strategy name
  - Performance tracking hooks
  - Version attribute for backtesting consistency

### 2. Implement should_enter? Interface
- [ ] Input: `EntryContext` with:
  - `market_context` (from MarketContextEngine)
  - `regime` (from MarketRegimeEngine)
  - `structure` (from MarketStructureEngine)
  - `momentum` (from MomentumEngine)
  - `liquidity` (from LiquidityEngine)
  - `option_intelligence` (from OptionIntelligenceEngine)
  - `strike_analysis` (from StrikeSelectionEngine)
  - `current_time`, `account_state`
- [ ] Output: `StrategySignal` with:
  - `signal` (:long, :short, :none)
  - `direction` (:bullish, :bearish)
  - `confidence` (0-100)
  - `setup_type` (symbol)
  - `metadata` (hash for debugging)

### 3. Implement should_exit? Interface
- [ ] Input: `ExitContext` with:
  - `position` (current position with entry details)
  - All engine outputs (same as entry)
  - `holding_time`, `unrealized_pnl`, `mfe`, `mae`
- [ ] Output: `ExitSignal` with:
  - `should_exit` (boolean)
  - `reason` (:target_hit, :stop_loss, :trailing_stop, :structure_break, :time_exit, :iv_change, :momentum_loss, :emergency)
  - `exit_type` (:full, :partial, :scale_out)
  - `target_price` (if partial)
  - `urgency` (:normal, :fast, :immediate)

### 4. Implement confidence Interface
- [ ] Input: same as `should_enter?`
- [ ] Output: Float 0-100
- [ ] Base implementation: weighted average of engine scores
- [ ] Override in strategies for strategy-specific confidence

### 5. Implement required_features Interface
- [ ] Return array of feature symbols required from FeatureStore
- [ ] Example: `[:ema_21, :vwap, :atr_14, :rsi_14, :delta, :gamma, :iv_rank, :oi_flow]`
- [ ] Used by StrategyValidator to check data availability

### 6. Create StrategyRegistry
- [ ] Create `app/strategies/strategy_registry.rb`
- [ ] Register strategies: `StrategyRegistry.register(:orb, ORBStrategy)`
- [ ] Discover: `StrategyRegistry.all`, `StrategyRegistry.get(name)`
- [ ] Auto-load from `app/strategies/` directory
- [ ] Metadata: name, version, description, parameters, required_features

### 7. Add StrategyValidator
- [ ] Create `app/strategies/strategy_validator.rb`
- [ ] Validate:
  - All required features available in FeatureStore
  - Parameters within allowed ranges
  - Strategy version compatible with current engine versions
  - No circular dependencies
- [ ] Run on strategy registration and before each trading session

### 8. Implement StrategyContext
- [ ] Create `app/strategies/strategy_context.rb`
- [ ] Immutable value object passed to all strategy methods
- [ ] Contains: all engine outputs, account state, time, configuration
- [ ] Factory: `StrategyContext.build(engines_output, account, time)`
- [ ] Serialization: `to_h` for logging/AI context

### 9. Create StrategyResult
- [ ] Create `app/strategies/strategy_result.rb`
- [ ] Unified result for entry and exit:
  - `signal` (:long, :short, :none, :exit)
  - `direction` (:bullish, :bearish)
  - `confidence` (0-100)
  - `setup_type` / `exit_reason`
  - `metadata` (hash)
  - `timestamp`
- [ ] Methods: `actionable?`, `entry?`, `exit?`

### 10. Add StrategyLoader
- [ ] Create `app/strategies/strategy_loader.rb`
- [ ] Load strategies from `app/strategies/**/*.rb`
- [ ] Validate each with StrategyValidator
- [ ] Return enabled strategies for current environment
- [ ] Support strategy weighting for ensemble

### 11. Implement Strategy Versioning
- [ ] Add `version` attribute to BaseStrategy (semver)
- [ ] Store version in `trade_setups` and `trades` tables
- [ ] Backtest runner uses specific version
- [ ] Migration path for parameter changes

### 12. Write Tests for Strategy Interface Compliance
- [ ] Create `spec/strategies/base_strategy_spec.rb`
- [ ] Shared examples for all strategies:
  - Implements all required methods
  - Returns correct result types
  - Handles missing features gracefully
  - Parameter validation works
  - Version attribute present
- [ ] Test StrategyRegistry discovery and loading
- [ ] Test StrategyValidator catches missing features

---

## Acceptance Criteria
- [ ] BaseStrategy defines clear interface with all 5 methods
- [ ] StrategyRegistry auto-discovers strategies in `app/strategies/`
- [ ] StrategyValidator prevents strategies with missing features from running
- [ ] StrategyContext carries all needed data immutably
- [ ] StrategyResult unifies entry/exit signals
- [ ] Versioning enables backtest reproducibility
- [ ] All strategies pass interface compliance tests

---

## Notes
- Strategies are PURE - no side effects, no external I/O
- All data comes through StrategyContext
- Strategies can be combined in ensemble (Phase 5.4)
- Parameters configurable per environment (AppConfig)
- StrategyLoader enables/disables per environment
- Consider `dry-struct` for StrategyContext/Result for type safety