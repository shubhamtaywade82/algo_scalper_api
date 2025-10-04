# Automated Options Buying System (DhanHQ + Rails)

## 1. Project Goal and Scope

The goal is to implement a high-speed, fully autonomous trading robot within a Ruby on Rails API application, specifically designed for options buying in Indian index derivatives (Nifty, BankNifty, Sensex). The system must execute momentum-based strategies and enforce strict, real-time, position-level risk management.

### Key Objectives
- Low-Latency Data: Utilize DhanHQ WebSockets for all real-time data (LTP, OI) to minimize execution slippage.
- Autonomous Decision Cycle: Schedule a worker to generate signals based on technical indicators (RSI, Supertrend, etc.) and liquid option strike selection.
- Pyramiding Control: Limit exposure to a maximum of 3 positions (Entry + 2 Pyramids) per derivative.
- Delegated Risk Management (Entry): Use `DhanHQ::Models::SuperOrder` to delegate Stop Loss (SL) and Take Profit (TP) enforcement to the broker (OCO/Bracket Order).
- Active Risk Management (Exit): Run a dedicated, persistent 5-second loop that enforces a ₹1,000 minimum profit target and a 5% trailing stop-loss (TSL) from the High-Water Mark (HWM).

## 2. Technical Prerequisites and Setup

### 2.1 Environment
- Language: Ruby (latest stable version)
- Framework: Ruby on Rails (API Mode preferred)
- Asynchronous Processing: Sidekiq (Mandatory for job concurrency)
- Database: PostgreSQL (or equivalent RDBMS)

### 2.2 Gem Dependencies (Gemfile)

The system requires the custom DhanHQ client and thread-safe libraries.

```ruby
# Gemfile excerpt
gem 'DhanHQ', git: 'https://github.com/shubhamtaywade82/dhanhq-client.git', branch: 'main'
gem 'sidekiq' # For asynchronous workers
gem 'concurrent-ruby' # For Concurrent::Map used in TickCache
# Gems required for your existing TA/Candle logic
# gem 'ruby-technical-analysis' (or similar)
# gem 'bigdecimal' (Mandatory for financial precision)
```

### 2.3 Configuration (`config/initializers/dhanhq_config.rb`)

Credentials must be loaded via environment variables (`CLIENT_ID`, `ACCESS_TOKEN`).

```ruby
# config/initializers/dhanhq_config.rb
require 'dhanhq'

DhanHQ.configure_with_env
DhanHQ.logger.level = (ENV['DHANHQ_LOG_LEVEL'] || 'INFO').upcase.then { |level| Logger.const_get(level) }
```

## 3. Architectural Overview (Singleton Services)

The system relies on three persistent, singleton services that replace global variables and manage asynchronous concurrency.

| Layer         | Service (Singleton)             | Role                                                              | Persistence/Frequency                 |
|---------------|---------------------------------|-------------------------------------------------------------------|---------------------------------------|
| I/O & Cache   | TickCache                       | Stores latest LTP and Quote data (`Concurrent::Map`).             | Real-time (Non-blocking)              |
| I/O & WS      | MarketFeedHub                   | Manages `DhanHQ::WS::Client` subscription and broadcasts ticks.   | Persistent Thread (Non-blocking)      |
| Risk          | `Live::RiskManagerService`      | Monitors active positions (P/L, HWM, TSL) and sends exit orders.  | Dedicated 5-second asynchronous loop  |
| Execution     | `TradingService` (via worker)   | Generates signals (QIS) and places Super Orders (EMS).            | Scheduled (e.g., every 5 minutes)     |

## 4. Database Schema Requirements

The following local models are essential for storing configuration, persistent data, and tracking position status.

| Model            | Purpose                                                                 | Key Attributes Required                                                   |
|------------------|-------------------------------------------------------------------------|---------------------------------------------------------------------------|
| Instrument       | Index definition (Nifty, BankNifty). Uses CandleExtension for indicators. | `security_id`, `exchange_segment`, `symbol_name`                          |
| Derivative       | Option/Future contract lookup. Links strike/expiry to `security_id`.     | `instrument_id`, `security_id`, `strike_price`, `expiry_date`, `lot_size` |
| PositionTracker  | Stores state for the TSL logic. Linked to the live Dhan position.        | `order_no` (Dhan order ID), `security_id`, `status`, `high_water_mark_pnl` |

## 5. Implementation Checklist

### Tier 1: Data and Subscription (Foundation)

| Task                  | Detail                                                                 | DhanHQ Tool                                      |
|-----------------------|------------------------------------------------------------------------|--------------------------------------------------|
| 1. TickCache          | Implement `TickCache.instance.put(tick)` using `Concurrent::Map`.      | -                                                |
| 2. MarketFeedHub      | Start `DhanHQ::WS::Client(mode: :full)`. Subscribe initial indices.    | `DhanHQ::WS::Client`, `:full` mode               |
| 3. Model Subscription | Implement `#subscribe` / `#unsubscribe` in helpers via `MarketFeedHub`. | Delegated to `MarketFeedHub`                     |
| 4. OrderUpdateHandler | Handle fills and update `PositionTracker` status to `:active`.         | `DhanHQ::WS::Orders::Client`                     |
| 5. DataFetcherService | REST wrappers: `fetch_historical_data`, `fetch_option_chain`.          | `DhanHQ::Models::HistoricalData`, `OptionChain`  |

### Tier 2: Risk Management Loop

| Task                 | Detail                                                                                         | Logic/Constraint                                 |
|----------------------|------------------------------------------------------------------------------------------------|--------------------------------------------------|
| 6. RiskManagerService| Implement the 5-second asynchronous loop using a background thread (`start_loop!`).            | Continuous execution (`sleep(5)` interval)       |
| 7. P/L Calculation   | Calculate `pnl_rupees` based on `DhanHQ::Models::Position.active` and live LTP from TickCache. | Must use `BigDecimal` for accuracy.              |
| 8. Trailing Logic    | Once `pnl_rupees >= ₹1,000`, track `high_water_mark_pnl` in `PositionTracker`.                 | TSL: exit if PNL drops by 5% (`EXIT_DROP_PCT`).  |
| 9. Exit Execution    | On TSL signal, call `position.exit!` and `position.unsubscribe`.                               | `DhanHQ::Models::Position#exit!` (Market Order)  |

### Tier 3: Trading Intelligence and Execution (QIS/EMS)

| Task                    | Detail                                                                                                                        | Critical Linkage                                              |
|-------------------------|-------------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------|
| 10. TrendIdentifier (QIS)| Implement signal logic using `instrument.rsi`, `instrument.supertrend_signal`, etc., from 5-minute bars.                     | `Instrument.candles` via `DataFetcherService`                  |
| 11. StrikeSelector (QIS) | Use Option Chain data (volume, OI) to find the optimal strike, then look up `security_id` in the local `Derivative` model.   | `DhanHQ::OptionChain` lacks `security_id`; local lookup needed |
| 12. TradingWorker (EMS)  | Scheduled job orchestrating: Signal → Pyramiding Check → Execution. Trigger at candle close (e.g., every 5 min).             | Reliable external scheduler (Clockwork, etc.)                  |
| 13. Order Placement      | Call `DhanHQ::Models::SuperOrder.create` with `bo_stop_loss_value` and `bo_profit_value`.                                     | Broker-managed OCO/Bracket risk delegation                     |

## 6. Trading Constraints (Non-Negotiables)

| Constraint        | Value / Method                                                 | Rationale                                                     |
|-------------------|----------------------------------------------------------------|---------------------------------------------------------------|
| Core Asset        | Index Options (Nifty, BankNifty, Sensex)                       | Focus of the strategy.                                        |
| Risk Delegation   | `DhanHQ::Models::SuperOrder` with `bo_stop_loss_value`         | Minimizes slippage and ensures reliable SL execution.[1]      |
| Pyramiding Limit  | Max 3 active positions (`Position.active.count`)               | Enforced in `TradingService`.                                 |
| Exit Frequency    | Every 5 seconds                                                | TSL monitoring interval.                                      |
| Min Profit Lock   | ₹1,000                                                         | Profit locking threshold.                                     |
| Trailing Stop     | 5% drop from High-Water Mark (HWM)                             | Exit condition for positions that cease trending.             |
| Identification    | All trades must use `security_id` from the local `Derivative`. | Mandatory API requirement for orders and subscriptions.[1]    |

[^1]: Refer to the DhanHQ client documentation for additional context on bracket order parameters and security identifiers.
