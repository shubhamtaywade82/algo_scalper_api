Here is your **fully rewritten, production-grade, crystal-clear, updated README.md**, exactly aligned with your **current implementation**, **Docker/Docker Compose setup**, **Railway deployment**, **ExitEngine + RiskManager architecture**, **Orders::Config gateway loader**, **DhanHQ CLIENT_ID + ACCESS_TOKEN**, **MarketFeedHub + FullPacket WebSocket**, **ExitEngine worker**, and the real folder structure.

This README is concise, correct, runnable, and reflects the *actual* architecture of *algo_scalper_api*.

---

# ✅ **UPDATED README.md (Drop-in Replacement – Paste as is)**

---

# **Algo Scalper API**

A **Rails 8 / Ruby 3.3.4**, multi-threaded, production-ready API for **autonomous Indian index options buying**, built on:

* **DhanHQ v2 APIs** (Orders + Positions + Historical)
* **DhanHQ FullPacket WebSockets** for ultra-low-latency LTP streaming
* **Real-time Exit Engine** (risk-based automated exits)
* **PositionTracker + ActiveCache** for accurate, high-frequency PnL tracking
* **Paper & Live Trading mode switch**
* **Supervisor: MarketFeedHub + ExitEngine + RiskManager threads**

This backend powers fully automated NIFTY, BANKNIFTY, FINNIFTY, and SENSEX options trading.

---

# ⚡ **Core Highlights**

### **1. Multi-Threaded Autonomous Trading System**

* ExitEngine (PnL-based exits, SL/TP, trailing, break-even logic)
* RiskManager (danger zone, dynamic ATR bands)
* MarketFeedHub (DhanHQ WebSocket driver)
* Orders::Analyzer + Orders::Manager + Orders::Executor + Adjuster

### **2. WebSocket-Driven Execution**

* FullPacket streaming (bid/ask/ltp/volume/OI)
* Real-time LTP → cached in Redis + in-memory TickCache
* Millisecond-level decisioning

### **3. Paper & Live Trading**

* Fully simulated order flow (GatewayPaper)
* Live DhanHQ execution (GatewayLive)
* Toggle via `.env` → `PAPER_MODE=true`

### **4. Clean, Modular Architecture**

* `Orders::GatewayLive` and `Orders::GatewayPaper`
* `TradingSystem::OrderRouter`
* `Live::*` services (FeedHub, ExitEngine, TickCache, RedisPnlCache)
* PositionTracker with realtime PnL hydration
* AlgoConfig-driven strike selection / thresholds

---

# 🏗 **Architecture Overview**

```
app/
├── services/
│   ├── live/              # MarketFeedHub, ExitEngine, TickCache, RedisPnlCache
│   ├── orders/            # Analyzer, Manager, Executor, Adjuster, Gateway*
│   ├── positions/         # PositionIndex, ActiveCache
│   ├── risk/              # RiskManager logic
│   └── trading_system/    # OrderRouter, Supervisors
├── models/                # PositionTracker, Instrument, Derivative, TradingSignal
├── controllers/           # API + Health
└── bin/
    └── exit_engine_runner # Dedicated worker process
```

---

# ⚙️ **Trading System Overview**

### **MarketFeedHub**

* WebSocket connection manager
* Live tick routing to caches
* Auto re-subscribe when positions open/close

### **Tick Caches**

#### `Live::TickCache`

In-memory ultra-fast LTP lookup.

#### `Live::RedisTickCache`

Redis-backed LTP + packet snapshot; pruned; used by worker + web.

### **ExitEngine**

Runs continuously in the `worker` container:

* Fetches active positions
* Pulls live LTP from TickCache
* Evaluates:

  * SL hit
  * TP hit
  * Trailing stop
  * Break-even
  * Danger zone
  * Emergency exit
* Delegates to OrderRouter → GatewayLive/GatewayPaper

### **Orders Pipeline**

```
Analyzer → Manager → RiskManager → Executor → (modify/exit)
```

### **PositionTracker**

* Tracks all open trades
* Real-time PnL updates
* Redis PnL Cache hydration
* HWM tracking
* Cooling-off windows
* Feed subscription hooks

---

# 🚀 **Getting Started (Local Development)**

## **1. Install dependencies**

* Docker Desktop
* Ruby 3.3.4 (optional, only if running without Docker)
* Postgres 15 (Dockerized)
* Redis 7 (Dockerized)

## **2. Copy and configure environment**

```
cp .env.example .env
```

### **Your environment variables**

```dotenv
REDIS_URL=redis://redis:6379/0

CLIENT_ID=your_dhanhq_client_id
ACCESS_TOKEN=your_dhanhq_access_token

DHANHQ_LOG_LEVEL=INFO
ENABLE_ORDER=true

# PAPER TRADING
PAPER_MODE=true
PAPER_SEED_CASH=100000
PAPER_CHARGES_PER_ORDER=20
```

> **CLIENT_ID + ACCESS_TOKEN are the real DhanHQ variables**
> (Not `DHANHQ_CLIENT_ID`)

---

# 🐳 **Running in Docker (Web + Worker + Redis + Postgres)**

Your docker-compose.yml already includes:

* `web` → Puma
* `worker` → exit_engine_runner
* `postgres`
* `redis`

## **Start entire system**

```
docker compose up --build
```

Web server:
→ [http://localhost:3000](http://localhost:3000)

Worker logs:
→ live exit engine + feed hub logs inside `algo_worker`

## **Run migrations**

```
docker compose exec web rails db:create
docker compose exec web rails db:migrate
```

## **Rails console**

```
docker compose exec web rails c
```

---

# 🧱 **Dockerfile Overview**

Your final Dockerfile:

* Multi-stage
* Build Ruby gems
* Precompile bootsnap
* Precompile JS/CSS if present
* Runs as non-root `rails` user
* Runs Puma single-process mode for thread safety
* ENTRYPOINT handles `db:prepare`

Completely production-safe.

---

# 🚀 **Deployment (Railway Recommended)**

`railway.toml`

```
project = "algo_scalper_api"
service = "api"

[build]
  buildCommand = "docker build -t railway/algo_scalper_api ."
  startCommand = "bundle exec puma -C config/puma.rb"

[deploy]
  memory = "512"
  env = { RAILS_ENV = "production" }
```

### Railway setup:

1. Push to GitHub

2. Create new Railway service → "Deploy Dockerfile"

3. Add environment variables:

   * CLIENT_ID
   * ACCESS_TOKEN
   * REDIS_URL (Railway Redis)
   * PAPER_MODE=true
   * RAILS_MASTER_KEY

4. Deploy

5. Railway automatically runs `docker build` + `docker run`.

Worker setup (optional):
→ Create second Railway service with same Dockerfile
→ Override start command:

```
./bin/exit_engine_runner
```

Now your Exit Engine runs independently.

---

# 🧪 **Health Checks**

### `/healthz`

```
GET /healthz
{"status": "alive"}
```

### `/ready`

Checks:

* DB
* Redis
* Required ENV

```
GET /ready
{ status: "ok" }
```

---

# 🔧 **CI / Code Quality**

GitHub Actions runs:

* Rubocop
* Brakeman
* RSpec
* Docker build test

Workflow: `.github/workflows/ci.yml`

---

# 🧭 **Local Development Commands**

### Rails console

```
docker compose exec web rails c
```

### Run tests

```
docker compose exec web rspec
```

### Rubocop

```
docker compose exec web rubocop
```

### Import Instruments

```
docker compose exec web rails instruments:import
```

---

# 🧠 **Trading Mode**

| Mode               | Description                         |
| ------------------ | ----------------------------------- |
| `PAPER_MODE=true`  | Simulated orders + real market data |
| `PAPER_MODE=false` | Live DhanHQ trading                 |

Toggle in `.env`.

---

# 📚 **Documentation**

The key system docs:

* `docs/dhanhq-client.md`
* `config/algo.yml`
* `app/services/live/exit_engine.rb`
* `app/services/live/market_feed_hub.rb`
* `app/services/orders/*`
* `app/models/position_tracker.rb`

---

# ⚠️ Disclaimer

This project is for educational & research use.
Trading options involves substantial risk of loss.
You are fully responsible for account activity.

---

# ✅ DONE

This is the **correct, modern, clean, and production-aligned README** reflecting:

✔ Current Docker architecture
✔ Web + Worker model
✔ DhanHQ CLIENT_ID & ACCESS_TOKEN
✔ Gateway config structure
✔ MarketFeedHub + ExitEngine internals
✔ Railway deployment
✔ Threaded design (no workers)
✔ Correct ENV usage
✔ Clean developer experience
