# Unified infrastructure: Rails app + options agent

One Postgres, one Redis, one Dhan login. The Rails app (`algo_scalper_api`) is the control plane and owns the Dhan
token; the options agent (`options-trading-agent`) is a separate execution engine that reads that token and shares the
account's option-chain rate budget. They share infrastructure, not code. Design and roadmap:
`docs/architecture/UNIFIED_SYSTEM_PLAN.md`.

> **One live engine at a time.** The agent's design assumes it is the only writer on the account (its lease is "the
> single trading authority for a client id", it refuses to start while the broker holds a position it cannot adopt, and
> Dhan's account-wide kill switch cannot be engaged while any position is open). Do not run Rails and the agent live on
> the same account at the same time. Paper alongside paper is fine.

## Services

| Service | Profile | Role | Host port |
|---|---|---|---|
| `postgres` | always | one server, five databases, two roles (see `initdb/`) | none |
| `redis` | always | rate budget, caches, ActionCable, agent lease cache; `noeviction` | none |
| `asa-migrate` | always | one-shot `db:prepare` for all four Rails databases | none |
| `asa-web` | always | Rails API + token authority | `127.0.0.1:3011` |
| `asa-jobs` | always | Solid Queue worker + recurring schedule | none |
| `asa-trading` | `trading` | Rails trading daemon (needs Dhan credentials) | none |
| `asa-dashboard` | `dashboard` | SolidJS dashboard behind nginx | `127.0.0.1:3000` |
| `ota` | `agent` | the options agent, paper by default, no inbound ports | none |

Only the Rails services receive `DHAN_PIN` / `DHAN_TOTP_SECRET`. The agent container never holds login-grade secrets.

## First-time setup

```bash
cd deploy/unified
cp .env.example .env              # fill every empty value; see the comments in the file
docker compose up -d --build      # postgres, redis, migrations, rails web + jobs (no trading, no Dhan login)
docker compose ps                 # asa-web must be "healthy"; asa-migrate exits 0
```

Then, in this order (each step needs the one before it):

```bash
docker compose --profile trading up -d --build   # Rails logs in to Dhan and starts feeds. Needs DHAN_PIN/TOTP.
docker compose --profile agent up -d --build     # the agent fetches the token from Rails; paper unless OTA_MODE says otherwise
docker compose --profile dashboard up -d --build # optional
```

The agent image comes from the agent repo's `Dockerfile` (`OTA_CONTEXT`). Build the agent against the Rails-owned
token only; never set `DHAN_PIN` for it.

## Bring-up checklist (every line is observable)

| # | Check | Command | Pass |
|---|---|---|---|
| 1 | Stores healthy, databases exist | `docker compose exec postgres psql -U postgres -lqt` | `algo_scalper_api_production`, `_cache`, `_queue`, `_cable`, `trading` |
| 2 | Migrations ran | `docker compose logs asa-migrate` | exits 0, no errors |
| 3 | Rails up | `curl -fsS localhost:3011/up` | HTTP 200 |
| 4 | Token authority guarded | `curl -si localhost:3011/api/dhan/token` and again with `-H "Authorization: Bearer $API_OPERATOR_TOKEN"` | 401 without the key; 503 `token_unavailable` with the key until Rails has logged in; 200 after |
| 5 | Recurring schedule loaded | `docker compose exec asa-web bin/rails runner 'puts SolidQueue::RecurringTask.count'` | 18 in production |
| 6 | Instrument master fresh | `docker compose exec asa-web bin/rails runner 'puts Setting.fetch("instruments.last_imported_at")'` | today (the old `Derivative` table is frozen and says nothing) |
| 7 | Agent uses the authority | `docker compose logs ota` | "dhan access token" fetched; no PIN/TOTP anywhere |
| 8 | Shared rate queue | `docker compose exec redis redis-cli --scan --pattern 'dhan:rate_limit:*'` | `dhan:rate_limit:option_chain` appears during chain polls |
| 9 | Egress IP registered with Dhan | `curl -H "Authorization: Bearer $API_OPERATOR_TOKEN" localhost:3011/api/public_ip/audit` | matches the Dhan console |
| 10 | Stops and end of day | agent paper session, circuit-breaker trip test (`POST /api/circuit_breaker/trip`, then `DELETE`) | entries halt; flat by the agent's `FLATTEN_BY` (default 15:05) |

## A trading day (IST)

| Time | What happens | Check |
|---|---|---|
| 08:45 | Rails imports the instrument master (also at daemon start if older than 20 h) | checklist 6 |
| 09:15 | Market opens; each app has its own feed | tick freshness on the dashboard and in `docker compose logs ota` |
| 15:05 | Agent flattens (`FLATTEN_BY`) | no open agent position |
| 15:30 | Close | `GET /api/reports/trades` and the agent's `npm run journal:summary` agree on counts and net P&L |

Run the agent's reports through its image, for example
`docker compose run --rm ota npm run journal:summary`.

## Staged rollout (one live engine at a time)

| Stage | Rails | Agent | Exit criteria |
|---|---|---|---|
| 0 | up, no trading profile | off | checklist 1 to 6 pass |
| 1 | paper | paper | 2 to 4 weeks; `bin/rails shadow:compare` reviewed; 30+ agent trades journaled; no token invalidations, no Dhan 429 |
| 2 | paper | paper, chosen indices | per-engine results judged per index |
| 3 | paper | live, one lot, caps 2 %/6 % | every live order matches the journal; sandbox session done first |
| 4 | live (`ASA_PLACE_ORDER=true` and `dhanhq.enable_orders`), minimal size | **off** | reconciliation clean for a week |

There is deliberately no stage with both live. Neither engine has shown a net edge; the agent's own roadmap says so.

## Failure behaviour

- **Rails down:** the agent keeps trading on its held token until it expires, then refuses to trade. It never logs in itself.
- **Redis down:** chain calls fall back to each app's own limiter; the account-wide spacing is no longer guaranteed. Watch for Dhan 429s.
- **Postgres down:** the agent's paper wallet cannot persist and it will not enter. Rails reports drift.
- **Terminal feed close (Dhan codes 804 to 810):** that app stops entering and keeps managing exits. Fix the cause before restarting.
- **Unregistered egress IP:** every order call from both apps is rejected.

## Housekeeping

- `docker compose down` keeps data; `docker compose down -v` **deletes the databases and the agent journal**.
- Use `docker compose stop` (not `kill`) so the agent shuts down gracefully (up to 90 s).
- Secrets live only in `.env` (gitignored). Rotate `API_OPERATOR_TOKEN` by changing it once and restarting `asa-web` and `ota`.
