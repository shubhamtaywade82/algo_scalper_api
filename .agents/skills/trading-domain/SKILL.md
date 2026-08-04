---
name: trading-domain
description: >
  Domain knowledge for an automated crypto/equity futures and options trading system.
  Covers order execution, position management, broker integration, risk management,
  signal processing, and market data handling. Use when implementing, refactoring,
  or reviewing trading logic in Ruby/Rails codebases.
---

# Trading Domain Knowledge & Architecture Guide

## Core Entities

- **Instrument**: A tradeable contract (symbol, exchange, lot size, tick size, expiry, margin requirement). An Instrument is a resolved, validated domain object with all properties needed for order placement.
- **Order**: An intent to buy or sell a quantity of an Instrument at a specified price (or market). Has an explicit lifecycle (`created` $\rightarrow$ `validated` $\rightarrow$ `submitted` $\rightarrow$ `acknowledged` $\rightarrow$ `filled`/`partially_filled` $\rightarrow$ `closed`). An Order is NOT a trade.
- **Position**: The net exposure resulting from filled orders (quantity, avg price, realized PnL, unrealized PnL, margin used). OPEN when `quantity != 0`, FLAT when `quantity == 0`.
- **Trade (Execution)**: Single fill event from a broker. One Order can produce multiple Trades (partial fills). Trades are immutable records.
- **Signal**: A computed trading decision (`BUY`/`SELL`/`CLOSE`/`HOLD`) for an Instrument with suggested quantity and price. Produced by strategies. Signals are NOT orders and become orders only after passing risk checks.
- **Strategy**: Rules that produce Signals from market data. Strategies do NOT place orders, do NOT manage risk, and do NOT know about brokers.
- **RiskRule**: A constraint that must pass before a Signal becomes an Order (max position size, max daily loss, margin availability, max orders per minute, circuit breaker).
- **Broker**: An external execution venue (Dhan, Zerodha, Upstox). The system communicates via adapters. Domain NEVER knows which broker is being used.
- **MarketData**: Real-time or historical price/volume information (ticks, candles, orderbook). READ-ONLY input to strategies.

---

## 10 Domain Invariants (NEVER Violate)

1. **Signal $\rightarrow$ RiskCheck $\rightarrow$ Order**: A Signal NEVER directly creates an Order without passing RiskCheck.
2. **Order $\rightarrow$ OrderExecutor $\rightarrow$ BrokerAdapter**: An Order NEVER directly calls a Broker API.
3. **Position derived from Trades**: `Position.quantity = sum(Trade.quantity * direction)`. Never set directly.
4. **Strategy reads NO database execution state**: Strategies receive market data and emit signals. Pure logic.
5. **Pre-trade Risk Evaluation**: Risk checks are evaluated BEFORE submission, not after.
6. **Asynchronous Fill Assumption**: Order submitted $\neq$ Order filled. Handle async fills and webhooks cleanly.
7. **Paise Integer Money**: Money is stored as integer paise (or equivalent). Never float. `185450` paise = ₹1854.50.
8. **Integer Lot Quantities**: Quantity is integer lots. Never fractional for futures/options.
9. **Explicit State Transitions**: Every state transition is explicit and logged. No side-effect callbacks.
10. **Idempotency**: Processing the same broker event twice MUST NOT create duplicate trades or double-count positions.

---

## Domain Boundaries

```text
┌─────────────────────────────────────────────────────┐
│                    PRESENTATION                      │
│  Controllers, WebSockets, APIs, Dashboards          │
└────────────────────────┬────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────┐
│                   APPLICATION                        │
│  Use cases: PlaceOrder, ClosePosition, RunStrategy  │
│  Orchestration only. No domain logic.               │
└────────────────────────┬────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────┐
│                     DOMAIN                           │
│  Order, Position, Trade, Signal, RiskRule           │
│  State machines, invariants, calculations           │
│  NO Rails. NO HTTP. NO database. Pure Ruby.        │
└────────────────────────┬────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────┐
│                 INFRASTRUCTURE                       │
│  BrokerAdapter, MarketDataFeed, Persistence,        │
│  Redis, WebSocket clients, Jobs                     │
└─────────────────────────────────────────────────────┘
```

- Domain must not depend on Infrastructure.
- Infrastructure implements Domain interfaces.
- Application orchestrates Domain + Infrastructure.
