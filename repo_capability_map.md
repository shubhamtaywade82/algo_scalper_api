# Repo Capability Map and Test Coverage

Generated from actual scan of `app/`, `lib/`, `config/`, `docs/`, `.github/`, `db/`, and `spec/`.

Legend:
- Coverage: ✅ tested | 🔶 partial | ❌ not found | ⚠️ present but risky
- Note: All paths below are real files/directories found on disk unless explicitly labeled as docs-only or missing.

---

## 1. Options Buying Framework
- Docs reference `options_buying/cm_producer.rb` but no implementation found; treat as concept-only or doc artifact.
- `app/services/options_buying/strategies/`
- `app/services/options/index_rules/`
- `app/services/options/strike_qualification/`
- `app/services/option_intelligence/`
- `app/models/options_buying_signal_event.rb`
- `app/jobs/options_buying/chain_radar_job.rb` ✅ `spec/jobs/options_buying/chain_radar_job_spec.rb`
- `app/jobs/options_buying/daily_metrics_job.rb` ✅ `spec/jobs/options_buying/daily_metrics_job_spec.rb`
- `app/jobs/options_buying/eod_carry_job.rb` ✅ `spec/jobs/options_buying/eod_carry_job_spec.rb`
- `app/jobs/options_buying/telemetry_sink_job.rb` ✅ `spec/jobs/options_buying/telemetry_sink_job_spec.rb`
- `app/jobs/options_buying/candle_precompute_job.rb` — 🔶 `spec/jobs/` only shows `chain_radar/daily_metrics/eod_carry/telemetry_sink`
- `app/services/options_buying/stream_consumer.rb` ✅ `spec/services/options_buying/stream_consumer_spec.rb`
- `app/services/options_buying/stream_writer.rb` ✅ `spec/services/options_buying/stream_writer_spec.rb`
- `app/services/options_buying/trade_scoring_engine.rb` ✅
- `app/services/options_buying/expected_value_model.rb` ✅
- `app/services/options_buying/risk_explorer.rb` ✅
- `app/services/options_buying/breakout_watcher.rb` ✅
- `app/services/options_buying/breakout_evaluator.rb` ✅
- `app/services/options_buying/rsi_divergence_scanner.rb` ✅
- `app/services/options_buying/atr_compression_checker.rb`
- `app/services/options_buying/carry_policy.rb`
- `app/services/options_buying/minute_bar_aggregator.rb` ✅
- `app/services/options_buying/tick_metrics.rb`
- `app/services/options_buying/state_store.rb` ✅
- `app/services/options_buying/performance_db_spec.rb` — ✅
- `app/services/options/strike_selector.rb` suite heavily tested
- `app/services/options/chain_analyzer_strike_pick_result.rb` ✅
- `app/services/options/chain_signal_extractor.rb` ✅
- `app/services/options/delta_acceleration_detector.rb` ✅
- `app/services/options/premium_filter.rb` ✅
- `app/services/options/prop_strike_selector.rb` ✅
- `app/services/options/strike_aggregator.rb` ✅
- `app/services/options/strike_selector_simple.rb` ✅
- `app/services/options/regime_detector.rb` ✅
- `app/services/options/expiry_calendar.rb` ✅
- `app/services/options/auto_calibrator.rb` ✅
- `app/services/adapters/option_chain/dhan_adapter.rb`
- `app/services/adapters/option_chain/null_adapter.rb`
- `app/services/strike_selection/`
- **Summary**: Well-tested options buying pipeline with scoring, selection, and stream handling.

---

## 2. Signal Generation, Scheduling, and Enforcement
- `app/services/signal/` (`scheduler.rb`, `engine_*.rb`, `metadata_builder.rb`, `trend_scorer.rb`, `fast_entry_mode.rb`, `entry_quality_filter.rb`, `cycle_summary.rb`, `momentum_validator.rb`) — extensive specs
- `app/services/signal/engine_market_close_spec.rb`
- `app/services/signal/scheduler_market_close_spec.rb`
- `app/services/signal/scheduler_direction_first_spec.rb`
- `app/services/signal/engine_confidence_score_spec.rb`
- `app/services/signal/engine_validation_and_dte_spec.rb`
- `app/services/signal/fast_entry_mode_spec.rb`
- `app/services/signal/entry_quality_filter_spec.rb`
- `app/services/signal/momentum_validator_spec.rb`
- `app/services/signal/trend_scorer_spec.rb`
- `app/services/signal/metadata_builder.rb`
- `app/services/signal/live_metadata_cache.rb`
- **Summary**: Dense test matrix for trading signal lifecycle and scheduler.

---

## 3. Market Data Feed and Ingestion
- `app/services/live/market_feed_hub.rb`
- `app/services/live/market_feed_hub_service.rb`
- `app/services/live/ws_hub.rb`
- `app/services/live/ws_connection_budget.rb`
- `app/services/live/redis_tick_cache.rb`
- `app/services/live/tick_query.rb`
- `app/services/live/feed_health_service.rb`
- `app/services/live/market_feed_hub_*.spec.rb` ✅
- `app/services/live/redis_tick_cache_spec.rb`
- `app/services/market_data/`
- `app/services/market_state/`
- `app/queries/derivatives/atm_options.rb` ✅
- `app/queries/positions/active_for_exit.rb` ✅
- `app/queries/positions/risk_candidates.rb` ✅
- `app/services/index_instrument_cache.rb`
- `app/services/index_config_loader.rb` ✅
- `app/services/instruments_importer.rb` jobs/integrations tested
- `app/services/historical_options_analyzer.rb`
- **Summary**: Websocket hub and tick cache well-spec'd; historical backfill and options analyzer loosely covered.

---

## 4. Entry Guards Pipeline
- `app/services/entries/entry_guard_pipeline.rb`
- `app/services/entries/entry_guard.rb`
- `app/services/entries/order_execution_service.rb`
- `app/services/entries/guards/*` (~30 guards, e.g. `drawdown_guard.rb`, `circuit_breaker_guard.rb`, `vix_gate_guard.rb`, `time_regime_guard.rb`, `sizing_guard.rb`, `smc_navigator_guard.rb`)
- `app/services/entries/entry_snapshot_builder.rb`
- `app/services/entries/no_trade_engine.rb`
- `app/services/entries/no_trade_thresholds.rb`
- `app/services/entries/no_trade_context_builder.rb`
- `app/services/entries/bos_entry_engine.rb`
- `app/services/entries/structure_detector.rb`
- `app/services/entries/atr_utils.rb`
- `app/services/entries/vwap_utils.rb`
- `app/services/entries/range_utils.rb`
- `app/services/entries/chop_score.rb`
- `app/services/entries/option_chain_wrapper.rb`
- `app/services/entries/meta_builder.rb`
- Specs: ✅ extensive (`entry_guard_*`, `no_trade_engine`, base utilities)
- **Summary**: Strong coverage of guard concepts; extremely high surface area with many guards.

---

## 5. Risk Management and Drawwdown
- `app/services/live/risk_manager_service/` (runner.rb, exit_enforcement.rb, exit_execution.rb, pnl_cache.rb)
- `app/services/live/risk_manager_service/config.rb`
- `app/services/risk/circuit_breaker.rb` ✅
- `app/services/portfolio/drawdown_guard.rb` ✅
- `app/services/portfolio/pnl_tracker.rb` ✅
- `app/services/portfolio/profit_lock_engine.rb` ✅
- `app/services/portfolio/paper_peak_tracker.rb`
- `app/services/risk/rules/`
- `app/services/live/trailing_engine.rb` ✅
- `app/services/live/unified_exit_checker.rb` ✅
- `app/services/live/structure_invalidation_evaluator.rb`
- `app/services/live/edge_failure_detector.rb`
- `app/services/market/vix_gate.rb` ✅
- `app/services/drawdown_guard/` implied from controller
- `app/controllers/api/drawdown_guard_controller.rb`
- **Summary**: Risk manager service tested across market-close, integration, and market close scenarios; circuit breaker + drawdown guard covered. Trailing engine well covered. `vix_gate` and structure invalidation lightly covered.

---

## 6. Position Management and Trailing
- `app/services/positions/`
- `app/services/positions/states/`
- `app/services/positions/trailing_config/`
- `app/models/position_tracker.rb` ✅ multiple specs (`active_for_exit`, `association_contracts`)
- `app/models/position_meta_snapshot.rb`
- `app/models/paper_daily_wallet.rb`
- `app/models/domain/trading_context.rb` ✅
- `app/serializers/positions/`
- Controllers: `api/positions_controller.rb`
- `app/services/live/position_index.rb`
- `app/services/live/position_runtime_cache.rb`
- `app/queries/positions/active_for_exit.rb` ✅
- **Summary**: Position tracker, serializer, states, and some SRP tests adequate; paper-wallet and meta-snapshot thin.

---

## 7. Execution and Order Management
- `app/services/execution/fill_validator.rb`
- `app/services/execution/order_retry.rb`
- `app/services/execution/slippage_model.rb`
- `app/services/alpha_execution_service.rb`
- `app/jobs/alpha_execution_job.rb`
- `app/services/orders/` (`placer.rb`, `slicer.rb`, `gateway_*.rb`, `adaptive_trailing.rb`, `bracket_placer.rb`, `entry_manager.rb`, `limit_chaser.rb`, `mfe_exit_engine.rb`, `gamma_trailing_engine.rb`, `placer.rb`, `trailing_engine.rb`)
- ✅ specs exist across orders (`gateway_live_spec`, `gateway_paper_spec`, `bracket_placer`, `entry_manager`, `placer`, `slicer`, `mfe_exit_engine`, `limit_chaser`, `gamma_trailing`, etc.)
- `app/services/concerns/broker_fee_calculator.rb`
- `app/services/concerns/session_detector.rb`
- **Summary**: Order gating well covered; execution edge (`fill_validator`, `slippage_model`, `order_retry`) lightly documented but mostly UNTESTED.

---

## 8. Backtesting and Simulation
- `app/services/backtest/engine.rb`
- `app/services/backtest/market_replayer.rb`
- `app/services/backtest/report.rb`
- `app/services/backtest/metrics.rb`
- `app/services/backtest/signal_generator_backtester.rb`
- `app/services/backtest/smc_replay_runner.rb` ✅ `spec/services/backtest/smc_replay_runner_spec.rb`
- `app/services/backtest/option_trade_simulator.rb`
- `app/services/backtest/strategy_adapter.rb`
- `app/services/auto_exp/` (`experiment_runner.rb`, `backtest_executor.rb`, `evaluator.rb`, `llm_planner.rb`, `results_store.rb`, `config_applier.rb`)
- `scripts/run_backtest.rb`
- **Summary**: Backtest used for SMC replay and auto experiments; a few scenarios covered but overall spec coverage is partial.

---

## 9. Analytics, Calibration, and Configuration
- `app/services/analytics/` (`auto_rule_engine.rb`, `best_setups_extractor.rb`, `strategy_evaluator.rb`, `trade_breakdown.rb`, `threshold_optimizer.rb`)
- `app/services/algo_config/` (`audit.rb`, `validator.rb`, `document_store.rb`, `cache_broadcaster.rb`, `legacy_migrator.rb`, `merge_util.rb`, `profitability_slice{2,3,4}.rb`, `auxiliary_bootstrap.rb`)
- ✅ specs: validator, audit, document_store, cache_broadcaster, legacy_migrator, merge_util, slice2/3/4
- `app/services/indicators/` (`calculator.rb`, `cached_indicator_source.rb`, `adx`, `ema_direction`, `macd`, `rsi`, `supertrend`, `supertrend_indicator`, `ml_adaptive_supertrend`, `threshold_config`, `trend_duration_indicator`, `holy_grail`)
- config: `config/algo.yml`, `config/algo_organized.yml`, `config/strategy_config.yml`, `config/signal_tier_presets.yml`
- docs: `docs/ALPHA*.md`, `docs/NEW_ANALYTICS_AND_STRATEGY_LAYER.md`, `docs/options_buying_*.md`
- `app/services/context/builder.rb`
- `app/services/core/event_bus.rb`
- **Summary**: Analytics and algo config have dedicated and mostly-tested modules.

---

## 10. AI / Agent / LLM Layer
- `app/services/ai/` (`ai_snapshot_prompt_builder.rb`, `alpha_gate.rb`, `generative_ai_market_gate.rb`, `autonomous/orchestrator.rb`, `autonomous/auditor.rb`, `autonomous/task_runner.rb`, `dhan_tool_bridge.rb`)
- `app/services/ai_technical_analysis_job.rb`
- `lib/services/ai/` (full `technical_analysis_agent` with intent resolver, tool registry, adaptive controller, learning, etc.)
- spec: `spec/services/ai/ai_snapshot_prompt_builder_spec.rb`, `dhan_tool_bridge_spec.rb`, `generative_ai_market_gate_spec.rb`, `ai_technical_analysis_job_spec.rb`
- **Summary**: AI layer exists and has specs for gateway/prompt-builder; agent internals mostly untested.

---

## 11. SMC / Structure / Regime
- `app/services/smc/` (structure_engine.rb, bias_engine.rb, context?, confluence?, detectors?, tick_ai/)
- `app/services/market_structure/`
- `app/services/market/regime_scorer.rb`, `regime_state.rb`, `market_regime_resolver.rb` ✅
- `app/services/market_context/participation_analyzer.rb`
- `app/services/avrz/detector.rb` ✅
- `app/services/regime/`
- Controllers/api: `smc_controller.rb`
- Jobs: `smc_scanner_job.rb` ✅, `smc/tick_ai_digest_job.rb` ✅
- docs: `docs/smc/`
- **Summary**: SMC ecosystem heavily represented, but many service files may lack direct spec coverage (limited spec list shows only a few: detectors, bias_engine, structure_engine, permission snapshot, navigator).

---

## 12. Ledger / Capital / Wallet
- `app/services/ledger/` (`entry_poster.rb`, `exit_poster.rb`, `posting_service.rb`, `seeder.rb`, `wallet_reader.rb`, `balance_checker.rb`, `config.rb`)
- `app/services/capital/allocator.rb`, `dynamic_risk_allocator.rb` ✅
- `app/services/portfolio/` (drawdown_guard, paper_peak_tracker, pnl_tracker, profit_lock)
- `app/controllers/api/ledger_controller.rb`
- ledger models: `ledger_account`, `ledger_journal_entry`, `ledger_posting`, `paper_daily_wallet`
- spec: `spec/services/ledger/ledger_spec.rb`, `capital/allocator_*`, portfolio names
- **Summary**: Capital/ludget services steadily tested.

---

## 13. DhanHQ Integration
- `app/lib/dhan/auth/strategies/` (manual, renew, totp, authority, resolver)
- `app/services/dhan/token_manager.rb` ✅
- `app/services/dhan/ip_service.rb`
- `app/jobs/dhan/auto_ip_updater_job.rb` ✅
- `app/controllers/api/dhan_access_token_controller.rb` ✅
- **Summary**: Dhan auth and token refresh well-covered; IP updater covered.

---

## 14. Dashboard, Realtime, and Observability
- `app/channels/dashboard_channel.rb`
- `app/channels/positions_channel.rb`
- `app/services/graphify/context_service.rb` ✅
- `app/services/notifications/telegram/`
- `app/services/telegram/`
- `app/services/observability/` (entry_funnel_metrics, structured_log)
- `spec/channels/dashboard_channel_spec.rb`, `positions_channel_spec.rb`
- `lib/observability/`
- `app/services/stats_notifier_service.rb`
- `app/services/live/stats_notifier_service.rb`
- **Summary**: Dashboard channels tested; observability framework partial.

---

## 15. API Controllers and Admin
- `app/controllers/api/` — alpha_controller, analysis, calibration_runs, candles, circuit_breaker, dashboard, dhan_access_token, drawdown_guard, health, ledger, market, positions, public_ip, settings, signals, smc, test
- specs: ✅ most controllers have request specs (`analysis_ai_snapshot_spec`, `dashboard_spec`, `ledger_spec`, `market_controller_spec`, `positions_controller_spec`, `settings_spec`, `calibration_runs_spec`, `dhan_access_token_spec`, `public_ip_spec`, `token_authentication_spec`, etc.)
- `spec/controllers/redis_ui_controller_spec.rb`
- **Summary**: API coverage solid; admin-only surface likely additional.

---

## 16. Database, Migrations, and Configuration Files
- `db/schema.rb`
- `db/seeds.rb`
- `lib/db_seeds.rb`
- `lib/india_index_registry.rb` ✅
- `app/lib/algo_config.rb`
- `app/lib/options_buying/redis_pool.rb`
- `app/lib/positions/drawdown_schedule.rb` ✅ `spec/lib/positions/drawdown_schedule_spec.rb` and `_config_spec.rb`
- `app/lib/market/calendar.rb` ✅
- `app/models/` — many well-defined; key ones have model specs (calibration_run, candle, candle_series, derivative, instrument, position_tracker, smc_event, trading_signal, etc.)
- `app/models/concerns/position_tracker/` — ✅ covered (lifecycle, broadcastable, indexable, pnl_calculatable, queryable)
- **Summary**: Domain and config foundations have reasonable test coverage.

---

## 17. Scheduling and Workers
- `app/jobs/` — active job classes (analysis, alpha_execution, alpha_scan, autonomous/optimization, clear_carried_overnight, dhan/auto_ip_updater, instruments_import, iv_snapshot, ledger/daily_close, ledger/reconciliation, market/vix_gate, options_buying/*, portfolio_reset, pre_market_iv_baseline, public_ip_log, smc/tick_ai_digest, smc_scanner, weekly_calibration)
- specs: ✅ subset covered (analysis_job_spec, alpha_technical_analysis_job_spec, clear_carried_overnight_positions_job_spec, dhan job, instruments_import_job_spec, observability job, smc jobs, weekly_calibration_job_spec, public_ip_log_job_spec)
- **Summary**: Partial job coverage; recurring definitions exist in `.schedule.yml` equivalents, but not all workers have harnessed tests.

---

## 18. CI/CD and Test Infrastructure
- `.github/workflows/ci.yml`
- `.github/dependabot.yml`
- `lib/tasks/` — many rake task files
- `backtest_runner.rb`
- `lib/testing/service_test_runner.rb` (`lib/testing/README.md`, `lib/testing/quick_start.rb`)
- `scripts/test_services/` — suite of ruby-based service tests
- `spec/support/` test helpers (database_cleaner, vcr, webmock, factory_bot, shoulda, trading_services_helper)
- **Summary**: CI present; manual service harness scripts exist but aren't tightly integrated into standard RSpec runs.

---

## 19. Documentation, Plans, and Audit References
- `docs/` — COMPREHENSIVE coverage of framework, options buying automation, services catalog, AVRZ/SMC, risk, trading pipeline, and integration guides.
- `docs/superpowers/specs/` and `plans/` — detailed design/plan documents with embedding of use-cases.
- `options_buying_plan/` — milestone-by-milestone plan and detailed implementation plan.
- `REPO_AUDIT.md`, `REPO_SUMMARY.md`, `TODO.md`, `CODING_CONVENTIONS.md`, `CLAUDE.md` — high-fidelity repo operating documents.
- **Summary**: Excellent documentation; exceptionally well-planned options buying system. Design documents are a first-class artifact here.

---

## Overall Risk Gaps
1. **Order execution edge cases**: `fill_validator.rb`, `slippage_model.rb`, and `order_retry.rb` have no/light dedicated unit tests.
2. **AI agent internals**: `technical_analysis_agent/*` and SMC tick-AI have minimal spec coverage.
3. **Historical replay and backtesting**: backtest engine/option trade simulator/smc replay runner only partially tested.
4. **Options buying core production worker**: `candle_precompute_job` and `stream_writer` in some areas could use resilience tests.
5. **Documentation vs implementation drift**: heavy docs/plans may outpace automated test rails.
6. **CI/Workflow cadence**: `.github/workflows/graphify-impact.yml` implies non-test workflow; primary CI not audited here.

---
Generated by Hermes repo mapper.
