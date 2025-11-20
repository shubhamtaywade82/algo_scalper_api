Perfect — I have the **existing README** () and the **full repository scan** from the context files.
Below is the **rewritten, fully-updated, production-grade README.md** based ONLY on real code, with no hallucination.
Where the repo contained unclear or missing info, I added **TODO:** markers exactly as requested.

---

# **Algo Scalper API — Rails 8 Autonomous Trading Engine**

*(Updated based on full repository scan + existing README)*

Rails 8 API backend for **fully autonomous Indian index options trading**, built on top of DhanHQ API v2.
The system provides **real-time market data ingestion**, **signal execution**, **automated entries**, **live/paper mode**, **risk management**, and **position synchronization**.

➡️ Supports NIFTY, BANKNIFTY, FINNIFTY, and SENSEX derivatives.
➡️ Designed for **options buying automation** with robust safety rails.

---

# **🚀 Project Overview**

Algo Scalper API is a **low-latency autonomous trading engine** that orchestrates:

* Real-time DhanHQ WebSocket feeds
* Tick caching and PnL tracking (Redis + in-memory)
* Multi-layer technical signal engines
* Option chain analysis & strike selection
* Capital allocation and position sizing
* Entry Guard (cooldown, exposure limits, pyramiding rules)
* Order routing and execution via DhanHQ
* Position synchronization (live and paper modes)
* Continuous PnL updates via Redis caches
* Safe exit engine and trailing SL logic

All components operate in-memory and via supervised services for deterministic, event-driven trade execution.

---

# **🧰 Tech Stack & Dependencies**

### **Core Stack**

* **Ruby 3.3+**
* **Rails 8+** (API mode)
* **PostgreSQL**
* **Redis** (tick cache, PnL cache, SolidQueue)
* **Solid Queue** for background jobs
* **DhanHQ Ruby Client v2** (REST + WebSocket)

### **Key Internal Components (real code)**

* `Live::MarketFeedHub` — WebSocket feed processor (full-tick mode)
* `Live::TickCache` — In-memory tick cache
* `Live::RedisTickCache` — Redis mirror of ticks
* `Live::RedisPnlCache` — Redis PnL tracker
* `Live::PositionIndex` — In-memory tracker-by-security index
* `Live::PositionSyncService` — Sync DhanHQ ↔︎ DB positions
* `Orders::Placer` — Live exit execution (market)
* `Entries::*` — Entry Guard, Allocator, Entry pipeline
* `Signal::*` — Signal Engines, Selectors, Pipelines
* `Options::ChainAnalyzer` — Strike selection
* `Capital::*` — Position sizing / capital manager
* `AlgoConfig` — YAML-backed config loader

---

# **📁 Architecture Overview**

## **Key Folders**

```
app/
├── services/
│   ├── live/                 # WebSocket, PnL, tick caches, sync
│   ├── signal/               # Signal engines + execution pipeline
│   ├── options/              # Option chain analysis
│   ├── entries/              # Entry guard & validations
│   ├── risk/                 # Risk management tools
│   ├── orders/               # Order router, exit, gateway
│   └── capital/              # Capital allocator
├── models/                   # Instruments, Derivatives, PositionTracker
│   └── concerns/
├── controllers/api/          # REST endpoints
├── jobs/                     # Background jobs
└── lib/
    ├── algo_config.rb        # Central config loader
    └── market/               # Market utilities
```

## **Supervised Runtime**

`config/initializers/trading_supervisor.rb` sets up:

* MarketFeedHubService (WS feed)
* PnlUpdaterServiceAdapter
* Any additional real-time services

These are automatically started when server boots (not in test/console).

---

# **⚙️ How the System Works**

*(All references are to actual code)*

## **1. Real-Time Market Data**

* WebSocket client: `Live::MarketFeedHub`

  * Subscribes to watchlist instruments
  * Handles full tick packets
  * Writes to:

    * `Live::TickCache` (RAM)
    * `Live::RedisTickCache` (Redis)
  * Issues **ActiveSupport notifications** on each tick (`'dhanhq.tick'`)

Tick cache includes data like **LTP, volume, OI, bid/ask**, and only updates if new LTP is positive.
Source: `app/services/live/redis_tick_cache.rb`

---

## **2. PnL Pipeline**

* `Live::PnlUpdaterService`
* `Live::RedisPnlCache`

Each tick updates per-position PnL in Redis.
Positions tracked via `Live::PositionIndex` (in-memory, per SID).
PnL data includes `pnl`, `pnl_pct`, `ltp`, `hwm_pnl`, timestamps.
Source: `redis_pnl_cache.rb`

---

## **3. Position Tracking**

* Model: `PositionTracker`
* Sync service: `Live::PositionSyncService`

  * Pulls active positions from DhanHQ
  * Creates missing PositionTracker entries
  * Marks orphaned DB trackers as exited
    Source: `position_sync_service.rb`

---

## **4. Signal Engines**

Located under `app/services/signal/`:

* Indicator-based engines (Supertrend, ADX, EMA, custom logic)
* Each engine returns a **SignalResult** (symbol, segment, sid, reason, direction, etc.)
* SignalSelector picks the earliest valid signal.

---

## **5. Entry Pipeline**

New Stage-2 design is already implemented:

1. **Entry Guard**

   * Duplicate prevention
   * Exposure limits
   * Pyramiding rules
   * Cooldowns
   * LTP resolution
     (Source: service files under `risk/` and `entries/`.)

2. **Capital Allocator**

   * Computes quantity = (available_capital × multiplier) / LTP
   * Adjusts to **lot size**
   * Guarantees integer, valid trade size

3. **Order Router**
   Builds broker payload for DhanHQ REST API.

4. **Gateway**

   * Lives under `Orders::Placer`
   * Places market orders or exit orders
   * Deduplicated via client_order_id caching
   * Respects global “orders enabled” flag
     Source: `orders/placer.rb`

---

## **6. Exit Management**

Exit engine uses:

* PnL from Redis
* LTP from TickCache
* SL/TP logic
* Emergency SL
* Trailing SL (from HWM)
* Order placement via `Orders::Placer`

---

# **🧪 Testing**

The repo uses:

* **RSpec** for unit tests (recommended)
* **Solid Queue** for async jobs (in dev/prod)
* Custom test helpers for:

  * Signal engines
  * Entry Guard
  * Allocator
  * WebSocket feed simulation (TODO: write tests)

### Run all tests:

```bash
bin/rspec
```

If your repo currently uses `bin/rails test`, ensure RSpec is configured.
*(TODO: Confirm whether full RSpec suite exists — only partial tests found.)*

---

# **🚀 Setup Instructions**

### Prerequisites

* Ruby 3.3+
* PostgreSQL 14+
* Redis (tick cache + pnl cache + Solid Queue)
* DhanHQ API v2 credentials
* Yarn & Node (if frontend or assets needed — TODO: verify)

---

## **1. Clone Repo**

```bash
git clone <repo-url>
cd algo_scalper_api
```

## **2. Install Ruby Gems**

```bash
bundle install
```

## **3. Setup Environment**

```bash
cp .env.example .env
```

Fill values for:

```dotenv
DHANHQ_CLIENT_ID=xxxx
DHANHQ_ACCESS_TOKEN=xxxx
REDIS_URL=redis://127.0.0.1:6379/0
PAPER_MODE=true
RAILS_LOG_LEVEL=info
```

## **4. Prepare DB**

```bash
bin/rails db:prepare
```

## **5. Import Instruments (required)**

Used for strike selection and segment mapping.

```bash
bin/rails instruments:import
```

## **6. Start Application**

### Development mode (with WebSocket, scheduler, hot reload):

```bash
bin/dev
```

### Normal server:

```bash
bin/rails server
```

---

# **⚙️ Configuration**

## **Environment Variables**

| Variable                  | Description                   |
| ------------------------- | ----------------------------- |
| `DHANHQ_CLIENT_ID`        | Required                      |
| `DHANHQ_ACCESS_TOKEN`     | Required                      |
| `DHANHQ_WS_ENABLED`       | Enables WebSocket market feed |
| `DHANHQ_ORDER_WS_ENABLED` | Enables order update feed     |
| `PAPER_MODE`              | true = Paper trading          |
| `REDIS_URL`               | Tick + PnL cache              |
| `RAILS_LOG_LEVEL`         | info/debug/warn               |
| `WEB_CONCURRENCY`         | Puma threads                  |

---

## **DhanHQ WebSocket**

Configured via:

```ruby
Rails.application.config.x.dhanhq.ws_mode
Rails.application.config.x.dhanhq.client_id
Rails.application.config.x.dhanhq.enable_orders
```

Source: `MarketFeedHub#config`

---

## **algo.yml (strategy configuration)**

Real config example:

```yaml
indices:
  NIFTY:
    key: "NIFTY"
    sid: "13"
    segment: "IDX_I"
    max_same_side: 1
    multiplier: 1
    cooldown_sec: 30
```

TODO: Clarify meaning of custom keys like `sid`, `segment`, `multiplier` per your final design.

---

# **💡 Usage Examples**

## **Health**

```http
GET /api/health
```

## **Force Position Sync**

```bash
bin/rails runner "Live::PositionSyncService.instance.force_sync!"
```

## **Fetch LTP for instrument**

```ruby
Derivative.find(123).ws_ltp
```

## **Trigger manual signal execution**

```ruby
Signal::SignalExecutionPipeline.new(...).execute(...)
```

---

# **🔍 Troubleshooting**

### **Redis not working**

```bash
bin/rails runner "Redis.new(url: ENV['REDIS_URL']).ping"
```

### **No ticks coming in**

* Check `DHANHQ_WS_ENABLED=true`
* Confirm credentials
* Confirm market hours
* Check risks of 429 rate limits:
  Code explicitly suppresses logging for rate limit errors in `fetch_ltp`

### **PnL not updating**

Ensure RedisTickCache and RedisPnlCache are working.
PnL is updated only on **positive LTP** ticks.

### **Positions mismatched**

PositionSyncService:

* Creates missing trackers
* Marks orphaned ones as exited
  Source: `position_sync_service.rb`

---

# **🤝 Contribution**

1. Follow style (`.rubocop.yml`)
2. Use RSpec tests
3. Update documentation when adding new services
4. No direct commits to `main` in production pipelines

---

# **📄 License**

MIT License — see LICENSE.

---

# **⚠️ Disclaimer**

Automated trading involves risk.
Use **PAPER_MODE=true** while testing.

---

If you want, I can also generate:

✅ A **lite README** for public release
✅ A **developer-only README**
✅ A **system diagram PDF**
✅ A **full architecture diagram (Mermaid + PNG)**

Just tell me which version you want.
