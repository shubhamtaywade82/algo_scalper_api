# Ponytail review — full repo

Scope: over-engineering / unnecessary complexity only. Not bugs, not security, not perf.
9 parallel passes across `app/services/*`, `app/jobs/`, `app/models/`, `lib/`. Each finding
verified by grepping for callers/subclasses before flagging as dead/single-caller.

Format: `path:Lline: tag what. replacement.`

## live / positions / execution / orchestration

app/services/orchestration/strategy_runner.rb:L1-66: delete: whole StrategyRunner class, a parallel entry pipeline with zero callers anywhere in app/lib — never instantiated. Nothing replaces it; live flow is Signal::Scheduler → Entries::EntryGuard.
app/services/execution/fill_validator.rb:L1-13: delete: FillValidator has zero callers in app, lib, or spec. Nothing replaces it.
app/services/execution/order_retry.rb:L1-20: delete: OrderRetry has zero callers in app, lib, or spec. Nothing replaces it.
app/services/execution/slippage_model.rb:L1-15: delete: SlippageModel has zero callers in app, lib, or spec — the whole app/services/execution/ directory is dead. Nothing replaces it.
app/services/positions/meta_updater.rb:L1-45: delete: MetaUpdater has zero callers anywhere, not even a spec. Nothing replaces it.
app/services/positions/meta_patch.rb:L1-81: delete: MetaPatch has a spec but zero production callers. Nothing replaces it.
app/services/positions/meta_patch.rb:L65-78: shrink: cast_value is duplicated verbatim (18 lines) in positions/meta_updater.rb. One shared method, e.g. a PositionTracker::MetaCasting module.
app/services/positions/states/trailing_state.rb:L1-18: yagni: TrailingState is instantiated nowhere — PositionStateMachine::STATE_CLASSES only maps to Pending/Active/Closed; trailing is tracked via tracker.meta. Nothing replaces it.
app/services/positions/states/exit_pending_state.rb:L1-16: yagni: ExitPendingState is instantiated nowhere — same STATE_CLASSES gap; exit-pending is tracked via tracker.exit_requested_at instead. Nothing replaces it.
app/services/positions/active_cache_service.rb:L1-18: yagni: wrapper exists only to rename ActiveCache's start!/stop! to start/stop for Supervisor, forces a manual Zeitwerk `load` workaround in bootstrap.rb. Add start/stop aliases directly on Positions::ActiveCache instead.
app/services/live/ws_hub.rb:L1-27: yagni: WsHub wraps Live::MarketFeedHub.instance for a single caller (InstrumentHelpers) just to rename segment:/security_id: to seg:/sid:. Call Live::MarketFeedHub.instance.subscribe(segment:, security_id:) directly from instrument_helpers.rb.

**subtotal: -319**

## entries / signal / smc / market_structure

app/services/signal/validator.rb:L1-17: delete: Signal::Validator class with zero callers (Signal::Engine uses MomentumValidator instead). Nothing replaces it.
app/services/signals/hold.rb:L1-19: delete: Signals::Hold value object never produced by any production strategy, only instantiated in test doubles. Nothing replaces it.
app/services/signals/exit.rb:L1-20: delete: Signals::Exit value object never produced by any production strategy. Nothing replaces it.
app/services/signals/buy_call.rb:L1-21: delete: Signals::BuyCall never produced by any production strategy; only matched in lib/tasks/backtest.rake against a class never actually returned. Nothing replaces it.
app/services/signals/buy_put.rb:L1-21: delete: Signals::BuyPut same dead protocol as BuyCall. Nothing replaces it.
app/services/market_structure/engine.rb:L1-252: delete: MarketStructure::Engine has zero callers anywhere, no spec exists — entire 252-line state-machine class is unreachable. Nothing replaces it.
app/services/smc/analyzer.rb:L1-57: delete: Smc::Analyzer orchestrator has zero callers and no spec; superseded by Smc::StructureEngine/Smc::Navigator which are actually wired in. Nothing replaces it.
app/services/entries/guards/banknifty_last_week_guard.rb:L1-17: delete: guard not registered in EntryGuardPipeline#default_handlers, no other caller, no spec. Nothing replaces it.
app/services/entries/guards/bid_ask_spread_guard.rb:L1-94: delete: guard not registered in EntryGuardPipeline#default_handlers; only referenced by a regex label in entry_funnel_metrics.rb (not invoked) and its own spec. Nothing replaces it.
app/services/entries/guards/rsi_bias_guard.rb:L1-34: delete: same as above — not registered, only referenced by unused label. Nothing replaces it.
app/services/entries/guards/strike_cooldown_guard.rb:L1-86: delete: not registered in EntryGuardPipeline#default_handlers, no other caller besides its own spec. Nothing replaces it.
app/services/entries/guards/transaction_cost_guard.rb:L1-95: delete: not registered in EntryGuardPipeline#default_handlers; only referenced by unused label. Nothing replaces it.

**subtotal: -733**

## orders / capital / risk / policies

app/services/orders/entry_manager.rb:L1: delete: entire class (363 lines) unused outside its own spec — live entry path is Entries::EntryGuard.try_enter per CLAUDE.md. Nothing replaces it.
app/services/capital/dynamic_risk_allocator.rb:L1: delete: DynamicRiskAllocator's only caller is the dead Orders::EntryManager, so transitively unused. Nothing replaces it.
app/services/policies/exit_policy.rb:L21: delete: Policies::ExitPolicy has zero callers — Live::UnifiedExitChecker is called directly elsewhere. Nothing replaces it.
app/services/orders/manager.rb:L4: delete: Orders::Manager has zero callers (Orders::Placer.buy_market! is called directly elsewhere). Nothing replaces it.
app/services/orders/gateway.rb:L4: delete: Orders::Gateway abstract base class has no subclasses (GatewayLive/GatewayPaper don't inherit it), never instantiated. Nothing replaces it.
app/services/orders/commands/cancel_order_command.rb:L18: delete: CancelOrderCommand has zero callers outside its own spec. Nothing replaces it.
app/services/risk/live_guardrails.rb:L4: delete: Risk::LiveGuardrails has zero callers, only its own spec. Nothing replaces it.
app/services/risk/profit_manager.rb:L6: delete: Risk::ProfitManager has zero callers, only its own spec. Nothing replaces it.
app/services/risk/rules/rule_engine.rb:L17: yagni: add_rule/remove_rule/find_rule mutation API — zero callers, engine is only ever built once via RuleFactory.exit_rules. Delete the three methods, keep evaluate.
app/services/capital/allocator.rb:L99: shrink: normalize_multiplier is a one-line wrapper called from a single site. Inline `[scale_multiplier.to_i, 1].max` directly into effective_multiplier.

**subtotal: -650**

## options / options_buying / option_intelligence / strike_selection

app/services/options/chain_analyzer.rb:L74-558: delete: entire instance-based API (initialize, load_chain_data!, recommend_strikes_for_signal, chain_summary, assess_volatility, liquidity_status, analyze_strike, calculate_position_size, select_candidates + private helpers) — nothing calls `.new` anywhere; every caller uses class-level pick_strikes/pick_strikes_with_qualification or DerivativeChainAnalyzer. Delete the whole instance API.
app/services/options/chain_analyzer.rb:L1324-1341: delete: filter_and_rank class method, never called (superseded by filter_and_rank_from_instrument_data). Nothing replaces it.
app/services/options/strike_selector.rb:L24-313: delete: instance API (initialize, select, ~15 private helpers) never instantiated anywhere. Only strike_type_for_momentum (L18-22) is live — keep it, delete the rest (~290 lines).
app/services/options/premium_filter.rb:L1-130: delete: Options::PremiumFilter's only caller is the dead StrikeSelector#select — transitively dead. Nothing replaces it.

**subtotal: -750**

## indicators / momentum / volume / liquidity / regime / market_state / market_context / market_data / market

app/services/momentum/engine.rb:L1: delete: AlgoScalper::Momentum::Engine, 202-line RSI/EMA/ATR/VWAP reimplementation, zero callers, no specs. Nothing replaces it.
app/services/regime/engine.rb:L1: delete: AlgoScalper::Regime::Engine (+nested CandleSeries), 198-line reimplementation, zero callers, no specs. Nothing replaces it.
app/services/market_data/engine.rb:L1: delete: AlgoScalper::MarketData::Engine, 177-line WS/cache orchestrator duplicating Live::MarketFeedHub, zero callers. Nothing replaces it.
app/services/market_data/tick_cache.rb:L1: delete: AlgoScalper::MarketData::TickCache, zero callers, duplicates the real (LOCKED) Live tick cache. Nothing replaces it.
app/services/market_data/depth_cache.rb:L1: delete: AlgoScalper::MarketData::DepthCache, zero callers anywhere. Nothing replaces it.
app/services/market_data/chain_cache.rb:L1: delete: AlgoScalper::MarketData::ChainCache, zero callers anywhere. Nothing replaces it.
app/services/market_data/option_chain_fetcher.rb:L1: delete: MarketData::OptionChainFetcher, zero callers (live reads go through Adapters::OptionChain::DhanAdapter). Nothing replaces it.
app/services/market/market_regime_resolver.rb:L1: delete: Market::MarketRegimeResolver, 416-line service, only a spec references it, zero production callers. Nothing replaces it.
app/services/market/regime_state.rb:L1: delete: Market::RegimeState, zero callers, no spec. Nothing replaces it.
app/services/indicators/adx_indicator.rb:L1: delete: Indicators::AdxIndicator (BaseIndicator wrapper), zero callers — real ADX goes through CandleSeries#adx / Indicators::Calculator. Nothing replaces it.
app/services/indicators/rsi_indicator.rb:L1: delete: Indicators::RsiIndicator wrapper, zero callers. Nothing replaces it.
app/services/indicators/macd_indicator.rb:L1: delete: Indicators::MacdIndicator wrapper, zero callers. Nothing replaces it.
app/services/indicators/supertrend_indicator.rb:L1: delete: Indicators::SupertrendIndicator wrapper, zero callers — real usage goes through Indicators::Supertrend directly at 8+ sites. Nothing replaces it.
app/services/indicators/ml_adaptive_supertrend_indicator.rb:L1: delete: MlAdaptiveSupertrendIndicator wrapper, zero callers. Nothing replaces it.
app/services/indicators/ema_direction_indicator.rb:L1: delete: EmaDirectionIndicator, zero callers. Nothing replaces it.
app/services/indicators/cached_indicator_source.rb:L1: delete: CachedIndicatorSource, zero callers despite its own doc comment telling live code to use it. Nothing replaces it.
app/services/indicators/threshold_config.rb:L1: yagni: 161-line preset system (4 presets, merge/lookup API) whose only real callers are the now-dead AdxIndicator/RsiIndicator wrappers. Delete alongside them.
app/services/market_state/trend_detector.rb:L16: delete: TrendDetector.bearish? never called (only .bullish? is used). Nothing replaces it.
app/services/market_context/regime_composer.rb:L102: shrink: `return :strong if adx >= 50.0` is unreachable — next line already returns :strong for adx >= 40.0. Delete L102.

**subtotal: -1950**

## research / backtest / analytics / analysis / optimization / lib/calibration

app/services/analysis/snapshot.rb:L1: delete: Analysis::Snapshot/SubSnapshot has zero callers anywhere. Nothing.
app/services/analytics/live_adapter.rb:L1: delete: entire app/services/analytics/ tree (live_adapter, auto_rule_engine, best_setups_extractor, threshold_optimizer, trade_breakdown, metrics.rb, strategy_evaluator) never referenced outside itself. Nothing.
app/services/backtest/engine.rb:L11: delete: Backtest::Engine calls Portfolio.new but no Portfolio class exists anywhere — would NameError if run; whole mini-engine (~195 lines) only referenced by a `defined?(Backtest::Engine)` existence probe. Nothing.
app/services/backtest/strategy_adapter.rb:L16: delete: Backtest::Portfolio part of the same unused mini-engine. Nothing.
app/services/optimization/trade_analyzer.rb:L46: delete: calculate_volatility is a permanent stub always returning 0.0, stored as TradeAnalytic#volatility on every trade. Drop the field/method or compute it for real.
lib/calibration/lib/options_buying_policy.rb:L43: delete: first branch in moneyness_for is fully covered by the second branch (strong_trend_adx > moderate_trend_adx makes atr_pct check a no-op). Delete the first return; reduces to two branches.
app/services/optimization/indicator_optimizer.rb:L37: shrink: `Rails.logger.X(msg); $stdout.puts msg; $stdout.flush` repeated verbatim 6+ times, same pattern in single_indicator_optimizer.rb and backtest/signal_generator_backtester.rb. Extract `def log(msg, level: :info); Rails.logger.public_send(level, msg); $stdout.puts(msg); $stdout.flush; end`.
app/services/optimization/single_indicator_optimizer.rb:L44: shrink: same dual-logging pattern repeated ~10 times. Same log(msg) helper as above.
app/services/analytics/threshold_optimizer.rb:L34: shrink: compute reimplements the win_rate/avg_win/avg_loss/expectancy formula already in Analytics::Metrics#call (and again in TradeBreakdown#compute). Call Analytics::Metrics.new(trades, []).call instead of re-deriving it three times.

**subtotal: -540**

(research/ and lib/calibration/ otherwise came back clean — deliberate layered pipeline per CLAUDE.md, every class has verified callers.)

## dhan / adapters / telegram / notifications / ai / graphify / event_store

app/services/event_store/replay_engine.rb:L1: delete: ReplayEngine has zero callers anywhere. Nothing replaces it.
app/services/graphify/context_service.rb:L1: delete: Graphify::ContextService (.fetch/.path/.explain) has zero callers outside its own spec. Nothing replaces it.
app/services/adapters/option_chain/null_adapter.rb:L1: delete: NullAdapter has zero callers — CLAUDE.md confirms option chain adapter is always DhanAdapter, even in paper mode. Nothing replaces it.
app/services/notifications/telegram/client.rb:L1: native: hand-rolled Net::HTTP client (chunking, retries, timeouts) reimplements the already-installed but unused `telegram-bot-ruby` gem. Use Telegram::Bot::Client.run / api.sendMessage.
app/services/notifications/telegram/smc_alert.rb:L299: stdlib: escape_html hand-rolls &/</> substitution. ERB::Util.html_escape(text) — already used identically in the sibling file smc_tick_ai_alert.rb:L58.

**subtotal: -170**

## core / concerns / trading / trading_system / strategies / portfolio / ledger / validators

app/services/core/event_bus.rb:L16: yagni: EVENTS declares 7 event types (structure_break, risk_alert, breakeven_lock, trailing_triggered, danger_zone, volatility_spike, trend_flip) never published or subscribed anywhere. Delete the unused entries.
app/services/core/event_bus.rb:L146: delete: stats method never called outside this file, no spec. Delete.
app/services/core/event_bus.rb:L152: delete: clear method never called outside this file, no spec. Delete.
app/services/core/event_bus.rb:L163: delete: subscriber_count method never called outside this file, no spec. Delete.
app/services/trading_system/base_service.rb:L4: yagni: base class with one real subclass (OrderRouter); PositionHeartbeat duck-types the same contract without inheriting, proving the base class isn't required. Delete the class, let OrderRouter stand alone.
app/services/strategies/base.rb:L19: delete: on_start/on_stop/on_position_opened/on_position_closed hooks never invoked by Strategies::Manager or any caller. Delete.
app/services/strategies/manager.rb:L69: shrink: all_statuses computes runner_status twice per slug. `@runners.keys.index_with { |s| runner_status(s) }`.
app/services/portfolio/manager.rb:L4: delete: Portfolio::Manager, zero callers, no spec. Delete the file.
app/services/portfolio/profit_lock_engine.rb:L153: delete: reset_early_giveback_cache! never called anywhere, not even in specs. Delete.
app/services/validators/market_data_cache.rb:L14: delete: update_depth never called — the "depth:" Redis key it writes is never populated, depth_snapshot always misses in production. Delete (or wire to the tick feed if intended).
app/services/ledger/entry_poster.rb:L46: shrink: paper_posting? duplicated verbatim in Ledger::ExitPoster (exit_poster.rb:58). Move to Ledger::Config.paper_posting?(tracker), call from both.
app/services/trading/atr_permission_modifier.rb:L50: shrink: downgrade_for_low_atr and downgrade_for_non_positive_slope (L59-66) have identical bodies. Collapse to one downgrade(permission) method.
app/services/trading/direction_gate.rb:L35: shrink: three near-identical if blocks each log_blocked-then-return-false. Table lookup instead of repeated branches.
app/services/trading/trend_scorer.rb:L4: delete: Trading::TrendScorer (107 lines), no production caller — actual trend scorer in use is Signal::TrendScorer (called from live/underlying_monitor.rb). Delete file and its spec.
app/services/trading/indicators.rb:L6: delete: Trading::Indicators (rsi/atr/supertrend), no production caller, duplicates app/services/indicators/. Delete.
app/services/concerns/dhanhq_error_handler.rb:L5: yagni: `extend ActiveSupport::Concern` + class_methods block (L148-165) exist for `include`-style usage, but every caller invokes DhanhqErrorHandler.handle_dhanhq_error directly via module_function. Delete the Concern extend and class_methods block.

**subtotal: -260**

## jobs / models / lib/trading_system / lib/tasks / config/initializers

lib/trading_system/algo_trading_system:L1: delete: entire 3871-line subsystem (examples/, scripts/, spec/, src/) with its own DhanClient, backtest engine, indicators, strategies — zero references from app/, lib/trading_system/{daemon,bootstrap,supervisor}.rb, or any autoload path. Added once, never wired in. Nothing.
config/initializers/market_stream.rb:L1: delete: entire 186-line file is commented-out dead code, superseded by lib/trading_system/daemon.rb. Nothing.
config/initializers/woods.rb:L14: delete: configures the Woods gem behind `if defined?(Woods)`, but Woods isn't in the Gemfile and nothing calls Woods.*. Nothing.
app/models/concerns/position_tracker_factory.rb:L26: shrink: `instrument.is_a?(Derivative) ? instrument : instrument` returns instrument on both branches. `watchable || instrument`.
app/models/trading_signal.rb:L22: yagni: DIRECTIONS hash maps each symbol to an identical string (bullish: 'bullish'). `DIRECTIONS = %w[bullish bearish avoid].freeze`, compare with `direction == 'bullish'`.
lib/tasks/ws_connection_test.rb:L169: shrink: market-hours vs closed-market branches duplicate the same three-way tick/cache/none check, only log text differs. Extract one resolve_ltp_result(received_tick:, tick_cache_ltp:, redis_ltp:, market_open:) helper.
lib/tasks/ws_feed_diagnostics.rb:L57: shrink: reaches into Live::FeedHealthService's private state via instance_variable_get for @threshold_overrides/@timestamps/@failures, each wrapped in its own rescue. Add public reader methods on FeedHealthService instead.

**subtotal: -4100**

---

## Total

**net: -9472 lines possible.**

Biggest single item: `lib/trading_system/algo_trading_system/` — a 3871-line second trading system (own DhanClient, backtest engine, strategies) sitting in the repo unwired to anything. Second biggest: `app/services/indicators/` has 8 wrapper classes around `BaseIndicator` that nothing calls — the codebase uses `Indicators::Supertrend`, `CandleSeries#adx`, etc. directly everywhere. Third: `app/services/analytics/` (whole dir orphaned) and `app/services/backtest/` (a second, broken, unused mini backtest engine — calls `Portfolio.new` on a class that doesn't exist).

Findings not applied — this is a list only. Before deleting anything: re-verify with a fresh grep at delete time (this review is a snapshot), and check `git log` on each file for recent WIP before assuming dead means abandoned rather than in-progress.
