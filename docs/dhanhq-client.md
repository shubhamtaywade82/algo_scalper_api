# DhanHQ Client API Guide

## Overview

A clean Ruby client for Dhan API v2 with ORM-style models (orders, positions, holdings, and more) plus a resilient WebSocket market feed (ticker, quote, full) built on EventMachine and Faye.

### Key Features
- ActiveRecord-like helpers: `find`, `all`, `where`, `save`, `update`, `cancel`
- ActiveModel-style validations and error surfaces
- REST coverage: Orders, Super Orders, Forever Orders, Trades, Positions, Holdings, Funds/Margin, Historical Data, Option Chain, Market Feed
- WebSocket market feed: dynamic subscribe and unsubscribe, auto reconnect with backoff, 429 cool-off handling, idempotent subscriptions, binary header and payload parsing with normalized ticks

## Rails Integration in This Repository

### Environment flags
- `DHANHQ_ENABLED` (default `false`) – master toggle; disables all configuration when unset.
- `DHANHQ_CLIENT_ID`, `DHANHQ_ACCESS_TOKEN` – required when the integration is enabled.
- `DHANHQ_BASE_URL`, `DHANHQ_WS_VERSION`, `DHANHQ_LOG_LEVEL` – optional overrides for non-production stacks.
- `DHANHQ_WS_ENABLED`, `DHANHQ_WS_MODE` (`ticker`, `quote`, `full`), `DHANHQ_WS_WATCHLIST` (comma/semicolon separated `SEGMENT:SECURITY_ID`) – control the market feed.
- `DHANHQ_ORDER_WS_ENABLED`, `DHANHQ_WS_ORDER_URL`, `DHANHQ_WS_USER_TYPE`, `DHANHQ_PARTNER_ID`, `DHANHQ_PARTNER_SECRET` – order update stream settings.

### Runtime helpers
- `Dhanhq.client` exposes a shared instance of `Dhanhq::Client` for REST calls (`place_order`, `positions`, `historical_intraday`, etc.). All methods raise `Dhanhq::Client::Error` when something goes wrong.
- `Live::TickCache` stores the latest WebSocket ticks and provides helpers like `Live::TickCache.ltp("NSE_FNO", "12345")`.
- `Live::MarketFeedHub` spins up `DhanHQ::WS::Client` when WebSockets are enabled, subscribes the configured watchlist, forwards ticks to `ActiveSupport::Notifications` (`"dhanhq.tick"`), and keeps callbacks running.【F:app/services/live/market_feed_hub.rb†L1-L118】
- `Live::OrderUpdateHub` listens to order events via `DhanHQ::WS::Orders::Client`, emits `ActiveSupport::Notifications` (`"dhanhq.order_update"`), and allows registering callbacks with `on_update`.

Initializers (`config/initializers/dhanhq.rb` and `config/initializers/dhanhq_streams.rb`) drive configuration, check for required credentials, and guard startup/shutdown for both WebSocket clients.

---

## Installation

Add to your Gemfile:

```ruby
gem "DhanHQ", git: "https://github.com/shubhamtaywade82/dhanhq-client.git", branch: "main"
```

Install:

```bash
bundle install
```

Or:

```bash
gem install DhanHQ
```

---

## Configuration

### Programmatic

```ruby
require "DhanHQ"

DhanHQ.configure do |config|
  config.client_id    = ENV["CLIENT_ID"]    # e.g. "1001234567"
  config.access_token = ENV["ACCESS_TOKEN"] # e.g. "eyJhbGciOi..."
  config.base_url     = "https://api.dhan.co/v2" # optional REST base
  config.ws_version   = 2                         # optional WS version (default 2)
  config.ws_order_url  = "wss://api-order-update.dhan.co" # optional order WS knobs
  config.ws_user_type  = "SELF"                      # or "PARTNER"
  config.partner_id    = nil                         # required for PARTNER mode
  config.partner_secret = nil
end
```

### From environment variables

```ruby
require "DhanHQ"

DhanHQ.configure_with_env
DhanHQ.logger.level = (ENV["DHAN_LOG_LEVEL"] || "INFO").upcase.then { |level| Logger.const_get(level) }
# expects:
#   CLIENT_ID=...
#   ACCESS_TOKEN=...
#   DHAN_LOG_LEVEL=... (optional, defaults to INFO)
```

### Logging

```ruby
DhanHQ.logger.level = (ENV["DHAN_LOG_LEVEL"] || "INFO").upcase.then { |level| Logger.const_get(level) }
```

---

## Quick Start (REST)

```ruby
# Place an order
order = DhanHQ::Models::Order.new(
  transaction_type: "BUY",
  exchange_segment: "NSE_FNO",
  product_type: "MARGIN",
  order_type: "LIMIT",
  validity: "DAY",
  security_id: "43492",
  quantity: 50,
  price: 100.0
)
order.save

# Modify / Cancel
order.modify(price: 101.5)
order.cancel

# Positions / Holdings
positions = DhanHQ::Models::Position.all
holdings  = DhanHQ::Models::Holding.all

# Historical Data (Intraday)
bars = DhanHQ::Models::HistoricalData.intraday(
  security_id: "13",             # NIFTY index value
  exchange_segment: "IDX_I",
  instrument: "INDEX",
  interval: "5",                 # minutes
  from_date: "2025-08-14",
  to_date: "2025-08-18"
)

# Option Chain (example)
oc = DhanHQ::Models::OptionChain.fetch(
  underlying_scrip: 1333,        # example underlying ID
  underlying_seg: "NSE_FNO",
  expiry: "2025-08-21"
)
```

---

## WebSocket Market Feed

### Modes

- `:ticker` -> LTP and LTT
- `:quote` -> OHLCV and totals (recommended default)
- `:full` -> quote plus open interest and best five depth

### Normalized tick payload

```ruby
{
  kind: :quote,                 # :ticker | :quote | :full | :oi | :prev_close | :misc
  segment: "NSE_FNO",           # string enum
  security_id: "12345",
  ltp: 101.5,
  ts:  1723791300,              # LTT epoch (sec) if present
  vol: 123456,                  # quote/full
  atp: 100.9,                   # quote/full
  day_open: 100.1, day_high: 102.4, day_low: 99.5, day_close: nil,
  oi: 987654,                   # full or OI packet
  bid: 101.45, ask: 101.55      # from depth (mode :full)
}
```

### Start, subscribe, stop

```ruby
require "DhanHQ"

DhanHQ.configure_with_env
DhanHQ.logger.level = (ENV["DHAN_LOG_LEVEL"] || "INFO").upcase.then { |level| Logger.const_get(level) }

ws = DhanHQ::WS::Client.new(mode: :quote).start

ws.on(:tick) do |t|
  puts "[#{t[:segment]}:#{t[:security_id]}] LTP=#{t[:ltp]} kind=#{t[:kind]}"
end

# Subscribe instruments (<=100 per frame; send multiple frames if needed)
ws.subscribe_one(segment: "IDX_I",   security_id: "13")     # NIFTY index value
ws.subscribe_one(segment: "NSE_FNO", security_id: "12345")  # an option

# Unsubscribe
ws.unsubscribe_one(segment: "NSE_FNO", security_id: "12345")

# Graceful disconnect (sends broker disconnect code 12, no reconnect)
ws.disconnect!

# Or hard stop (no broker message, just closes and halts loop)
ws.stop

# Safety: kill all local sockets (useful in IRB)
DhanHQ::WS.disconnect_all_local!
```

### Under the hood

- Request codes per Dhan docs: subscribe 15 (ticker), 17 (quote), 21 (full); unsubscribe 16, 18, 22; disconnect 12
- Limits: up to 100 instruments per SUB or UNSUB; up to 5 WebSocket connections per user
- Backoff and 429 cool-off: exponential backoff with jitter; handshake 429 triggers a 60 second cool-off before retry
- Reconnect and resubscribe: on reconnect the client resends the current subscription snapshot (idempotent)
- Graceful shutdown: `ws.disconnect!` or `ws.stop` prevents reconnects; an `at_exit` hook stops all registered WS clients

---

## Order Update WebSocket

Receive live updates whenever orders transition between states (placed, traded, cancelled, etc.).

### Standalone Ruby script

```ruby
require "DhanHQ"

DhanHQ.configure_with_env
DhanHQ.logger.level = (ENV["DHAN_LOG_LEVEL"] || "INFO").upcase.then { |level| Logger.const_get(level) }

ou = DhanHQ::WS::Orders::Client.new.start

ou.on(:update) do |payload|
  data = payload[:Data] || {}
  puts "ORDER #{data[:OrderNo]} #{data[:Status]} traded=#{data[:TradedQty]} avg=#{data[:AvgTradedPrice]}"
end

sleep # keep the script alive (CTRL+C to exit)

ou.stop
```

Quick callback helper:

```ruby
DhanHQ::WS::Orders.connect do |payload|
  # handle :update callbacks only
end
```

### Rails bot integration

Mirror the market feed supervisor by adding an Order Update hub singleton that hydrates the local database and hands off to execution services.

1. Service: `app/services/live/order_update_hub.rb`

   ```ruby
   Live::OrderUpdateHub.instance.start!
   ```

   The hub wires `DhanHQ::WS::Orders::Client` to:
   - Upsert local `BrokerOrder` rows so UIs always reflect broker status
   - Auto subscribe traded entry legs on your existing `Live::WsHub` (if defined)
   - Refresh `Execution::PositionGuard` (if present) with fill prices and quantities

2. Initializer: `config/initializers/order_update_hub.rb`

   ```ruby
   if ENV["ENABLE_WS"] == "true"
     Rails.application.config.to_prepare do
       Live::OrderUpdateHub.instance.start!
     end

     at_exit { Live::OrderUpdateHub.instance.stop! }
   end
   ```

   Set `ENABLE_WS=true` in your Procfile or `.env` to boot the hub alongside the feed supervisor. On shutdown the client stops cleanly to avoid leaked sockets.

The hub is resilient to missing dependencies; if there is no `BrokerOrder` model it skips persistence while keeping downstream callbacks alive.

---

## Exchange Segment Enums

Use these string enums in WebSocket subscriptions and REST parameters:

| Enum           | Exchange | Segment           |
| -------------- | -------- | ----------------- |
| `IDX_I`        | Index    | Index Value       |
| `NSE_EQ`       | NSE      | Equity Cash       |
| `NSE_FNO`      | NSE      | Futures and Options |
| `NSE_CURRENCY` | NSE      | Currency          |
| `BSE_EQ`       | BSE      | Equity Cash       |
| `MCX_COMM`     | MCX      | Commodity         |
| `BSE_CURRENCY` | BSE      | Currency          |
| `BSE_FNO`      | BSE      | Futures and Options |

---

## Accessing ticks elsewhere in your app

### Direct handler

```ruby
ws.on(:tick) { |t| do_something_fast(t) } # avoid heavy work here
```

### Shared TickCache (recommended)

```ruby
# app/services/live/tick_cache.rb
class TickCache
  MAP = Concurrent::Map.new
  def self.put(t)
    MAP["#{t[:segment]}:#{t[:security_id]}"] = t
  end
  def self.get(seg, sid)
    MAP["#{seg}:#{sid}"]
  end
  def self.ltp(seg, sid)
    get(seg, sid)&.dig(:ltp)
  end
end

ws.on(:tick) { |t| TickCache.put(t) }
ltp = TickCache.ltp("NSE_FNO", "12345")
```

### Filtered callback

```ruby
def on_tick_for(ws, segment:, security_id:, &blk)
  key = "#{segment}:#{security_id}"
  ws.on(:tick) { |t| blk.call(t) if "#{t[:segment]}:#{t[:security_id]}" == key }
end
```

---

## Rails integration example

Goal: generate signals from Historical Intraday OHLC (5 minute bars) and use the WebSocket only for exits or trailing on open option legs.

1. Initializer `config/initializers/dhanhq.rb`

   ```ruby
   DhanHQ.configure_with_env
   DhanHQ.logger.level = (ENV["DHAN_LOG_LEVEL"] || "INFO").upcase.then { |level| Logger.const_get(level) }
   ```

2. Start WebSocket supervisor `config/initializers/stream.rb`

   ```ruby
   INDICES = [
     { segment: "IDX_I", security_id: "13" },  # NIFTY index value
     { segment: "IDX_I", security_id: "25" }   # BANKNIFTY index value
   ]

   Rails.application.config.to_prepare do
     $WS = DhanHQ::WS::Client.new(mode: :quote).start
     $WS.on(:tick) do |t|
       TickCache.put(t)
       Execution::PositionGuard.instance.on_tick(t)  # trailing and fast exits
     end
     INDICES.each { |i| $WS.subscribe_one(segment: i[:segment], security_id: i[:security_id]) }
   end
   ```

3. Fetch bars every five minutes via the Historical API; update your `CandleSeries` and run strategy logic on each closed bar.

4. Routing and orders: on signal, place Super Orders (SL, TP, TSL) or fallback to Market plus local trailing. Register the leg in `PositionGuard` and subscribe its option on the WebSocket.

5. Shutdown hook:

   ```ruby
   at_exit { DhanHQ::WS.disconnect_all_local! }
   ```

---

## Super Orders example

```ruby
intent = {
  exchange_segment: "NSE_FNO",
  security_id:      "12345",   # option
  transaction_type: "BUY",
  quantity:         50,
  take_profit:      0.35,      # 35 percent target
  stop_loss:        0.18,      # 18 percent stop loss
  trailing_sl:      0.12       # 12 percent trail
}

# If your SuperOrder model exposes create or modify:
o = DhanHQ::Models::SuperOrder.create(intent)
# or fallback:
mkt = DhanHQ::Models::Order.new(
  transaction_type: "BUY", exchange_segment: "NSE_FNO",
  order_type: "MARKET", validity: "DAY",
  security_id: "12345", quantity: 50
).save
```

Trailing a super order using WebSocket ticks:

```ruby
DhanHQ::Models::SuperOrder.modify(
  order_id: o.order_id,
  stop_loss: new_abs_price,    # broker permitting
  trailing_sl: nil
)
```

---

## Packet parsing reference

- Response header (8 bytes): `feed_response_code` (u8 big endian), `message_length` (u16 big endian), `exchange_segment` (u8 big endian), `security_id` (i32 little endian)
- Packet codes supported:
  - 1 Index (surface as raw or misc unless documented)
  - 2 Ticker: `ltp`, `ltt`
  - 4 Quote: `ltp`, `ltt`, `atp`, `volume`, totals, `day_*`
  - 5 Open interest packet
  - 6 Previous close: `prev_close`, `oi_prev`
  - 7 Market status (raw or misc unless documented)
  - 8 Full: quote plus open interest plus five depth levels
  - 50 Disconnect reason

---

## Best practices

- Keep the `on(:tick)` handler non-blocking; push work to a queue or thread.
- Use `mode: :quote` for most strategies; switch to `:full` only if you need depth or open interest in real time.
- Call `ws.disconnect!` or `ws.stop` when leaving IRB or tests; use `DhanHQ::WS.disconnect_all_local!` to be safe.
- Do not exceed 100 instruments per subscribe frame (the client auto chunks but be mindful).
- Avoid rapid connect and disconnect loops; the client already backs off and cools off on 429 responses.

---

## Troubleshooting

- **429 unexpected response code**: you connected too frequently or have too many sockets. The client cools off for 60 seconds and backs off. Prefer `ws.disconnect!` before reconnecting and call `DhanHQ::WS.disconnect_all_local!` to kill stragglers.
- **No ticks after reconnect**: ensure you re subscribed after a clean start; the client resends the snapshot automatically on reconnect.
- **Binary parse errors**: run with `DHAN_LOG_LEVEL=DEBUG` to inspect. The client drops malformed frames and keeps the loop alive.

---

## Contributing

Pull requests are welcome. Include tests for new packet decoders and WebSocket behaviors such as chunking, reconnect, and cool-off handling.

## License

MIT

---

## Detailed Model Reference

Use this section as a companion to the official Dhan API v2 documentation. It maps the public DhanHQ Ruby client classes to REST and WebSocket endpoints, highlights the validations enforced by the gem, and shows how to compose end to end flows without tripping over common pitfalls.

### Table of Contents

1. [Getting Started](#getting-started)
2. [Working With Models](#working-with-models)
3. [Orders](#orders)
4. [Super and Forever Orders](#super-and-forever-orders)
5. [Portfolio and Funds](#portfolio-and-funds)
6. [Trade and Ledger Data](#trade-and-ledger-data)
7. [Data and Market Services](#data-and-market-services)
8. [Account Utilities](#account-utilities)
9. [Constants and Enums](#constants-and-enums)
10. [Error Handling](#error-handling)
11. [Best Practices](#best-practices)

---

### Getting Started

```ruby
# Gemfile
gem "DhanHQ", git: "https://github.com/shubhamtaywade82/dhanhq-client.git", branch: "main"
```

```bash
bundle install
```

Configure the client (directly or via environment variables):

```ruby
require "DhanHQ"

DhanHQ.configure do |config|
  config.client_id    = ENV.fetch("CLIENT_ID")
  config.access_token = ENV.fetch("ACCESS_TOKEN")
  config.base_url     = "https://api.dhan.co/v2"   # optional override
  config.ws_version   = 2                           # optional, defaults to 2
end

DhanHQ.logger.level = (ENV["DHAN_LOG_LEVEL"] || "INFO").upcase.then { |level| Logger.const_get(level) }
```

Or bootstrap from environment variables:

```ruby
require "DhanHQ"

DhanHQ.configure_with_env
DhanHQ.logger.level = (ENV["DHAN_LOG_LEVEL"] || "INFO").upcase.then { |level| Logger.const_get(level) }
```

---

### Working With Models

All models inherit from `DhanHQ::BaseModel` and expose a consistent API:

- Class helpers: `.all`, `.find`, `.create`, and where available `.where`, `.history`, `.today`
- Instance helpers: `#save`, `#modify`, `#cancel`, `#refresh`, `#destroy`
- Validation: the gem wraps Dry Validation contracts. Validation errors raise `DhanHQ::Error`.
- Parameter naming: Ruby facing APIs accept snake case keys. The client converts to camelCase for the REST API. Low level `DhanHQ::Resources::*` classes expect API casing directly.
- Responses: constructors normalize keys to snake case and expose attribute readers. Raw API hashes are wrapped in `HashWithIndifferentAccess` for simple lookup.

---

### Orders

```ruby
order = DhanHQ::Models::Order.place(payload)    # validate, post, fetch
order = DhanHQ::Models::Order.create(payload)   # build and save
orders = DhanHQ::Models::Order.all              # current day order book
order  = DhanHQ::Models::Order.find(order_id)
order  = DhanHQ::Models::Order.find_by_correlation(correlation_id)
```

Instance workflow:

```ruby
order = DhanHQ::Models::Order.new(params)
order.save
order.modify(price: 101.5)
order.cancel
order.refresh
```

Required fields validated by `DhanHQ::Contracts::PlaceOrderContract`:

| Key               | Type    | Notes |
| ----------------- | ------- | ----- |
| `transaction_type`| String  | `BUY`, `SELL` |
| `exchange_segment`| String  | Use `DhanHQ::Constants::EXCHANGE_SEGMENTS` |
| `product_type`    | String  | `CNC`, `INTRADAY`, `MARGIN`, `MTF`, `CO`, `BO` |
| `order_type`      | String  | `LIMIT`, `MARKET`, `STOP_LOSS`, `STOP_LOSS_MARKET` |
| `validity`        | String  | `DAY`, `IOC` |
| `security_id`     | String  | Security identifier from the scrip master |
| `quantity`        | Integer | Must be greater than zero |

Optional fields and rules:

| Key                   | Type    | Notes |
| --------------------- | ------- | ----- |
| `correlation_id`      | String  | Up to 25 characters for idempotency |
| `disclosed_quantity`  | Integer | Greater than or equal to zero and up to 30 percent of quantity |
| `trading_symbol`      | String  | Optional label |
| `price`               | Float   | Mandatory for limit orders |
| `trigger_price`       | Float   | Mandatory for stop loss orders |
| `after_market_order`  | Boolean | Requires `amo_time` when true |
| `amo_time`            | String  | `OPEN`, `OPEN_30`, `OPEN_60` |
| `bo_profit_value`     | Float   | Required with `product_type: "BO"` |
| `bo_stop_loss_value`  | Float   | Required with `product_type: "BO"` |
| `drv_expiry_date`     | String  | ISO `YYYY-MM-DD` for derivatives |
| `drv_option_type`     | String  | `CALL`, `PUT`, `NA` |
| `drv_strike_price`    | Float   | Greater than zero |

Example:

```ruby
payload = {
  transaction_type: "BUY",
  exchange_segment: "NSE_EQ",
  product_type: "CNC",
  order_type: "LIMIT",
  validity: "DAY",
  security_id: "1333",
  quantity: 10,
  price: 150.0,
  correlation_id: "hs20240910-01"
}

order = DhanHQ::Models::Order.place(payload)
puts order.order_status
```

`Order#modify` merges existing attributes with overrides and validates against `ModifyOrderContract`. The instance must have `order_id` and `dhan_client_id`. At least one modifiable field must change. `Order#cancel` issues the cancel endpoint, and `Order#refresh` refetches current state.

Slicing orders uses similar parameters and allows additional validity options (`GTC`, `GTD`). When using the low level resource, camelize keys before calling `DhanHQ::Models::Order.resource.slicing`.

---

### Super and Forever Orders

#### Super Orders

```ruby
legs = {
  transactionType: "BUY",
  exchangeSegment: "NSE_FNO",
  productType: "CO",
  orderType: "LIMIT",
  validity: "DAY",
  securityId: "43492",
  quantity: 50,
  price: 100.0,
  stopLossPrice: 95.0,
  targetPrice: 110.0
}

super_order = DhanHQ::Models::SuperOrder.create(legs)
super_order.modify(trailingJump: 2.5)
super_order.cancel("ENTRY_LEG")
```

#### Forever Orders (GTT)

```ruby
params = {
  dhanClientId: "123456",
  transactionType: "SELL",
  exchangeSegment: "NSE_EQ",
  productType: "CNC",
  orderType: "LIMIT",
  validity: "DAY",
  securityId: "1333",
  price: 200.0,
  triggerPrice: 198.0
}

forever_order = DhanHQ::Models::ForeverOrder.create(params)
forever_order.modify(price: 205.0)
forever_order.cancel
```

The high level helpers accept snake case parameters and camelize internally.

---

### Portfolio and Funds

#### Positions

```ruby
positions = DhanHQ::Models::Position.all
open_positions = DhanHQ::Models::Position.active
```

Convert an intraday position to delivery:

```ruby
convert_payload = {
  dhan_client_id: "123456",
  security_id: "1333",
  from_product_type: "INTRADAY",
  to_product_type: "CNC",
  convert_qty: 10,
  exchange_segment: "NSE_EQ",
  position_type: "LONG"
}

response = DhanHQ::Models::Position.convert(convert_payload)
```

#### Holdings

```ruby
holdings = DhanHQ::Models::Holding.all
```

#### Funds

```ruby
funds = DhanHQ::Models::Funds.fetch
puts funds.available_balance

balance = DhanHQ::Models::Funds.balance
```

`available_balance` is normalized from the API's `availabelBalance` typo.

---

### Trade and Ledger Data

#### Trades

```ruby
history = DhanHQ::Models::Trade.history(from_date: "2024-01-01", to_date: "2024-01-31", page: 0)
trade_book = DhanHQ::Models::Trade.today
trade = DhanHQ::Models::Trade.find_by_order_id("ORDER123")
```

#### Ledger Entries

```ruby
ledger = DhanHQ::Models::LedgerEntry.all(from_date: "2024-04-01", to_date: "2024-04-30")
ledger.each { |entry| puts "#{entry.voucherdate} #{entry.narration} #{entry.runbal}" }
```

---

### Data and Market Services

#### Historical Data

`DhanHQ::Models::HistoricalData` validates requests via `HistoricalDataContract`.

```ruby
bars = DhanHQ::Models::HistoricalData.intraday(
  security_id: "13",
  exchange_segment: "IDX_I",
  instrument: "INDEX",
  interval: "5",
  from_date: "2024-08-14",
  to_date: "2024-08-14"
)
```

#### Option Chain

```ruby
chain = DhanHQ::Models::OptionChain.fetch(
  underlying_scrip: 1333,
  underlying_seg: "NSE_FNO",
  expiry: "2024-12-26"
)

expiries = DhanHQ::Models::OptionChain.fetch_expiry_list(
  underlying_scrip: 1333,
  underlying_seg: "NSE_FNO"
)
```

#### Margin Calculator

```ruby
params = {
  dhan_client_id: "123456",
  exchange_segment: "NSE_EQ",
  transaction_type: "BUY",
  quantity: 10,
  product_type: "INTRADAY",
  security_id: "1333",
  price: 150.0
}

margin = DhanHQ::Models::Margin.calculate(params)
puts margin.total_margin
```

Validation errors raise `DhanHQ::Error` before making the API call.

#### REST Market Feed (Batch)

```ruby
payload = {
  "NSE_EQ" => [11536, 3456],
  "NSE_FNO" => [49081, 49082]
}

ltp   = DhanHQ::Models::MarketFeed.ltp(payload)
ohlc  = DhanHQ::Models::MarketFeed.ohlc(payload)
quote = DhanHQ::Models::MarketFeed.quote(payload)
```

The client throttles requests via an internal rate limiter.

#### WebSocket Market Feed

See the earlier WebSocket section for code. Modes are `:ticker`, `:quote`, and `:full`. The client manages reconnects, snapshot resubscribe, and 429 cool-off handling.

---

### Account Utilities

#### Profile

```ruby
profile = DhanHQ::Models::Profile.fetch
profile.dhan_client_id
profile.token_validity
profile.active_segment
```

Invalid credentials raise `DhanHQ::InvalidAuthenticationError`.

#### EDIS

```ruby
form = DhanHQ::Models::Edis.form(
  isin: "INE0ABCDE123",
  qty: 1,
  exchange: "NSE",
  segment: "EQ",
  bulk: false
)

bulk_form = DhanHQ::Models::Edis.bulk_form(
  isin: %w[INE0ABCDE123 INE0XYZ89012],
  exchange: "NSE",
  segment: "EQ"
)

DhanHQ::Models::Edis.tpin
authorisations = DhanHQ::Models::Edis.inquire("ALL")
```

Helpers accept snake case keys; the client camelizes before calling `/v2/edis/...`.

#### Kill Switch

```ruby
DhanHQ::Models::KillSwitch.activate
DhanHQ::Models::KillSwitch.deactivate
DhanHQ::Models::KillSwitch.update("ACTIVATE")
```

Only `ACTIVATE` and `DEACTIVATE` are accepted.

---

### Constants and Enums

`DhanHQ::Constants` exposes canonical values:

- `TRANSACTION_TYPES`
- `EXCHANGE_SEGMENTS`
- `PRODUCT_TYPES`
- `ORDER_TYPES`
- `VALIDITY_TYPES`
- `AMO_TIMINGS`
- `INSTRUMENTS`
- `ORDER_STATUSES`
- CSV URLs: `COMPACT_CSV_URL`, `DETAILED_CSV_URL`
- `DHAN_ERROR_MAPPING` for broker error code translation

Example:

```ruby
validity = DhanHQ::Constants::VALIDITY_TYPES
```

---

### Error Handling

Broker error payloads map to subclasses of `DhanHQ::Error` (see `lib/DhanHQ/errors.rb`). Key mappings:

- `InvalidAuthenticationError` -> `DH-901`
- `InvalidAccessError` -> `DH-902`
- `UserAccountError` -> `DH-903`
- `RateLimitError` -> `DH-904`, HTTP 429 or 805
- `InputExceptionError` -> `DH-905`
- `OrderError` -> `DH-906`
- `DataError` -> `DH-907`
- `InternalServerError` -> `DH-908` or `800`
- `NetworkError` -> `DH-909`
- `OtherError` -> `DH-910`
- `InvalidTokenError`, `InvalidClientIDError`, `InvalidRequestError` for broker codes 807 through 814

Example handling on order placement:

```ruby
begin
  order = DhanHQ::Models::Order.place(payload)
  puts "Order status: #{order.order_status}"
rescue DhanHQ::InvalidAuthenticationError => e
  warn "Auth failed: #{e.message}"
rescue DhanHQ::OrderError => e
  warn "Order rejected: #{e.message}"
rescue DhanHQ::RateLimitError => e
  warn "Slow down: #{e.message}"
end
```

---

### Best Practices

1. Validate payloads locally before hitting the API in batch scripts (contracts live under `DhanHQ::Contracts`).
2. Use `correlation_id` for idempotent order placement across retries.
3. Refresh orders after placement when you depend on derived fields such as average traded price.
4. Respect the rate limiter; space out historical data and market feed calls to avoid `DH-904` or 805 responses.
5. Reference `DhanHQ::Constants` instead of hardcoding enum strings.
6. Persist broker error codes even when they map to Ruby exceptions; they are valuable for support.
7. Subscribe in frames of 100 instruments or fewer and handle reconnect callbacks to resubscribe cleanly.

Always cross check with https://dhanhq.co/docs/v2/ for endpoint specifics. The Ruby client mirrors those contracts while adding guard rails and idiomatic ergonomics.
