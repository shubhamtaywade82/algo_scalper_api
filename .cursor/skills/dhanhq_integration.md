# DhanHQ Integration Guide

Integration details for the DhanHQ API used for market data and order execution.

## Authentication
- **DhanMcpService**: Manages API keys and token rotation via `Dhan::TokenManager`.
- Always verify connection status before starting the `TradingSystem::Daemon`.

## Market Data (WebSocket)
- **Feed**: `MarketTick` objects pushed via ActionCable or internal bus.
- **Throughput**: Optimized for low-latency handling of NIFTY 50 and SENSEX constituents.

## Order Execution
- **Endpoints**: `POST /orders` for entry and exit.
- **Safety**: Use `dhanhq.enable_orders: false` in `algo.yml` for paper trading even when using live data.

## Historical Data
- OHLCV data typically fetched for the last 5 days to build structural context on startup.
- Endpoint: `POST /charts/intraday`.
