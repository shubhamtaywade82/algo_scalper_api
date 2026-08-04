# DhanHQ Broker Integration

The system integrates exclusively with DhanHQ via their v2 API for order execution, position synchronization, real-time market data, and authentication. No other broker is supported.

## Authentication & Token Management

### Three-Tier Token Provisioning

`Dhan::TokenManager` (`app/services/dhan/token_manager.rb`) implements a 3-tier fallback:

1. **Authority server** — HTTP GET to `$TRADER_API_BASE_URL/auth/dhan/token` (60s cache); used when internal token authority server is available
2. **TOTP auto-refresh** — Generates new access token via DhanHQ TOTP login using `DHAN_PIN` + `DHAN_TOTP_SECRET`
3. **Static fallback** — `ENV['DHAN_ACCESS_TOKEN']`; last resort if tiers 1-2 fail

### Token Bootstrap

`config/initializers/dhan_token_bootstrap.rb` runs an eager TOTP token refresh at startup before the first API call. This ensures a fresh token is available from boot.

### Token Healing During Live Trading

- `Orders::GatewayLive` detects `401 Unauthorized` responses from DhanHQ API
- Triggers `Dhan::TokenManager` to refresh via TOTP
- After refresh, `Dhan::TokenManager` restarts `Live::MarketFeedHub` to reconnect WebSocket with the new token

### Credentials

| ENV Variable | Purpose |
|-------------|---------|
| `DHAN_CLIENT_ID` | DhanHQ account client ID |
| `DHAN_ACCESS_TOKEN` | Static access token (tier 3 fallback) |
| `DHAN_PIN` | Login PIN for TOTP auto-refresh (tier 2) |
| `DHAN_TOTP_SECRET` | TOTP secret for token generation (tier 2) |
| `TRADER_API_BASE_URL` | Authority server base URL (tier 1) |

### Token Persistence

`DhanAccessToken` model (`app/models/dhan_access_token.rb`) persists the current access token with `expiry_time` for reuse across restarts.

---

## WebSocket Feed

### Market Data WebSocket

`Live::MarketFeedHub` (`app/services/live/market_feed_hub.rb`) manages the DhanHQ v2 market data WebSocket.

**Subscription management:**
- Subscribes index instruments (NIFTY, BANKNIFTY, SENSEX) on startup
- Subscribes option instruments as new positions open
- Unsubscribes on position exit
- Resubscribes all active instruments on reconnect

**Tick schema:**
```ruby
{
  segment: "IDX_I",       # segment identifier
  security_id: "13",      # DhanHQ security ID (NIFTY = "13", BANKNIFTY = "25", SENSEX = "51")
  ltp: 22450.50,
  prev_close: 22400.00,
  timestamp: "2026-03-31 10:15:00"
}
```

**Indices:**
| Index | Segment | Security ID | Expiry |
|-------|---------|-------------|--------|
| NIFTY | IDX_I | 13 | Weekly (Thursday) |
| BANKNIFTY | IDX_I | 25 | Weekly (last week of month) |
| SENSEX | IDX_I | 51 | Weekly |

**ENV control:**
- `DHANHQ_WS_ENABLED=true` — enable WebSocket
- WebSocket also disabled in: `Rails.env.test?`, `BACKTEST_MODE=1`, `SCRIPT_MODE=1`, `MOCK_DATA_ENABLED=true`

### Order Update WebSocket

`Live::OrderUpdateHub` (`app/services/live/order_update_hub.rb`) connects to DhanHQ order update feed. `Live::OrderUpdateHandler` processes fill/cancel events and updates `PositionTracker` state.

---

## Order Execution API

### Gateway Selection

At boot, `Orders::GatewayFactory.build` selects:
- `Orders::GatewayPaper` — if `config/algo.yml` → `paper_trading.enabled: true`
- `Orders::GatewayLive` — if `paper_trading.enabled: false`

### Live Order Safety Gates

Two explicit safety gates must both be active for live DhanHQ order submission:

1. `config/algo.yml` → `dhanhq.enable_orders: true`
2. `PLACE_ORDER=true` environment variable

`Orders::Placer` checks `ENV['PLACE_ORDER'] == 'true'` before every live BUY, SELL, or EXIT call. Without it, the attempt is logged as "dry-run" and not submitted to DhanHQ.

### Order Types

| Type | Use case | Implementation |
|------|----------|----------------|
| Market BUY | Entry | `Orders::Placer.buy_market!` |
| Market SELL | Exit | `Orders::Placer.sell_market!` |
| Position flat | Exit (gateway level) | `GatewayLive.flat_position` |
| Order cancel | Cancel pending | `GatewayLive.cancel_order` |

### Order Execution Pipeline

```
EntryGuard.try_enter
  → Capital::Allocator.qty_for (lot-aligned)
  → Orders::GatewayLive.place_market(segment:, security_id:, qty:, direction:, ...)
    → Orders::Placer.buy_market!(...)
      → Check: ENV['PLACE_ORDER'] == 'true'
      → Check: dhanhq.enable_orders: true
      → Build DhanHQ order payload (segment, security_id, qty, order_type, transaction_type)
      → POST /orders to DhanHQ API
      → Handle response: return order_no on success
    → PositionTracker.create! (status: :pending, order_no: dhan_order_no)
```

### Error Handling

| Error | Response |
|-------|---------|
| `401 Unauthorized` | Token refresh via `Dhan::TokenManager` |
| Insufficient margin | Entry rejected; logged with reason |
| Rate limiting | Exponential backoff (built into `GatewayLive`) |
| Duplicate order (coid reuse) | Normalized as successful terminal outcome |
| Unknown order error | Logged as fatal; circuit breaker may trip |

---

## Option Chain API

**Adapter:** `Adapters::OptionChain::DhanAdapter` (`app/services/adapters/option_chain/dhan_adapter.rb`)

**Always live:** Option chain data is always fetched live from DhanHQ API, even in paper trading mode. The `DhanAdapter` is always wired regardless of `paper_trading.enabled`.

**Usage in `Options::ChainAnalyzer`:**
- Fetches option chain for a given underlying + expiry date
- Returns CE/PE data with OI, volume, IV, LTP, bid/ask

---

## Instrument Data

### DhanHQ Instrument Master CSV

`InstrumentsImportJob` runs daily at 8:45 AM via Solid Queue:
- Downloads DhanHQ instrument master CSV
- Upserts `Instrument` records
- Creates/updates `Derivative` records (options with strike, expiry, option_type, lot_size, security_id)

```bash
# Run manually
rails runner "InstrumentsImportJob.perform_now"

# Check record count
rails runner "puts Derivative.count"
```

### Segment Mapping

DhanHQ uses numeric segment IDs internally. The codebase uses symbolic segment identifiers:

| Symbol | DhanHQ Segment | Instruments |
|--------|---------------|-------------|
| `IDX_I` | Index segment | NIFTY, BANKNIFTY, SENSEX spot |
| `NSE_FNO` | NSE F&O | Options/futures |
| `BSE_FNO` | BSE F&O | SENSEX options |

---

## Performance Notes

- **Order latency**: HTTP order placement. Typical latency 50-200ms depending on DhanHQ response time.
- **WebSocket tick latency**: Sub-millisecond from DhanHQ to in-memory cache on same machine.
- **IP whitelisting**: DhanHQ may require production server IP whitelisting — check your DhanHQ account settings.
- **Token expiry**: DhanHQ access tokens expire daily. TOTP auto-refresh handles this transparently when `DHAN_PIN` and `DHAN_TOTP_SECRET` are configured.
