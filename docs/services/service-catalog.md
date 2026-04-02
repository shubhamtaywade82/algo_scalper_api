# Service Catalog

Comprehensive list of major service classes in the Algo Scalper API trading system, aligned with the current Rails 8 codebase.

## Trading Signal Services

| Service | File | Purpose |
|---------|------|---------|
| `Signal::Scheduler` | `app/services/signal/scheduler.rb` | Orchestrates 30-second index scans and dispatches work to `Signal::Engine`. |
| `Signal::Engine` | `app/services/signal/engine.rb` | Runs Supertrend/ADX/SMC-based analysis in 13 steps and produces structured signal results per index. Supports optional market context gate. |
| `Signal::TrendScorer` | `app/services/signal/trend_scorer.rb` | Computes multi-timeframe trend scores (0-21) used for dynamic risk allocation. |
| `Signal::StateTracker` | `app/services/signal/state_tracker.rb` | Prevents duplicate signal generation for same direction/candle. |
| `Signal::MomentumValidator` | `app/services/signal/momentum_validator.rb` | Scores momentum 0-3 from price action for entry quality. |
| `Trading::PermissionResolver` | `app/services/trading/permission_resolver.rb` | SMC + AVRZ permission gating (returns `:allowed`, `:blocked`, or `:neutral`). |
| `Entries::EntryFilterEngine` | `app/services/entries/entry_filter_engine.rb` | Pre-guard filter for structure/liquidity/volatility alignment. |

## Market Context Services (Optional Alpha Layer)

Enabled when `market_context.enabled: true` in `config/algo.yml` (default: false).

| Service | File | Purpose |
|---------|------|---------|
| `MarketContext::RegimeComposer` | `app/services/market_context/regime_composer.rb` | Composes `MarketRegimeDetector` + structure/volatility/participation into a `RegimeSnapshot` with conviction score. |
| `MarketContext::RegimeSnapshot` | `app/services/market_context/regime_snapshot.rb` | Value object: structure, strength, volatility_state, participation, conviction_score, raw diagnostics. |
| `Options::ChainSignalExtractor` | `app/services/options/chain_signal_extractor.rb` | Chain-side confirmation (PCR, flow scores, ATM premium expansion vs FlowAnalyzer cache). |
| `Trading::MarketPermissionGate` | `app/services/trading/market_permission_gate.rb` | Optional hard entry filter when `market_context.gate.enabled: true`. Logs `entry_blocked` with `stage: market_permission_gate`. |
| `Trading::StrategyProfileSelector` | `app/services/trading/strategy_profile_selector.rb` | Maps `RegimeSnapshot` to `strategy_profile` symbol stored in entry_metadata and tracker meta. |

## Entry Services

| Service | File | Purpose |
|---------|------|---------|
| `Entries::EntryGuard` | `app/services/entries/entry_guard.rb` | Orchestrates the 20-guard pipeline + post-pipeline checks. Single entry point for all trade entries. |
| `Entries::EntryGuardPipeline` | `app/services/entries/entry_guard_pipeline.rb` | Runs 20 guards in sequence; first block wins. |
| `Entries::BosEntryEngine` | `app/services/entries/bos_entry_engine.rb` | Break-of-Structure entry state machine for BOS-based entries. |
| `Guards::ExpiryWeekPowerTrendGuard` | `app/services/entries/guards/expiry_week_power_trend_guard.rb` | Detects expiry-week afternoon power trend (ADX >= 40 + monthly expiry + 12:00-13:45). Enriches context, never blocks. |
| `Guards::TimeRegimeGuard` | `app/services/entries/guards/time_regime_guard.rb` | Enforces time-of-day entry rules; bypasses S3 block when `expiry_power_trend = true`. |
| `Guards::CircuitBreakerGuard` | `app/services/entries/guards/circuit_breaker_guard.rb` | Checks `Risk::CircuitBreaker.instance.tripped?`. |
| `Guards::MiddayQualityGuard` | `app/services/entries/guards/midday_quality_guard.rb` | Quality gate; bypassed when ADX >= `trending_adx_bypass` (default 28). |
| `Guards::LossStreakGuard` | `app/services/entries/guards/loss_streak_guard.rb` | Blocks on consecutive losses >= threshold (default 2). |
| `Guards::EdgeFailureGuard` | `app/services/entries/guards/edge_failure_guard.rb` | Checks `Live::EdgeFailureDetector.instance.entries_paused?`. |

## Options Services

| Service | File | Purpose |
|---------|------|---------|
| `Options::ChainAnalyzer` | `app/services/options/chain_analyzer.rb` | Analyzes live option chains, scores strikes (liquidity, OI, spread, IV), selects ATM±1 candidates. |
| `Options::DerivativeChainAnalyzer` | `app/services/options/derivative_chain_analyzer.rb` | Lower-level derivative chain access and expiry resolution. |
| `Options::GammaRampDetector` | `app/services/options/gamma_ramp_detector.rb` | Detects gamma pressure zones from option chain data. |
| `Options::FlowAnalyzer` | `app/services/options/flow_analyzer.rb` | Tracks strike-level flow history for chain signal extraction. |
| `Adapters::OptionChain::DhanAdapter` | `app/services/adapters/option_chain/dhan_adapter.rb` | Live option chain fetch from DhanHQ API (always wired, even in paper mode). |

## Capital and Order Services

| Service | File | Purpose |
|---------|------|---------|
| `Capital::Allocator` | `app/services/capital/allocator.rb` | Rupee-based and percentage-based lot sizing. Central position sizing authority. |
| `Capital::DynamicRiskAllocator` | `app/services/capital/dynamic_risk_allocator.rb` | Trend-score-based dynamic risk sizing. |
| `Trading::CapitalAllocator` | `app/services/trading/capital_allocator.rb` | Lot calculation and max_lots cap. |
| `Orders::GatewayFactory` | `app/services/orders/gateway_factory.rb` | Selects `GatewayPaper` or `GatewayLive` at boot based on config. |
| `Orders::GatewayLive` | `app/services/orders/gateway_live.rb` | Real DhanHQ execution with retry and token auto-heal. Requires `PLACE_ORDER=true`. |
| `Orders::GatewayPaper` | `app/services/orders/gateway_paper.rb` | Simulated fills at current LTP with synthetic order updates. |
| `Orders::Placer` | `app/services/orders/placer.rb` | DhanHQ API calls with idempotency. Live calls blocked unless `PLACE_ORDER=true`. |
| `Orders::EntryManager` | `app/services/orders/entry_manager.rb` | High-level entry orchestrator tying signals, EntryGuard, capital allocation, and ActiveCache. |
| `TradingSystem::OrderRouter` | `app/services/trading_system/order_router.rb` | Routes exit and management orders through configured gateway. |

## Live & Risk Services

| Service | File | Purpose |
|---------|------|---------|
| `Live::MarketFeedHub` | `app/services/live/market_feed_hub.rb` | Singleton WebSocket hub for DhanHQ ticks; manages subscriptions and distributes to caches and PnL pipeline. |
| `Live::MarketFeedHubService` | `app/services/live/market_feed_hub_service.rb` | Adapter exposing `start/stop` for `TradingSystem::Supervisor`. |
| `Live::PnlUpdaterService` | `app/services/live/pnl_updater_service.rb` | 250ms PnL flush: batch compute, write to `RedisPnlCache`, publish EventBus `:ltp`. |
| `Live::RiskManagerService` | `app/services/live/risk_manager_service.rb` | Per-tick risk checks via EventBus; 5s enforcement loop for all exit rules. |
| `Live::UnifiedExitChecker` | `app/services/live/unified_exit_checker.rb` | Evaluates all exit conditions in priority order (per-tick path). |
| `Live::ExitEngine` | `app/services/live/exit_engine.rb` | Single source of truth for placing and tracking exit orders. |
| `Live::TrailingEngine` | `app/services/live/trailing_engine.rb` | Trailing stop management (tiered, direct, gamma-aware). |
| `Live::ReconciliationService` | `app/services/live/reconciliation_service.rb` | Broker/DB state sync every 30s. |
| `Live::PositionSyncService` | `app/services/live/position_sync_service.rb` | Startup + on-demand broker/DB position reconciliation. |
| `Live::RedisTickCache` | `app/services/live/redis_tick_cache.rb` | Redis-backed tick store keyed by `segment:security_id`. |
| `Live::RedisPnlCache` | `app/services/live/redis_pnl_cache.rb` | Redis-backed PnL snapshot store; read by RiskManager and dashboard. |
| `Live::TickCache` | `app/services/live/tick_cache.rb` | In-memory + Redis write-through tick store. |
| `Live::TickQuery` | `app/services/live/tick_query.rb` | Authoritative LTP read boundary (returns nil on cache miss). |
| `Live::PositionIndex` | `app/services/live/position_index.rb` | In-memory `security_id → PositionTracker` lookup (O(1)). |
| `Live::TimeRegimeService` | `app/services/live/time_regime_service.rb` | Determines current market session window (S1-S4). |
| `Live::EdgeFailureDetector` | `app/services/live/edge_failure_detector.rb` | Detects when strategy edge is lost for an index; pauses entries for 60 min. |
| `Live::StatsNotifierService` | `app/services/live/stats_notifier_service.rb` | Sends daily stats via Telegram at market close. |
| `Live::OrderUpdateHub` | `app/services/live/order_update_hub.rb` | DhanHQ order update WebSocket connection. |
| `Live::OrderUpdateHandler` | `app/services/live/order_update_handler.rb` | Handles fill/cancel events from order update WebSocket; idempotent. |

## Risk Services

| Service | File | Purpose |
|---------|------|---------|
| `Risk::CircuitBreaker` | `app/services/risk/circuit_breaker.rb` | Redis-backed global kill switch. Singleton. API: `/api/circuit_breaker`. |
| `Risk::Rules::StructureInvalidationRule` | `app/services/risk/rules/structure_invalidation_rule.rb` | Exit rule: structure/thesis invalidated. |
| `Risk::Rules::PremiumMomentumFailureRule` | `app/services/risk/rules/premium_momentum_failure_rule.rb` | Exit rule: premium momentum stalled/failed. |
| `Risk::Rules::PercentagePnlRule` | `app/services/risk/rules/percentage_pnl_rule.rb` | Exit rule: target PnL% reached (DECIMAL). |
| `Risk::Rules::TimeStopRule` | `app/services/risk/rules/time_stop_rule.rb` | Exit rule: max hold duration exceeded. |

## SMC Services

| Service | File | Purpose |
|---------|------|---------|
| `Smc::Scanner` | `app/services/smc/scanner.rb` | 5-minute SMC pattern detection (order blocks, FVG, BOS/CHoCH). |
| `Smc::BiasEngine` | `app/services/smc/bias_engine.rb` | Computes SMC directional bias (bullish/bearish/neutral). |
| `Smc::AiAnalyzer` | `app/services/smc/ai_analyzer.rb` | LLM-backed analysis for SMC pattern interpretation. |

## AI Services

| Service | File | Purpose |
|---------|------|---------|
| `Services::Ai::OllamaClient` | `lib/services/ai/ollama_client.rb` | Thin wrapper around `Ollama::Client`. Provides `chat`, `generate`, `chat_stream`. Serializes concurrent requests. Auto-selects best model. |
| `Services::Ai::TechnicalAnalysisAgent` | `lib/services/ai/technical_analysis_agent.rb` | Multi-turn LLM-backed technical analysis agent for NIFTY and SENSEX. |

**Note:** The AI layer uses Ollama (local LLM) via the `ollama-client` gem (`~> 1.1`). OpenAI/ruby-openai gems have been removed.

## Positions Services

| Service | File | Purpose |
|---------|------|---------|
| `Positions::ActiveCacheService` | `app/services/positions/active_cache_service.rb` | In-memory + Redis active positions cache managed by Supervisor. |
| `Positions::ActiveCache` | `app/services/positions/active_cache.rb` | Core in-memory position state. |
| `Positions::Serializer` | `app/services/positions/serializer.rb` | JSON serialization for API responses. |
| `Positions::MetadataResolver` | `app/services/positions/metadata_resolver.rb` | Derives index key, direction, underlying metadata from PositionTracker. |
| `Positions::TrailingConfig` | `app/services/positions/trailing_config.rb` | Trailing stop configuration (DECIMAL values; DEFAULT_PEAK_DRAWDOWN_PCT: 0.05, etc.). |
| `Positions::DrawdownSchedule` | Module in `lib/positions/` | Calculates allowed drawdown schedule (upward and reverse/adaptive). |
| `Positions::HighWaterMark` | `app/services/positions/high_water_mark.rb` | Tracks and updates position HWM. |

## Dhan Integration Services

| Service | File | Purpose |
|---------|------|---------|
| `Dhan::TokenManager` | `app/services/dhan/token_manager.rb` | 3-tier token provisioning: authority server → TOTP auto-refresh → static ENV. |
