# Spec File Analysis - Needed vs. Not Needed

**Analysis Date**: Current
**Total Spec Files**: 113
**Purpose**: Identify which specs test active code vs. deprecated/removed features

---

## ✅ **SPECS TO KEEP** (Active Implementation)

### **Models** (All Keep)
- ✅ `spec/models/instrument_spec.rb` - Active model
- ✅ `spec/models/position_tracker_spec.rb` - Active model
- ✅ `spec/models/candle_series_spec.rb` - Active model
- ✅ `spec/models/derivative_spec.rb` - Active model
- ✅ `spec/models/watchlist_item_spec.rb` - Active model
- ✅ `spec/models/concerns/instrument_helpers_spec.rb` - Active concern
- ✅ `spec/models/concerns/candle_extension_spec.rb` - Active concern

### **Live Services** (All Keep)
- ✅ `spec/services/live/market_feed_hub_spec.rb` - Active service
- ✅ `spec/services/live/market_feed_hub_market_close_spec.rb` - Active service
- ✅ `spec/services/live/market_feed_hub_subscription_spec.rb` - Active service
- ✅ `spec/services/live/risk_manager_service_spec.rb` - Active service
- ✅ `spec/services/live/risk_manager_service_phase2_spec.rb` - Active service
- ✅ `spec/services/live/risk_manager_service_phase3_spec.rb` - Active service
- ✅ `spec/services/live/risk_manager_service_market_close_spec.rb` - Active service
- ✅ `spec/services/live/risk_manager_active_cache_spec.rb` - Active service
- ✅ `spec/services/live/risk_manager_underlying_spec.rb` - Active service
- ✅ `spec/services/live/exit_engine_spec.rb` - Active service
- ✅ `spec/services/live/trailing_engine_spec.rb` - Active service
- ✅ `spec/services/live/pnl_updater_service_spec.rb` - Active service
- ✅ `spec/services/live/pnl_updater_service_market_close_spec.rb` - Active service
- ✅ `spec/services/live/paper_pnl_refresher_market_close_spec.rb` - Active service
- ✅ `spec/services/live/order_update_hub_spec.rb` - Active service
- ✅ `spec/services/live/order_update_handler_spec.rb` - Active service
- ✅ `spec/services/live/position_sync_service_spec.rb` - Active service
- ✅ `spec/services/live/reconciliation_service_market_close_spec.rb` - Active service
- ✅ `spec/services/live/underlying_monitor_spec.rb` - Active service
- ✅ `spec/services/live/daily_limits_spec.rb` - Active service
- ✅ `spec/services/live/demand_driven_services_spec.rb` - Active service

### **Risk Rules** (All Keep - All Active)
- ✅ `spec/services/risk/rules/base_rule_spec.rb` - Base class
- ✅ `spec/services/risk/rules/rule_engine_spec.rb` - Active engine
- ✅ `spec/services/risk/rules/rule_factory_spec.rb` - Active factory
- ✅ `spec/services/risk/rules/rule_context_spec.rb` - Active context
- ✅ `spec/services/risk/rules/rule_result_spec.rb` - Active result
- ✅ `spec/services/risk/rules/stop_loss_rule_spec.rb` - Active rule
- ✅ `spec/services/risk/rules/take_profit_rule_spec.rb` - Active rule
- ✅ `spec/services/risk/rules/secure_profit_rule_spec.rb` - Active rule
- ✅ `spec/services/risk/rules/time_based_exit_rule_spec.rb` - Active rule
- ✅ `spec/services/risk/rules/session_end_rule_spec.rb` - Active rule
- ✅ `spec/services/risk/rules/peak_drawdown_rule_spec.rb` - Active rule
- ✅ `spec/services/risk/rules/trailing_stop_rule_spec.rb` - Active rule
- ✅ `spec/services/risk/rules/underlying_exit_rule_spec.rb` - Active rule
- ✅ `spec/services/risk/rules/bracket_limit_rule_spec.rb` - Active rule
- ✅ `spec/services/risk/rules/data_freshness_spec.rb` - Active rule
- ✅ `spec/services/risk/rules/edge_cases_spec.rb` - Active tests
- ✅ `spec/services/risk/rules/integration_scenarios_spec.rb` - Active tests
- ✅ `spec/services/risk/rules/trailing_activation_spec.rb` - Tests RuleContext method (keep)

### **Signal Services** (All Keep)
- ✅ `spec/services/signal/engine_spec.rb` - Active engine
- ✅ `spec/services/signal/engine_market_close_spec.rb` - Active engine
- ✅ `spec/services/signal/engine_multi_indicator_spec.rb` - Active engine
- ✅ `spec/services/signal/engine_no_trade_integration_spec.rb` - Active engine
- ✅ `spec/services/signal/scheduler_spec.rb` - Active scheduler
- ✅ `spec/services/signal/scheduler_market_close_spec.rb` - Active scheduler
- ✅ `spec/services/signal/scheduler_direction_first_spec.rb` - Active scheduler
- ✅ `spec/services/signal/trend_scorer_spec.rb` - Active service
- ✅ `spec/services/signal/index_selector_spec.rb` - Active service
- ✅ `spec/services/signal/engines/base_engine_spec.rb` - Base class
- ✅ `spec/services/signal/engines/open_interest_buying_engine_spec.rb` - Active engine

### **Entries Services** (All Keep)
- ✅ `spec/services/entries/entry_guard_spec.rb` - Active service
- ✅ `spec/services/entries/entry_guard_integration_spec.rb` - Active service
- ✅ `spec/services/entries/entry_guard_autowire_spec.rb` - Active service
- ✅ `spec/services/entries/no_trade_engine_spec.rb` - Active service
- ✅ `spec/services/entries/no_trade_context_builder_spec.rb` - Active service
- ✅ `spec/services/entries/structure_detector_spec.rb` - Active service
- ✅ `spec/services/entries/atr_utils_spec.rb` - Active utility
- ✅ `spec/services/entries/vwap_utils_spec.rb` - Active utility
- ✅ `spec/services/entries/candle_utils_spec.rb` - Active utility
- ✅ `spec/services/entries/range_utils_spec.rb` - Active utility
- ✅ `spec/services/entries/option_chain_wrapper_spec.rb` - Active service

### **Indicators** (All Keep)
- ✅ `spec/services/indicators/base_indicator_spec.rb` - Base class
- ✅ `spec/services/indicators/indicator_factory_spec.rb` - Active factory
- ✅ `spec/services/indicators/calculator_spec.rb` - Active service
- ✅ `spec/services/indicators/supertrend_indicator_spec.rb` - Active indicator
- ✅ `spec/services/indicators/adx_indicator_spec.rb` - Active indicator
- ✅ `spec/services/indicators/rsi_indicator_spec.rb` - Active indicator
- ✅ `spec/services/indicators/macd_indicator_spec.rb` - Active indicator
- ✅ `spec/services/indicators/trend_duration_indicator_spec.rb` - Active indicator
- ✅ `spec/services/indicators/threshold_config_spec.rb` - Active config

### **Options Services** (All Keep)
- ✅ `spec/services/options/chain_analyzer_spec.rb` - Active service
- ✅ `spec/services/options/strike_selector_spec.rb` - Active service
- ✅ `spec/services/options/premium_filter_spec.rb` - Active service
- ✅ `spec/services/options/index_rules/nifty_spec.rb` - Active rule

### **Orders Services** (All Keep)
- ✅ `spec/services/orders/placer_spec.rb` - Active service
- ✅ `spec/services/orders/gateway_live_spec.rb` - Active service
- ✅ `spec/services/orders/gateway_paper_spec.rb` - Active service
- ✅ `spec/services/orders/bracket_placer_spec.rb` - Active service
- ✅ `spec/services/orders/entry_manager_spec.rb` - Active service

### **Capital Services** (All Keep)
- ✅ `spec/services/capital/allocator_spec.rb` - Active service
- ✅ `spec/services/capital/dynamic_risk_allocator_spec.rb` - Active service

### **Positions Services** (All Keep)
- ✅ `spec/services/positions/activecache_add_remove_spec.rb` - Active service
- ✅ `spec/services/positions/trailing_config_spec.rb` - Active service

### **Trading Services** (All Keep)
- ✅ `spec/services/trading/admin_actions_spec.rb` - Active service
- ✅ `spec/services/trading_session_spec.rb` - Active service
- ✅ `spec/services/trading_system/signal_scheduler_spec.rb` - Active service
- ✅ `spec/services/trading_system/position_heartbeat_market_close_spec.rb` - Active service

### **Integration Tests** (All Keep)
- ✅ `spec/integration/nemesis_v3_flow_spec.rb` - End-to-end flow
- ✅ `spec/integration/exit_rules_spec.rb` - Integration test
- ✅ `spec/integration/websocket_data_feed_spec.rb` - Integration test
- ✅ `spec/integration/ltp_updates_spec.rb` - Integration test
- ✅ `spec/integration/signal_generation_strategies_spec.rb` - Integration test
- ✅ `spec/integration/modular_indicator_system_integration_spec.rb` - Integration test
- ✅ `spec/integration/supertrend_adx_computation_spec.rb` - Integration test
- ✅ `spec/integration/trend_duration_indicator_integration_spec.rb` - Integration test
- ✅ `spec/integration/option_chain_analysis_spec.rb` - Integration test
- ✅ `spec/integration/order_placement_spec.rb` - Integration test
- ✅ `spec/integration/database_persistence_spec.rb` - Integration test
- ✅ `spec/integration/dynamic_subscription_spec.rb` - Integration test
- ✅ `spec/integration/ohlc_data_fetch_spec.rb` - Integration test
- ✅ `spec/integration/vcr_cassette_generation_spec.rb` - Integration test

### **Initializers** (Keep)
- ✅ `spec/initializers/trading_supervisor_spec.rb` - Active initializer

### **Risk Rule Engine Simulation** (Keep)
- ✅ `spec/services/risk/rule_engine_simulation_spec.rb` - Simulation tests

---

## ❌ **SPECS TO REMOVE** (No Active Implementation)

### **1. Strategy Specs** (2 files - KEEP)

**Status**: `MultiIndicatorStrategy` exists and is actively used in `Signal::Engine` when enabled.

- ✅ `spec/strategies/multi_indicator_strategy_spec.rb` - **KEEP**
  - Class exists: `app/strategies/multi_indicator_strategy.rb`
  - Used conditionally: When `signals.use_multi_indicator_strategy: true` in config
  - Config: `config/algo.yml:219` - Currently `false` but feature exists
  - Implementation: `app/services/signal/engine.rb:66, 81, 806`
  - **Reason to Keep**: Feature exists and can be enabled, so specs are needed

- ✅ `spec/strategies/multi_indicator_strategy_confluence_spec.rb` - **KEEP**
  - Tests same strategy with confluence mode
  - Same conditional usage
  - **Reason to Keep**: Tests different confirmation modes of the strategy

**Action**: Keep both specs. The feature is implemented and can be enabled via config.

### **2. Capital Allocator Integer Multiplier Spec** (1 file - REVIEW/CONSOLIDATE)

- ⚠️ `spec/services/capital/allocator_integer_multiplier_spec.rb` - **REVIEW FOR CONSOLIDATION**
  - **Status**: Focused spec file testing integer multiplier normalization edge cases
  - **Tests**:
    - Non-integer multiplier normalization (1.5 -> 1)
    - Minimum multiplier enforcement (0 -> 1)
    - Lot size enforcement
    - Insufficient capital handling
  - **Main Spec Coverage**: `allocator_spec.rb` tests multipliers (lines 144, 169, 182) but may not cover all edge cases
  - **Recommendation**:
    - **Option 1 (Recommended)**: Merge the focused tests into `allocator_spec.rb` under a dedicated `describe 'integer multiplier enforcement'` block, then remove this file
    - **Option 2**: Keep if the focused tests provide better organization and clarity
  - **Action**: Review if main spec covers all edge cases. If yes, consolidate. If no, keep or merge.

**Action**: Review and potentially consolidate into main spec for better organization.

---

## ⚠️ **SPECS TO REVIEW** (May Need Updates)

### **1. Integration Tests** (Review for completeness)
- ⚠️ `spec/integration/vcr_cassette_generation_spec.rb` - Review if VCR is still actively used
- ⚠️ `spec/integration/dynamic_subscription_spec.rb` - Verify this matches current subscription logic

### **2. Risk Rules** (All seem active, but verify)
- All risk rule specs appear to test active rules from `RuleFactory.create_engine()`
- ✅ All rules are registered in `app/services/risk/rules/rule_factory.rb`

---

## 📊 **Summary**

| Category               | Count | Action                            |
| ---------------------- | ----- | --------------------------------- |
| **Keep**               | 112   | ✅ All active implementations      |
| **Review/Consolidate** | 1     | ⚠️ Consider merging into main spec |
| **Remove**             | 0     | ✅ No deprecated code found        |

### **Files to Review for Consolidation**:
1. `spec/services/capital/allocator_integer_multiplier_spec.rb` - **REVIEW**
   - **Status**: Focused test file for integer multiplier edge cases
   - **Recommendation**: Merge tests into `spec/services/capital/allocator_spec.rb` for better organization
   - **Action**: Review if main spec covers all cases. If yes, merge and remove. If no, keep.

### **Total Specs**: 113 (All are testing active code)

---

## 🔍 **Verification Steps**

Before consolidating `allocator_integer_multiplier_spec.rb`:
1. ✅ Check if `allocator_spec.rb` tests non-integer multiplier (1.5 -> 1 normalization)
2. ✅ Verify all edge cases are covered in main spec
3. ✅ If missing, merge the unique tests into main spec before removing

---

## 📝 **Notes**

- All other specs test active, production code
- Risk rules are all registered in `RuleFactory` and actively used
- Live services are all part of the trading supervisor
- Integration tests cover end-to-end flows
- Model specs test active ActiveRecord models

