# API CONTRACT — Inter-Module Interfaces

Formal contracts between modules. All modules must respect these interfaces.

---

## EventBus Events

| Event Name                   | Publisher            | Subscriber(s)             | Payload Keys                     |
|------------------------------|----------------------|---------------------------|----------------------------------|
| `market_data.tick`           | WebsocketFeed        | IndicatorEngine, Strategies | `symbol`, `ltp`, `volume`, `oi`, `timestamp` |
| `market_data.candle_closed`  | CandleLoader / BacktestEngine | IndicatorEngine, Strategies | `candle` (Candle struct)         |
| `indicator.updated`          | IndicatorBase        | Strategies                | `name`, `symbol`, `value`, `timestamp` |
| `strategy.signal`            | StrategyBase         | ExecutionEngine           | `signal`, `strategy`, `symbol`, `stop_loss`, `target`, `reason` |
| `order.placed`               | OrderManager         | PositionTracker, Logger   | `order` (Order struct)           |
| `order.filled`               | OrderManager         | PositionTracker, Logger   | `order` (Order struct)           |
| `order.cancelled`            | OrderManager         | PositionTracker, Logger   | `order` (Order struct)           |
| `order.rejected`             | OrderManager         | Logger, RiskEngine        | `order`, `reason`                |
| `position.opened`            | PositionTracker      | Logger                    | `position`                       |
| `position.closed`            | PositionTracker      | Logger, PnlCalculator     | `position`, `pnl`                |
| `risk.daily_limit_breached`  | RiskEngine           | ExecutionEngine, Logger   | `daily_loss_pct`, `capital`      |
| `risk.order_rejected`        | RiskEngine           | Logger                    | `reason`, `order`                |

---

## DhanClient Public Methods

```ruby
# Place a new order. Returns Order struct with orderId and status.
DhanClient#place_order(
  symbol:,          # String
  security_id:,     # String
  transaction_type:,# "BUY" | "SELL"
  order_type:,      # "MARKET" | "LIMIT" | "STOP_LOSS" | "STOP_LOSS_MARKET"
  quantity:,        # Integer
  price: 0.0,       # Float (0 for market)
  trigger_price: 0.0
) → Order

# Cancel an order by ID.
DhanClient#cancel_order(order_id:) → Order

# Fetch all orders for today.
DhanClient#orders → Array<Order>

# Fetch all open positions.
DhanClient#positions → Array<Hash>

# Fetch available capital.
DhanClient#available_capital → Float

# Fetch OHLCV candles (historical).
DhanClient#historical_candles(
  security_id:,
  exchange_segment:,
  instrument:,
  from_date:,   # String "YYYY-MM-DD"
  to_date:      # String "YYYY-MM-DD"
) → Array<Candle>

# Fetch intraday candles.
DhanClient#intraday_candles(
  security_id:,
  exchange_segment:,
  instrument:,
  interval:,    # "1" | "5" | "15" | "25" | "60"
  from_date:,
  to_date:
) → Array<Candle>

# Fetch LTP for multiple instruments.
DhanClient#ltp(instruments_by_segment:) → Hash
```

---

## StrategyBase Public Interface

```ruby
# Called on each closed candle. Updates internal state.
# Returns :buy, :sell, or :hold.
StrategyBase#on_candle(candle, indicators:) → Symbol

# Called on each live tick. Optional.
StrategyBase#on_tick(tick) → nil

# Returns current signal without mutating state.
StrategyBase#signal → :buy | :sell | :hold

# Returns strategy parameters hash.
StrategyBase#parameters → Hash

# Returns the stop-loss price for the current signal.
# Must be non-nil when signal is :buy or :sell.
StrategyBase#stop_loss → Float | nil

# Returns the target price for the current signal.
StrategyBase#target → Float | nil
```

---

## RiskEngine Public Interface

```ruby
# Validates an order against all risk rules.
# Returns [true, nil] if approved, or [false, "reason string"] if rejected.
RiskEngine#validate(order:, capital:, open_positions:) → [Boolean, String | nil]

# Records a trade result for daily loss tracking.
RiskEngine#record_trade(pnl:) → nil

# Returns true if trading is halted for the day.
RiskEngine#halted? → Boolean

# Returns the current daily P&L (negative means loss).
RiskEngine#daily_pnl → Float
```

---

## BacktestEngine Public Interface

```ruby
# Run a full backtest.
BacktestEngine#run(
  strategy:,      # StrategyBase instance
  candles:,       # Array<Candle> in chronological order
  capital:,       # Float
  config:         # Hash
) → BacktestResult

# BacktestResult fields:
#   total_trades:    Integer
#   winning_trades:  Integer
#   losing_trades:   Integer
#   total_pnl:       Float
#   max_drawdown:    Float
#   win_rate:        Float (percentage)
#   trades:          Array<Hash> — individual trade records
```
