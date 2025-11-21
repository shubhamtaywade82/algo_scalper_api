### High-level flow (from boot to shutdown)

- Initial boot
  - `config/initializers/dhanhq_config.rb`
    - Loads DhanHQ gem and configures it from ENV (`CLIENT_ID`, `DHANHQ_ACCESS_TOKEN`)
    - Sets `Rails.application.config.x.dhanhq` flags (always enabled, ws mode, etc.)
  - `config/initializers/market_stream.rb`
    - On `to_prepare`, starts the live stack unless console mode:
      - `Live::MarketFeedHub.instance.start!` (primary WS feed)
      - `Live::OrderUpdateHandler.instance.start!` (order updates - internally starts OrderUpdateHub)
      - `Live::OhlcPrefetcherService.instance.start!` (intraday OHLC prefetch loop)
      - `Signal::Scheduler.instance.start!` (signals → entries scheduler)
      - `Live::RiskManagerService.instance.start!` (PnL/risk loops)
      - `Live::AtmOptionsService.instance.start!` (ATM helper)
    - On `at_exit`, gracefully stops the above and `DhanHQ::WS.disconnect_all_local!`
  - `config/initializers/atm_options_service.rb`
    - Dev-only convenience starter for `Live::AtmOptionsService` (guarded by WS enabled)
  - `config/initializers/mock_data_service.rb`
    - Dev-only mock data if WS is disabled

### Data and market feed layer

- Instruments and watchlist
  - `Instrument` (model) + `InstrumentHelpers` concern
    - Resolves `exchange_segment`, builds subscription params, fetches `ltp`, `ohlc`, `intraday_ohlc` via DhanHQ models
  - `WatchlistItem` (model)
    - Drives which instruments to subscribe/prefetch; if empty, `DHANHQ_WS_WATCHLIST` is used as fallback
- Live market feed
  - `Live::MarketFeedHub`
    - Builds `DhanHQ::WS::Client` with mode (`ticker|quote|full`)
    - Subscribes to DB watchlist (preferred) or ENV fallback
    - Emits ticks to:
      - `Live::TickCache.put(tick)` (in-memory latest)
      - `ActiveSupport::Notifications.instrument("dhanhq.tick", tick)`
      - Broadcasts to `TickerChannel` (if present) for UI/debug

### Historical/Intraday data prefetch

- `Live::OhlcPrefetcherService`
  - Iterates active watchlist items on a staggered loop
  - For each instrument:
    - Calls `Instrument#intraday_ohlc` (via `InstrumentHelpers`)
      - Internally: `DhanHQ::Models::HistoricalData.intraday` with `security_id`, `exchange_segment`, `instrument` code, interval and dates
  - Logs fetched bar counts and recency for health

### Signal generation and entry

- `Signal::Scheduler`
  - Orchestrates periodic signal runs across configured indices
- `Signal::Engine`
  - Loads candles/series (via instrument data methods)
  - Computes Supertrend + ADX
  - Runs comprehensive validation with configurable modes:
    - **Conservative**: Strict ADX (≥25/≥30), narrow IV range (15%-60%), early theta cutoff (2:00 PM)
    - **Balanced**: Moderate ADX (≥18/≥20), standard IV range (10%-80%), normal theta cutoff (2:30 PM)
    - **Aggressive**: Relaxed ADX (≥15/≥18), wide IV range (5%-90%), late theta cutoff (3:00 PM)
    - All modes validate: IV rank, theta risk, ADX strength, trend confirmation, market timing
  - Makes a direction decision and yields a pick for entries if all checks pass
- Entry path
  - `Entries::EntryGuard.try_enter(...)`
    - Finds the `Instrument`, enforces exposure limits and cooldowns, checks live feed health
    - Sizes quantity via `Capital::Allocator.qty_for(...)`
    - Submits order through `Orders::Placer.buy_market!` (DhanHQ order create)
    - Persists `PositionTracker` for lifecycle tracking
- Option analytics (when used)
  - `Options::ChainAnalyzer` (select strikes/ATM bias)
  - `Live::AtmOptionsService` (maintains ATM references)

### Order management and updates

- `Orders::Placer`
  - Bridges order submission/modification/cancellation to `DhanHQ::Models::Order`
- `Live::OrderUpdateHandler`
  - Depends on `Live::OrderUpdateHub` (WebSocket client)
  - Processes order updates and updates `PositionTracker` records
  - Handles order status changes (FILLED, CANCELLED, etc.)
- `Live::OrderUpdateHub`
  - Connects `DhanHQ::WS::Orders::Client`
  - Normalizes payloads and emits `"dhanhq.order_update"` notifications
  - Invokes registered callbacks to update local state

### Risk management and circuit breakers

- `Live::RiskManagerService`
  - Continuous loop (interval seconds)
  - Fetches:
    - Active positions (`DhanHQ::Models::Position.active`)
    - Funds/balance (`DhanHQ::Models::Funds.fetch`) for daily breaker
  - Computes PnL and trailing stops:
    - Uses `Instrument#latest_ltp` (prefers `Live::TickCache`, fallback `quote_ltp` or API)
    - `enforce_hard_limits` (SL/TP/sizing bounds)
    - `enforce_trailing_stops` (breakeven/trailing logic)
    - `enforce_daily_circuit_breaker` using `Risk::CircuitBreaker`
  - Executes exits via `Orders::Placer` when rules trigger
- `Risk::CircuitBreaker`
  - Caches trip state with reason and timestamp; consulted by entry flow

### Health and observability

- `Api::HealthController#show`
  - Returns status of scheduler, circuit breaker, feed health, watchlist, sample LTPs
- `Live::FeedHealthService`
  - Tracks success/failure of funds/positions/feed pull
- Logging
  - Signal validation results, prefetch metrics, order updates, risk actions, and errors

### Shutdown

- `config/initializers/market_stream.rb` `at_exit`
  - Stops hubs/services and disconnects all Dhan WS clients
- Background threads in services terminate; caches are left ephemeral

### Console/server behavior

- Server mode (`rails s`)
  - All services start (subject to flags/ENV)
- Console/runner mode
  - Automated services are skipped:
    - `Live::MarketFeedHub`, `Live::OrderUpdateHandler`, `Live::OhlcPrefetcherService`,
      `Signal::Scheduler`, `Live::RiskManagerService`, `Live::AtmOptionsService`

### External integrations (DhanHQ gem)

- REST models used:
  - `DhanHQ::Models::HistoricalData`, `MarketFeed`, `Order`, `Position`, `Funds`, `OptionChain`
- WebSocket clients:
  - `DhanHQ::WS::Client` (quotes/ticker/full)
  - `DhanHQ::WS::Orders::Client` (order updates)

### Environment Variables

#### Required (Essential)
- `CLIENT_ID` - Your DhanHQ client ID
- `DHANHQ_ACCESS_TOKEN` - Your DhanHQ access token

#### Optional (Auto-configured)
- `DHANHQ_LOG_LEVEL` - Logging level (default: INFO)
- `DHANHQ_BASE_URL` - API base URL (default: https://api.dhan.co/v2)
- `DHANHQ_WS_MODE` - WebSocket mode (default: quote, configured in algo.yml)
- `DHANHQ_WS_WATCHLIST` - Fallback watchlist (not needed if WatchlistItem records exist)
- `ENABLE_ORDER` - Enable actual order placement (default: false, dry run mode)

#### Not Needed (Always Enabled)
- `DHANHQ_ENABLED` - Always enabled, no ENV check needed
- `DHANHQ_WS_ENABLED` - Always enabled, no ENV check needed
- `DHANHQ_ORDER_WS_ENABLED` - Always enabled, no ENV check needed

#### Not Needed
- `DHANHQ_WS_VERSION` - Uses gem default (version 2)
- `DHANHQ_WS_ORDER_URL` - Uses gem default
- `DHANHQ_WS_USER_TYPE` - Uses gem default (SELF)
- `RAILS_LOG_LEVEL` - Rails default is sufficient
- `RAILS_MAX_THREADS` - Rails default is sufficient
- `PORT` - Rails default (3000) is sufficient
- `REDIS_URL` - Uses default (redis://localhost:6379/0)

#### Trading Configuration
All trading parameters are configured in `config/algo.yml`:
- Risk limits (`sl_pct`, `tp_pct`, `daily_loss_limit_pct`)
- Signal parameters (`supertrend`, `adx`)
- Index configurations (`NIFTY`, `BANKNIFTY`, `SENSEX`)

#### **🎛️ Validation Modes**

The system supports **3 validation modes** to tune strictness based on market conditions:

```yaml
signals:
  validation_mode: "balanced" # conservative | balanced | aggressive

  validation_modes:
    conservative:
      adx_min_strength: 25
      adx_confirmation_min_strength: 30
      iv_rank_max: 0.6          # 60% max volatility
      iv_rank_min: 0.15         # 15% min volatility
      theta_risk_cutoff_hour: 14    # 2:00 PM cutoff
      theta_risk_cutoff_minute: 0
      require_trend_confirmation: true
      require_iv_rank_check: true
      require_theta_risk_check: true

    balanced:  # Default mode
      adx_min_strength: 18
      adx_confirmation_min_strength: 20
      iv_rank_max: 0.8          # 80% max volatility
      iv_rank_min: 0.1          # 10% min volatility
      theta_risk_cutoff_hour: 14    # 2:30 PM cutoff
      theta_risk_cutoff_minute: 30
      require_trend_confirmation: true
      require_iv_rank_check: true
      require_theta_risk_check: true

    aggressive:
      adx_min_strength: 15
      adx_confirmation_min_strength: 18
      iv_rank_max: 0.9          # 90% max volatility
      iv_rank_min: 0.05         # 5% min volatility
      theta_risk_cutoff_hour: 15    # 3:00 PM cutoff
      theta_risk_cutoff_minute: 0
      require_trend_confirmation: false  # Skip trend confirmation
      require_iv_rank_check: true
      require_theta_risk_check: false    # Skip theta risk check
```

#### **📊 Mode Selection Guidelines**

| Market Condition    | Recommended Mode | Reason                               |
| ------------------- | ---------------- | ------------------------------------ |
| **High Volatility** | Conservative     | Stricter filters prevent bad entries |
| **Trending Market** | Aggressive       | Lower barriers capture momentum      |
| **Sideways Market** | Conservative     | Avoid false breakouts                |
| **Low Volatility**  | Aggressive       | Need lower thresholds for entries    |
| **Late Session**    | Conservative     | Higher theta risk awareness          |

#### **🔄 Dynamic Mode Switching**

```ruby
# Switch modes during runtime (requires restart)
# Update config/algo.yml:
signals:
  validation_mode: "aggressive"

# Then restart Rails server
```

#### **📋 Order Control**

Control whether orders are actually placed or just logged (dry run mode):

```bash
# Enable actual order placement
export ENABLE_ORDER=true

# Dry run mode - only log orders, don't place them (default)
export ENABLE_ORDER=false
# or simply don't set the variable
```

**Example log output:**

**When `ENABLE_ORDER=true` (Live Trading):**
```
[Orders] Placing BUY order: seg=IDX_I, sid=25, qty=50, client_order_id=nifty_20250120_001
[Orders] BUY Order Payload: {
  :transaction_type=>"BUY",
  :exchange_segment=>"IDX_I",
  :security_id=>"25",
  :quantity=>50,
  :order_type=>"MARKET",
  :product_type=>"INTRADAY",
  :validity=>"DAY",
  :correlation_id=>"nifty_20250120_001",
  :disclosed_quantity=>0
}
[Orders] BUY Order placed successfully
```

**When `ENABLE_ORDER=false` (Dry Run Mode):**
```
[Orders] Placing BUY order: seg=IDX_I, sid=25, qty=50, client_order_id=nifty_20250120_001
[Orders] BUY Order Payload: {
  :transaction_type=>"BUY",
  :exchange_segment=>"IDX_I",
  :security_id=>"25",
  :quantity=>50,
  :order_type=>"MARKET",
  :product_type=>"INTRADAY",
  :validity=>"DAY",
  :correlation_id=>"nifty_20250120_001",
  :disclosed_quantity=>0
}
[Orders] BUY Order NOT placed - ENABLE_ORDER=false (dry run mode)
```

### Risk Management Exit Rules

The `Live::RiskManagerService` enforces multiple exit rules every 5 seconds:

#### Hard Limits (Priority Order)
1. **Stop-Loss** (`sl_pct: 0.30`) - Exit at 30% loss from entry
2. **Per-Trade Risk** (`per_trade_risk_pct: 0.01`) - Exit if loss reaches 1% of invested amount
3. **Take-Profit** (`tp_pct: 0.60`) - Exit at 60% gain from entry

#### Trailing Stops
4. **Trailing Stop** (`trail_step_pct: 0.10`, `exit_drop_pct: 0.03`)
   - Activates after 10% profit
   - Exits if current PnL drops 3% from high-water mark
5. **Breakeven Lock** (`breakeven_after_gain: 0.35`)
   - Locks breakeven after 35% profit
   - Never allows loss below entry price

#### Circuit Breakers
6. **Daily Loss Limit** (`daily_loss_limit_pct: 0.04`)
   - Stops all trading if daily loss reaches 4% of account balance
   - Triggers `Risk::CircuitBreaker` to halt new entries

### Architecture Simplifications

- **Single Market Feed**: Only `Live::MarketFeedHub` (removed redundant `MarketFeedHub`)
- **Simplified Order Updates**: `Live::OrderUpdateHandler` internally manages `Live::OrderUpdateHub`
- **Console Mode Protection**: All automated services skip in console/runner mode
- **Database-Driven Watchlist**: Uses `WatchlistItem` records (ENV fallback only if empty)
- **Minimal Configuration**: Only DhanHQ credentials required, everything else auto-configured

This is the end-to-end flow: initializers configure DhanHQ and spin up live services; feeds and prefetch hydrate data; the signal engine validates and produces entries; orders are routed and tracked; risk manager enforces exits and daily breakers; the system exposes health; on exit all live connections shut down cleanly.