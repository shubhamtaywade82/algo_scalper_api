# System Components Map

This document details the responsibilities, key files, and dependencies for each major component of the trading system.

## 1. Trading Supervisor & Bootstrap
The entry point for the trading engine.

- **Responsibilities**:
    - Service registration and lifecycle management (Start/Stop).
    - Startup reconciliation (Position Sync).
    - Environment-based initialization (Web vs. Daemon vs. Test).
- **Key Files**:
    - `lib/trading_system/supervisor.rb`: The orchestrator class.
    - `lib/trading_system/bootstrap.rb`: Wiring logic for service registration.
    - `config/initializers/trading_supervisor.rb`: Rails hook for initialization.
- **Dependencies**: All registered services.

## 2. Market Data Feed (`:market_feed`)
High-performance real-time data ingestion.

- **Responsibilities**:
    - WebSocket connection management with DhanHQ.
    - Multi-instrument subscription handling.
    - Tick data normalization and broadcasting (ActionCable).
    - Redis-based tick caching for downstream consumption.
- **Key Files**:
    - `app/services/live/market_feed_hub_service.rb`: Main service.
    - `app/services/live/tick_cache.rb`: In-memory caching logic.
    - `app/services/live/redis_tick_cache.rb`: Persistence layer for ticks.
- **Dependencies**: `DhanHQ::Client`, `Redis`.

## 3. Signal Generation (`:signal_scheduler`)
The "Brain" of the scalper.

- **Responsibilities**:
    - Scheduling analysis intervals for indices (NIFTY, BANKNIFTY, etc.).
    - Expiry-based prioritization.
    - Multi-timeframe trend analysis using Supertrend and ADX.
    - SMC (Smart Money Concepts) alignment verification.
- **Key Files**:
    - `app/services/signal/scheduler.rb`: Orchestrator.
    - `app/services/signal/engine.rb`: Core logic.
    - `app/services/signal/trend_scorer.rb`: Score calculation.
- **Dependencies**: `MarketFeedHub`, `Smc::Scanner`.

## 4. Risk Management (`:risk_manager`)
The safety layer for active positions.

- **Responsibilities**:
    - Real-time PnL tracking for all active positions.
    - Enforcement of Exit Rules (SL, TP, Trailing Stop, Time-Based).
    - Emergency Circuit Breaking.
    - Position status transitions (Active -> Exited).
- **Key Files**:
    - `app/services/live/risk_manager_service.rb`: Monitoring loop.
    - `app/services/live/unified_exit_checker.rb`: Logic prioritization.
    - `app/services/live/trailing_engine.rb`: Dynamic stop-loss logic.
- **Dependencies**: `ActiveCache`, `ExitEngine`, `CircuitBreaker`.

## 5. Order Execution (`:order_router`)
Unified hub for market interaction.

- **Responsibilities**:
    - Transparently routing orders to either Live (DhanHQ) or Paper trading engines.
    - Request/Response normalization.
    - Position persistence in `PositionTracker`.
- **Key Files**:
    - `app/services/trading_system/order_router.rb`: Unified interface.
    - `app/services/orders/placer.rb`: Live order placement.
    - `app/services/orders/entry_manager.rb`: Entry lifecycle handler.
- **Dependencies**: `DhanHQ::Client`, `PositionTracker`.

## 6. Smart Money Concepts (`:smc_scanner`)
Advanced trend and structure analysis.

- **Responsibilities**:
    - Scanning high timeframes (HTF) for market structure breaks (BOS/CHoCH).
    - Detecting Order Blocks and Fair Value Gaps (FVG).
    - Providing "Institutional Sentiment" to the Signal Engine.
- **Key Files**:
    - `app/services/smc/scanner.rb`: Main scanner logic.
    - `app/models/smc_structure.rb`: Persistence for detected patterns.
- **Dependencies**: `Indicators::SMC`.
