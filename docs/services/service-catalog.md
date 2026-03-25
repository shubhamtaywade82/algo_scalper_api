# Service Catalog

Comprehensive list of major service classes in the Algo Scalper API trading system, aligned with the current Rails 8 codebase.

## Trading Services

| Service | File | Purpose |
| :--- | :--- | :--- |
| `Signal::Scheduler` | `app/services/signal/scheduler.rb` | Orchestrates 30-second index scans and dispatches work to `Signal::Engine`. |
| `Signal::Engine` | `app/services/signal/engine.rb` | Runs Supertrend/ADX/SMC-based analysis and produces structured signal results per index. |
| `MarketContext::RegimeComposer` | `app/services/market_context/regime_composer.rb` | Composes `MarketRegimeDetector` with structure/volatility/participation into a `RegimeSnapshot` and conviction score (optional; gated by `config/algo.yml` `market_context.enabled`). |
| `Options::ChainSignalExtractor` | `app/services/options/chain_signal_extractor.rb` | Derives chain confirmation from raw `chain_data` + `FlowAnalyzer` history (optional gate input). |
| `Trading::MarketPermissionGate` | `app/services/trading/market_permission_gate.rb` | Optional hard entry filter after strike qualification (`market_context.gate.enabled`). |
| `Trading::StrategyProfileSelector` | `app/services/trading/strategy_profile_selector.rb` | Maps regime snapshot to `strategy_profile` for metadata and trailing overrides. |
| `Signal::TrendScorer` | `app/services/signal/trend_scorer.rb` | Computes multi-timeframe trend scores (0–21) used for dynamic risk allocation. |
| `Entries::EntryGuard` | `app/services/entries/entry_guard.rb` | Enforces the 10-guard entry pipeline (circuit breaker, cooldown, exposure, limits) before any trade. |
| `Options::ChainAnalyzer` | `app/services/options/chain_analyzer.rb` | Analyzes live option chains, scores strikes (liquidity, OI, spread, IV), and selects ATM±1 candidates. |
| `Orders::EntryManager` | `app/services/orders/entry_manager.rb` | High-level entry orchestrator that ties together signals, `EntryGuard`, capital allocation, and ActiveCache. |
| `Orders::Manager` | `app/services/orders/manager.rb` | Simple façade around `Orders::Placer` for placing direct market orders with tagged client IDs. |
| `TradingSystem::OrderRouter` | `app/services/trading_system/order_router.rb` | Routes exit and management orders through the configured gateway (paper/live). |

## Live & Risk Services

| Service | File | Purpose |
| :--- | :--- | :--- |
| `Live::MarketFeedHub` | `app/services/live/market_feed_hub.rb` | Singleton WebSocket hub for DhanHQ ticks; manages subscriptions and dispatches ticks to caches and PnL pipeline. |
| `Live::MarketFeedHubService` | `app/services/live/market_feed_hub_service.rb` | Adapter that exposes `start/stop` for `TradingSystem::Supervisor` while delegating to `MarketFeedHub`. |
| `Live::RiskManagerService` | `app/services/live/risk_manager_service.rb` | Subscribes to `EventBus(:ltp)` for per-tick risk checks and runs a 5s enforcement loop for all exit rules. |
| `Live::UnifiedExitChecker` | `app/services/live/unified_exit_checker.rb` | Central exit decision engine; evaluates all configured exit rules in priority order. |
| `Live::ExitEngine` | `app/services/live/exit_engine.rb` | Single source of truth for placing and tracking exit orders, delegating execution to the configured gateway. |
| `Live::RedisTickCache` | `app/services/live/redis_tick_cache.rb` | Redis-backed write-through tick store keyed by `segment:security_id`. |
| `Live::RedisPnlCache` | `app/services/live/redis_pnl_cache.rb` | Redis-backed PnL snapshot store used by `RiskManagerService` and the dashboard. |
| `Live::PositionSyncService` | `app/services/live/position_sync_service.rb` | Reconciles `PositionTracker` records with broker state on startup and during periodic sync. |

## Specialized Engines

| Service | File | Purpose |
| :--- | :--- | :--- |
| `Smc::Scanner` | `app/services/smc/scanner.rb` | Smart Money Concepts scanner for order blocks, FVGs, and structure changes (BOS/CHoCH). |
| `Smc::AiAnalyzer` | `app/services/smc/ai_analyzer.rb` | LLM-backed analyzer that produces AI technical analysis for configured indices. |
| `Risk::CircuitBreaker` | `app/services/risk/circuit_breaker.rb` | Redis-backed global kill-switch with `/api/circuit_breaker` control endpoints. |
| `Live::TimeRegimeService` | `app/services/live/time_regime_service.rb` | Adjusts behaviour and guardrails based on market session windows (open, lunch, close). |
| `Market::MarketRegimeResolver` | `app/services/market/market_regime_resolver.rb` | Determines trending/ranging regimes for indices and feeds decisions into signal and risk components. |
