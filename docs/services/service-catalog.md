# Service Catalog

Comprehensive list of major service classes in the ARES Trading System.

## Trading Services

| Service | File | Purpose |
| :--- | :--- | :--- |
| `Signal::Scheduler` | `app/services/signal/scheduler.rb` | High-level orchestrator for periodic index scanning. |
| `Signal::Engine` | `app/services/signal/engine.rb` | Evaluates indicators and generates bullish/bearish signals. |
| `Signal::TrendScorer` | `app/services/signal/trend_scorer.rb` | Multi-timeframe trend analysis service. |
| `Entries::EntryGuard` | `app/services/entries/entry_guard.rb` | Validates risk and exposure before placing orders. |
| `Options::ChainAnalyzer` | `app/services/options/chain_analyzer.rb` | Selects optimal strikes based on ATR and proximity. |
| `Orders::Manager` | `app/services/orders/manager.rb` | Orchestrates entry order placement. |
| `TradingSystem::OrderRouter` | `app/services/trading_system/order_router.rb` | Routes order requests to Live or Paper gateways. |

## Live & Risk Services

| Service | File | Purpose |
| :--- | :--- | :--- |
| `Live::RiskManagerService` | `app/services/live/risk_manager_service.rb` | Monitoring loop for active positions. |
| `Live::MarketFeedHub` | `app/services/live/market_feed_hub.rb` | Main WebSocket listener for real-time market data. |
| `Live::UnifiedExitChecker` | `app/services/live/unified_exit_checker.rb` | Decision matrix for position exits. |
| `Live::ExitEngine` | `app/services/live/exit_engine.rb` | Execution logic for closing broker positions. |
| `Live::RedisTickCache` | `app/services/live/redis_tick_cache.rb` | Shared state store for real-time prices. |
| `Live::PositionSyncService` | `app/services/live/position_sync_service.rb` | Reconciles local data with broker data. |

## Specialized Engines

| Service | File | Purpose |
| :--- | :--- | :--- |
| `Smc::Scanner` | `app/services/smc/scanner.rb` | Smart Money Concepts (BOS/CHoCH) detector. |
| `Smc::AiAnalyzer` | `app/services/smc/ai_analyzer.rb` | LLM-based technical analysis for confirmation. |
| `Risk::CircuitBreaker` | `app/services/risk/circuit_breaker.rb` | Emergency kill-switch for trading activity. |
| `Live::TimeRegimeService` | `app/services/live/time_regime_service.rb` | Adjusts behavior based on market session time. |
| `Market::Calendar` | `app/services/market/calendar.rb` | Logic for trading holidays and sessions. |
