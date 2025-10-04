# Algo Scalper API

Rails 8 API backend for algorithmic trading powered by the DhanHQ API v2.

- DhanHQ REST + WebSocket integration (quotes, orders, positions, holdings)
- Market feed supervisor and tick cache
- Instrument/Derivative catalog import with 24h CSV cache
- Background jobs via Solid Queue; Redis optional for Sidekiq

---

## Quick Start

### Prerequisites
- Ruby 3.3.4
- PostgreSQL 14+
- Redis (optional; used by Sidekiq if enabled)

### Setup
```bash
# Install gems, prepare DB
bin/setup --skip-server

# Create and migrate
bin/rails db:prepare

# Copy env template and fill in secrets
cp .env.example .env
```

Minimal `.env` (Dhan credentials required if you enable integration):
```dotenv
DHANHQ_ENABLED=false
DHANHQ_CLIENT_ID=
DHANHQ_ACCESS_TOKEN=
RAILS_LOG_LEVEL=info
RAILS_MAX_THREADS=3
REDIS_URL=redis://localhost:6379/0
```

Run the server:
```bash
bin/dev    # or: bin/rails server
```

---

## DhanHQ Integration

Configuration lives in `config/initializers/dhanhq_config.rb`.

Required when `DHANHQ_ENABLED=true`:
- `DHANHQ_CLIENT_ID` (or fallback `CLIENT_ID`)
- `DHANHQ_ACCESS_TOKEN` (or fallback `ACCESS_TOKEN`)

Optional:
- `DHANHQ_WS_ENABLED`, `DHANHQ_ORDER_WS_ENABLED`
- `DHANHQ_WS_MODE` (quote/ticker/full; default: quote)
- `DHANHQ_BASE_URL` (default: https://api.dhan.co/v2)
- `DHANHQ_WS_VERSION` (default: 2)
- `DHANHQ_WS_ORDER_URL`, `DHANHQ_WS_USER_TYPE`
- `DHANHQ_PARTNER_ID`, `DHANHQ_PARTNER_SECRET`
- `DHANHQ_LOG_LEVEL` (fallback `DHAN_LOG_LEVEL`) – DEBUG/INFO/WARN/ERROR/FATAL
- `DHANHQ_WS_WATCHLIST` – comma/semicolon/newline-separated instruments

See also: `docs/dhanhq-client.md`.

Note: Linux requires `require "DhanHQ"` (case-sensitive).

---

## Instruments & Derivatives Catalog

Importer service: `app/services/instruments_importer.rb`

- Downloads Dhan scrip master CSV (cached 24h under `tmp/`)
- Splits into cash/index vs derivatives
- Bulk upserts `Instrument` and `Derivative` tables
- Records summary stats in `Setting`

Rake tasks:
```bash
# Import (uses cache if < 24h old)
bin/rails instruments:import

# Clear all rows
bin/rails instruments:clear

# Clear, then import
bin/rails instruments:reimport

# Check freshness and counts (fails when stale)
bin/rails instruments:status
```

Importer knobs (constants): `CSV_URL`, `CACHE_MAX_AGE`, `BATCH_SIZE`, `VALID_EXCHANGES`.

---

## Environment Variables

Core:
- `RAILS_LOG_LEVEL` (default: info)
- `RAILS_MAX_THREADS` (default: 3)
- `PORT` (default: 3000)
- `SOLID_QUEUE_IN_PUMA` (default: false)
- `JOB_CONCURRENCY` (Solid Queue processes; default: 1)
- `REDIS_URL` (Sidekiq; default: redis://localhost:6379/0)

Database:
- `ALGO_SCALPER_API_DATABASE_PASSWORD` (production only)
- `DATABASE_URL` (optional, single URL)

DhanHQ:
- `DHANHQ_ENABLED`, `DHANHQ_CLIENT_ID`, `DHANHQ_ACCESS_TOKEN`
- Optional: `DHANHQ_WS_ENABLED`, `DHANHQ_ORDER_WS_ENABLED`, `DHANHQ_WS_MODE`
- Optional: `DHANHQ_BASE_URL`, `DHANHQ_WS_VERSION`, `DHANHQ_WS_ORDER_URL`, `DHANHQ_WS_USER_TYPE`
- Optional: `DHANHQ_PARTNER_ID`, `DHANHQ_PARTNER_SECRET`
- Optional: `DHANHQ_LOG_LEVEL`, `DHAN_LOG_LEVEL`, `DHANHQ_WS_WATCHLIST`

Deploy:
- `RAILS_MASTER_KEY` (required for decrypting credentials in deploys)
- `KAMAL_REGISTRY_PASSWORD` (if deploying with Kamal)

An example file is provided at `.env.example`.

---

## Services & Strategy Helpers

- Indicators:
  - `app/services/indicators/calculator.rb`
  - `app/services/indicators/holy_grail.rb`
  - `app/services/indicators/supertrend.rb`
- Market feed & cache:
  - `app/services/market_feed_hub.rb`
  - `app/services/live/market_feed_hub.rb`
  - `app/services/live/tick_cache.rb`
- Settings store: `app/models/setting.rb` (+ migration)

---

## Development

Format, lint, and security scan:
```bash
bin/rubocop
bin/brakeman --no-pager
```

Run tests (Minitest):
```bash
bin/rails test
```

Database:
```bash
bin/rails db:create db:migrate
```

---

## Troubleshooting

- LoadError: `dhanhq` – ensure the initializer requires `"DhanHQ"` (case-sensitive)
- Instrument import slow – increase `BATCH_SIZE` or run during off-hours
- Stale catalog – run `bin/rails instruments:reimport` or lower `CACHE_MAX_AGE`

---

## Documentation

- DhanHQ Client API Guide: `docs/dhanhq-client.md`

