### High-level flow (from boot to shutdown)

- Initial boot
  - `config/initializers/dhanhq_config.rb`
    - Loads DhanHQ gem and configures it from ENV (`DHANHQ_CLIENT_ID`, `DHANHQ_ACCESS_TOKEN`)
    - Sets `Rails.application.config.x.dhanhq` flags (enabled, ws flags, mode, etc.)
  - `config/initializers/market_stream.rb`
    - On `to_prepare`, starts the live stack unless console mode:
      - `Live::MarketFeedHub.instance.start!` (primary WS feed)
      - `MarketFeedHub.instance.start!` (fallback/local hub)
      - `Live::OrderUpdateHub.instance.start!` (order updates WS)
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
  - `MarketFeedHub` (non-namespaced local hub)
    - Same responsibilities as a fallback/simple hub

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
  - Runs comprehensive validation:
    - IV rank, theta risk, ADX strength/confirmation
    - Trend confirmation
    - Market timing (`Market::Calendar` trading day and market hours)
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
    - `Live::MarketFeedHub`, `Live::OrderUpdateHub`, `Live::OhlcPrefetcherService`,
      `Signal::Scheduler`, `Live::RiskManagerService`, `Live::AtmOptionsService`

### External integrations (DhanHQ gem)

- REST models used:
  - `DhanHQ::Models::HistoricalData`, `MarketFeed`, `Order`, `Position`, `Funds`, `OptionChain`
- WebSocket clients:
  - `DhanHQ::WS::Client` (quotes/ticker/full)
  - `DhanHQ::WS::Orders::Client` (order updates)

### Minimal ENV needed (runtime)

- Required
  - `DHANHQ_CLIENT_ID`
  - `DHANHQ_ACCESS_TOKEN`
- Optional (auto-wired by gem or already defaulted)
  - `DHANHQ_LOG_LEVEL`
  - `DHANHQ_BASE_URL` (gem default is used if not set)
- Not needed if `WatchlistItem` exists
  - `DHANHQ_WS_WATCHLIST`

This is the end-to-end flow: initializers configure DhanHQ and spin up live services; feeds and prefetch hydrate data; the signal engine validates and produces entries; orders are routed and tracked; risk manager enforces exits and daily breakers; the system exposes health; on exit all live connections shut down cleanly.