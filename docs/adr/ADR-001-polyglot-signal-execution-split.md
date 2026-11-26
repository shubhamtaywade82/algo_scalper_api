# ADR-001: Polyglot Architecture Split (Rails Core & Node Execution Agent)

## Status
Accepted

## Context
Automated options trading on Indian exchanges requires two distinct processing profiles:
1. **Relational & Analytical Pipeline**: Continuous market data capture, multi-timeframe candle series generation (1m, 5m, 15m), Smart Money Concept (SMC) order-flow identification, technical analysis indicators, database persistence (PostgreSQL), and background job orchestration (Solid Queue).
2. **Ultra-Low Latency Execution & Greek Risk Management**: High-speed asynchronous WebSocket feeds, sub-millisecond posture evaluation, dynamic option Greek calculations, and fast trailing stop-loss adjustments.

Attempting to run both within a monolithic Ruby on Rails process creates thread-contention and garbage collection latency spikes during high-volatility gamma bursts.

## Decision
We split responsibilities into a polyglot monorepo structure:
- **`core/` (Ruby on Rails 8)**: Acts as the central intelligence and data hub. It processes market ticks, maintains historical candles, computes technical indicators and market regimes, and emits standardized `TradeIntent` payloads (`trade-intent/1`).
- **`agent/` (TypeScript / Node.js)**: Acts as the dedicated execution and risk engine. It polls trade intents, evaluates execution postures (`SCOUT`, `ALIGNED`, `CONFIRMED`), selects ATM/ITM strikes based on live option chain liquidity, and actively manages trailing stops and time stops.
- **Contract Boundary**: Communication occurs strictly over internal HTTP (`POST /api/trade_intents`) with Redis-based heartbeat observability (`trading:agent:snapshot`).

## Consequences
- **Positive**: Rails focuses on robust persistence, jobs, and relational models; TypeScript focuses on high-speed async execution and lightweight concurrency.
- **Positive**: Full test coverage runs in parallel (1,713 TypeScript unit tests in 15s; SolidJS Vitest in 3s).
- **Negative**: Requires maintaining two runtime environments (Ruby 4.0 + Node 22+) in local development and production deployments.
