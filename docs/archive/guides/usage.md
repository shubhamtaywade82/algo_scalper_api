# Algo Scalper API Usage Guide

This guide consolidates the operational steps scattered across the repository
documentation into a single checklist for running the autonomous options buying
stack for NIFTY, BANKNIFTY, and SENSEX.

## 1. Prerequisites
1. Install Ruby 3.3.4 with Bundler available on the `PATH`.
2. Provision PostgreSQL 14+ with a user that can create, migrate, and query the
   target database.
3. Install Redis to back Solid Queue background jobs and publish-subscribe
   workflows.
4. Obtain DhanHQ API v2 trading credentials with live order placement enabled.
5. Ensure common Unix shell tooling (`bash`, `curl`, `jq`, `sed`) is present for
   the provided scripts and checks.

> **Warning:** Run the stack only on secured hosts; leaked credentials or open
> ports can trigger unauthorized orders in live markets.

## 2. Clone And Bootstrap
1. Fetch the source and install runtime dependencies.
   ```bash
   git clone <repository-url>
   cd algo_scalper_api
   bin/setup --skip-server
   ```
2. Prepare and verify database schema state.
   ```bash
   bin/rails db:prepare
   bin/rails db:seed   # first-time environments only
   ```
3. Copy the sample environment file for local overrides.
   ```bash
   cp .env.example .env
   ```

## 3. Configure Environment Secrets
Populate `.env` (or your secret manager) with the required keys.

| Variable              | Purpose                                   | Notes                                    |
| --------------------- | ----------------------------------------- | ---------------------------------------- |
| `CLIENT_ID`           | Identifies your Dhan trading account      | Must match live or sandbox tenant        |
| `DHAN_ACCESS_TOKEN` | Authorizes REST and WebSocket calls       | Refresh via Dhan console when rotated    |
| `DATABASE_URL`        | Directs Rails to the PostgreSQL instance  | Include credentials and preferred schema |
| `REDIS_URL`           | Points Solid Queue to Redis               | Use TLS in production                    |
| `DHANHQ_WS_MODE`      | Chooses ticker-only or full depth streams | Optional; defaults to ticker feed        |

1. Validate each value locally with `bin/rails credentials:show` or equivalent
   secret-loading checks.
2. Review `config/algo.yml` for index-specific risk settings, capital budgets,
   and indicator tuning before live deployment.
3. Store sensitive values in your deployment tooling rather than committing
   them to source control.

## 4. Sync Instruments And Market Data
1. Import the latest Dhan instrument catalog to unlock strike discovery.
   ```bash
   bin/rails instruments:import
   ```
2. Audit coverage for NIFTY, BANKNIFTY, and SENSEX symbols.
   ```bash
   bin/rails instruments:status
   ```
3. Rebuild the catalog if you suspect stale or missing contracts.
   ```bash
   bin/rails instruments:reimport
   ```

## 5. Start Trading Stack
1. Launch the orchestrated development stack, which brings up Rails, Solid
   Queue, WebSocket hubs, and schedulers.
   ```bash
   bin/dev
   ```
2. For custom supervisors, start components individually:
   ```bash
   bin/rails server
   bin/rails solid_queue:start
   bin/rails live:feeds:start
   ```
3. Confirm background jobs are enqueued and dequeued by inspecting `log/` and
   Redis activity.

## 6. Verify Live Readiness
1. Query the health endpoint until all checks report `status: "ok"`.
   ```bash
   curl http://localhost:3000/api/health | jq
   ```
2. Observe initial signal generation in logs to ensure Supertrend and ADX data
   hydrate correctly.
3. Confirm order listeners (`Live::OrderUpdateHub`) are consuming updates and
   persisting fills to PostgreSQL.

## 7. Daily Operations
1. **Pre-open:** Sync instruments, validate credentials, and clear stale jobs.
2. **Market open:** Keep `bin/dev` (or your supervisor) active, watch health
   probes, and monitor capital utilization across the three indices.
3. **Intraday:** Review trailing stop adjustments and cooldown enforcement; use
   `bin/rails trades:status` if available to audit open legs.
4. **Market close:** Halt new entries via configuration toggles, let exit logic
   flatten positions, then stop the services in reverse order.

## 8. Monitoring And Troubleshooting
1. Tail Rails logs for signal, strike selection, and risk manager events.
2. Use the health endpoint as a heartbeat for Redis, PostgreSQL, and DhanHQ
   connectivity.
3. Validate infrastructure from the console when anomalies appear.
   ```bash
   bin/rails runner "puts Redis.current.ping"
   bin/rails runner "puts ActiveRecord::Base.connection.active?"
   ```
4. Escalate to manual intervention if PnL breaches the configured circuit
   breaker thresholds.

## 9. Production Safety Checklist
1. Store credentials in vaulted systems and rotate them according to your
   compliance policy.
2. Promote strategy changes through paper trading before enabling live capital.
3. Monitor for authentication failures, WebSocket disconnects, and rate-limit
   responses; restart only the affected hubs to limit downtime.
4. Document every manual override or forced exit for post-trade review and
   auditability.
