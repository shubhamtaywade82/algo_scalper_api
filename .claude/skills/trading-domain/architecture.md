# Trading System Architecture Layout

## Directory Layout

```text
app/
├── controllers/
│   ├── api/
│   │   ├── orders_controller.rb        # HTTP API for manual orders
│   │   ├── positions_controller.rb     # Position queries
│   │   └── webhooks_controller.rb      # Broker callbacks
│   └── websockets/
│       └── market_data_channel.rb      # Live data streaming
│
├── domain/                              # PURE RUBY. No Rails.
│   ├── orders/
│   │   ├── order.rb                    # Order entity + state machine
│   │   ├── order_state.rb             # State transitions
│   │   └── order_validator.rb         # Domain validation
│   ├── positions/
│   │   ├── position.rb                # Position entity
│   │   └── position_calculator.rb     # PnL, margin calculations
│   ├── trades/
│   │   └── trade.rb                   # Immutable execution record
│   ├── signals/
│   │   ├── signal.rb                  # Signal value object
│   │   └── signal_type.rb            # BUY/SELL/CLOSE/HOLD
│   ├── risk/
│   │   ├── risk_engine.rb            # Evaluates rules against signal
│   │   ├── risk_result.rb            # PASS/REJECT + reason
│   │   └── rules/
│   │       ├── max_position_size.rb
│   │       ├── max_daily_loss.rb
│   │       ├── margin_availability.rb
│   │       ├── max_orders_per_minute.rb
│   │       └── circuit_breaker.rb
│   └── instruments/
│       ├── instrument.rb             # Resolved instrument
│       └── instrument_resolver.rb    # Symbol -> Instrument
│
├── services/                            # APPLICATION LAYER
│   ├── orders/
│   │   ├── place.rb                  # PlaceOrder use case
│   │   ├── cancel.rb
│   │   └── retry_failed.rb
│   ├── positions/
│   │   ├── close.rb
│   │   └── reconcile.rb
│   ├── strategies/
│   │   ├── run.rb                    # Execute strategy cycle
│   │   └── evaluate_signal.rb        # Signal -> risk -> order
│   └── market_data/
│       ├── process_tick.rb
│       └── build_candle.rb
│
├── gateways/                            # INFRASTRUCTURE: external
│   ├── brokers/
│   │   ├── base.rb                   # Shared interface
│   │   ├── dhan_gateway.rb
│   │   ├── zerodha_gateway.rb
│   │   └── upstox_gateway.rb
│   ├── market_data/
│   │   ├── dhan_feed.rb
│   │   └── websocket_feed.rb
│   └── notifications/
│       ├── telegram_notifier.rb
│       └── slack_notifier.rb
│
├── models/                              # ActiveRecord persistence
│   ├── order_record.rb               # Maps to orders table
│   ├── trade_record.rb
│   ├── position_record.rb
│   ├── instrument_record.rb
│   └── strategy_run_record.rb
│
├── jobs/
│   ├── order_submission_job.rb       # Async broker submission
│   ├── position_reconciliation_job.rb
│   ├── market_data_archive_job.rb
│   └── risk_report_job.rb
│
└── strategies/                          # TRADING STRATEGIES
    ├── base.rb                       # Strategy interface
    ├── momentum_breakout.rb
    ├── mean_reversion.rb
    └── vwap_reversion.rb
```

---

## Dependency Rules

- `controllers` $\rightarrow$ `services` (NEVER $\rightarrow$ `domain` directly, NEVER $\rightarrow$ `gateways`)
- `services` $\rightarrow$ `domain` + `gateways` + `models`
- `domain` $\rightarrow$ **NOTHING** (pure Ruby, no requires from `app/`)
- `gateways` $\rightarrow$ `domain` interfaces only (never $\rightarrow$ `models`, never $\rightarrow$ `services`)
- `models` $\rightarrow$ `domain` (for mapping, not business rules)
- `jobs` $\rightarrow$ `services`
- `strategies` $\rightarrow$ `domain` (`Signal`, `Instrument`) only

---

## Anti-Patterns Specific to Trading Systems

- ❌ Broker-specific logic in Order model
- ❌ Risk checks in controller action
- ❌ Strategy calling DhanGateway directly
- ❌ Position calculation in a view/serializer
- ❌ Order state changed via ActiveRecord callback
- ❌ Market data processing in a controller action
- ❌ Float for prices/quantities
- ❌ Synchronous broker call in request cycle
- ❌ Strategy reading/writing database directly
- ❌ Gateway containing business logic
