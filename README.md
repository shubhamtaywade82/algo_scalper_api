# options-trading-agent

An NSE/BSE **index options buying** agent on **DhanHQ**, with LLM advisory through
[`@nemesis-oss/ollama-sdk`](https://www.npmjs.com/package/@nemesis-oss/ollama-sdk).
It trades NIFTY, BANKNIFTY, FINNIFTY, MIDCPNIFTY (NSE_FNO) and SENSEX (BSE_FNO) by buying
one long CE or PE per signal, with a server-side stop and target on every entry.

It was migrated from `crypto-trading-agent` (the baseline commit is kept in history). The
crypto exchange adapters, perpetual and funding logic, SMC-ML strategy, MiniCPM workers and
research plane were removed, not adapted. See [What was removed](#what-was-removed).

What the agent has shown, and what it has not, is in [`docs/ROADMAP.md`](docs/ROADMAP.md). In short:
the trading machinery is built and tested offline, and no strategy has yet shown a net edge.

## Scope

| In scope | Out of scope |
| --- | --- |
| Long CE / long PE on index options (buy-to-open only) | Any option selling, spreads that sell premium, or short options |
| NSE_FNO and BSE_FNO index options | Equities, futures, commodities, crypto |
| DhanHQ REST + WebSocket market data and super-order execution | Other brokers |
| Three modes on live market data: `paper`, `sandbox`, `live` | Automatic tuning from backtest results |
| Offline historical replay on real option premiums ([Time Machine](docs/TIME_MACHINE.md)) | |

## Quick start

```bash
npm ci                       # installs @nemesis-oss/dhanhq-sdk 2.0.1 from npm (exact pin, from the lockfile)
cp .env.example .env         # fill DHAN_CLIENT_ID, DHAN_PIN and DHAN_TOTP_SECRET (see Dhan authentication)
npm run typecheck && npm test
npm run dev:paper            # paper venue, live market data, simulated fills
```

There are three modes. Market data is always the live Dhan feed in every mode.

| Mode | Market data | Orders go to | Persistence |
| --- | --- | --- | --- |
| `paper` | live Dhan feed | `PAPER_BACKEND=postgres`: simulated venue in PostgreSQL. `PAPER_BACKEND=exchange`: a running [paper_exchange](https://github.com/shubhamtaywade82/paper_exchange) server | PostgreSQL (required) |
| `sandbox` | live Dhan feed | Dhan sandbox account via the SDK's `hybrid` mode (`DHAN_SANDBOX_*`) | PostgreSQL and Redis (required) |
| `live` | live Dhan feed | Dhan production account | PostgreSQL and Redis (required) |

Live trading needs `MODE=live` **and** `LIVE_TRADING_ACK=I_ACCEPT_LIVE_ORDER_RISK`. Without
both, the process exits before opening a socket. `npm run dev:sandbox` starts sandbox mode.
Each mode holds its own trading lease, keyed `mode:clientId`, so a paper run never blocks a live run.

### Running paper against paper_exchange

`PAPER_BACKEND=exchange` sends paper orders to a running [paper_exchange](https://github.com/shubhamtaywade82/paper_exchange) server, which keeps the account, margin and ledger. Set `PAPER_EXCHANGE_URL` (https, or http on loopback), `PAPER_EXCHANGE_API_KEY` and optionally `PAPER_EXCHANGE_ACCOUNT_ID`.

The account must be INR. The server's reset endpoint creates USD accounts, so after a reset set the currency to INR on the server. The agent refuses to start otherwise.

To run the end-to-end suite against a server (it places real paper orders on that account and leaves no position open):

```bash
PAPER_EXCHANGE_E2E_URL=http://127.0.0.1:3100 \
PAPER_EXCHANGE_E2E_API_KEY=... \
PAPER_EXCHANGE_E2E_ACCOUNT=<inr-account-id> \
npx tsx --test tests/paperExchange.e2e.test.ts
```

Without those variables the suite is skipped.

Node 22 or newer is required.

## Architecture

```
                  ┌──────────────── Orchestrator (one shared DayBook) ───────────────┐
 Dhan WS  ──ticks─▶ route by composite key  (IDX_I:13 → spot,  NSE_FNO:48001 → option)
                  │      │                                           │
                  │  UnderlyingAgent (per index, serial queue)       │
                  │      CandleBuilder → BarSeries → signal families │
                  │      posture · chain analysis · market context   │
                  │      → selectContract → bracketLevels            │
                  │      → sizePosition → evaluatePreTrade (risk)    │
                  │      → LLM advisor (veto only, optional)         │
                  │      → ExecutionPort.submitEntry ─────────────┐  │
                  │      TradeStateMachine (deterministic FSM) ◀──┼──┘
 Dhan REST ◀── MarketPort (charts, expiries, option chain, funds)  │
                  │                                                │
                  │   ExecutionPort  (one contract, four paths)    │
                  │     Postgres paper   simulated fills           │
                  │     paper_exchange   via the gateway port      │
                  │     Dhan sandbox     via the gateway port      │
                  │     Live             super orders, WS fills    │
                  └────────────────────────────────────────────────┘
                  EventLog (JSONL audit trail) · console logger (IST)
```

- **One contract, four paths.** `ExecutionPort` reports every outcome as an event. The
  state machine is driven by events only, so the venues share one transition path.
  `src/runtime/createRuntime.ts` chooses the path at start.
- **One serial queue per underlying.** Spot ticks, option ticks, clock, and fills all enter
  one queue, so transitions never interleave.
- **Composite keys everywhere.** Instruments are identified by `exchangeSegment:securityId`.

Details, the full transition table, and the failure-mode matrix are in
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Operator cockpit

On an interactive terminal, `npm run dev:paper` (and `dev:live`) opens a full-screen cockpit: a header,
four framed columns, a detail row, the event log, and a footer. Set `UI=off`, or pipe the output, for plain
log lines under a process supervisor.

```
UNDERLYINGS     SIGNAL & CONTRACT           POSITION          RISK & DAY
▸ NIFTY IDLE    SELECTED NIFTY               flat             P&L +₹83.75
  spot, age     LAST SIGNAL / REJECTION      LAST EXIT        loss ░░░░ 0% of ₹3,000
  ST, ORB       LAST CANDIDATE (contract,    (or the open     trades 2/3, open 1/1
  EMA           ask, spread, OI, SL, TP)     position: mark,  kill switch off
                                             P&L, held time)
```

Every key that changes trading or the session needs a second press. The first press shows a
prompt and changes nothing. The second press, within 5 seconds and on the same target, does it.
Navigation keys never ask. The key table is `src/ui/keymap.ts`, and the footer and the `?` line are built from it.

| Key | Action | Second press |
| --- | --- | --- |
| `↑` `↓` | select the underlying | no |
| `←` `→` | scroll the option-chain window | no |
| `[` `]` | scroll the position list (PageUp and PageDown too) | no |
| `p` | cycle the strategy posture: scout, aligned, confirmed | yes |
| `1`–`5` | toggle a strategy family: 1 range, 2 trend, 3 EMA cross, 4 momentum, 5 continuation | yes |
| `t` | start a test trade on the selected underlying. Paper and sandbox only; live refuses it | yes |
| `c` | close the selected position through the normal exit path (reason `MANUAL`) | yes |
| `k` | toggle the entry block. Clearing is refused while any underlying is halted or the day has breached its loss limit | yes |
| `s`, `Ctrl+C` | stop: flatten open positions, then exit | yes |
| `r` | reset the daily drawdown threshold | yes |
| `d` | toggle the daily-loss brake | yes |
| `?` | show the key line | no |

The cockpit only sends the actions above. Its data comes from `Orchestrator.snapshot()`, a read-only
view built from the agents and the day book. Rendering it never changes trading state. Its log is an
in-memory ring of the last 200 records; the durable record is still the journal.

**Stopping.** In the cockpit, `Ctrl+C` is the same graceful stop as `s`: open positions are flattened
first, within the shutdown timeout. Without the cockpit (`UI=off`, or output that is not a terminal),
`SIGTERM` runs a graceful stop, and `SIGINT` twice within 2 seconds quits immediately. A paper immediate
quit releases the trading lease at once, so the next start does not wait. A graceful stop does not get
that handoff, so the next start waits for the lease to expire (`LEASE_TTL_MS`, 30 seconds by default).

## Strategy and contract selection

**Signal families.** Signals are evaluated only on closed bars, in the IST session. The paper profile
runs five live families:

| Family | Key | What it fires on |
| --- | --- | --- |
| `range` | 1 | Opening-range breakout: a bar closes beyond the high or low of the first `ORB_MINUTES` (default 15) from 09:15 |
| `trend` | 2 | A SuperTrend flip on the underlying |
| `ema_cross` | 3 | The fast EMA (9) crosses the slow EMA (21) |
| `momentum` | 4 | A breakout through the high or low of the last three bars |
| `continuation` | 5 | A pullback that bounces inside an established trend |

`prev_day` (the previous-day break) is research-only and stays off unless `ENABLED_STRATEGIES` names it.
`StrategySession` returns the first family that fires on a bar. A bar that would fire two families is
therefore credited to the earlier one in the catalogue, so per-strategy results depend on catalogue order.

**Posture** (`STRATEGY_POSTURE`). The code default is `aligned`. The paper profile uses `scout`.

- `scout`: the families fire without any multi-indicator agreement. The fastest entries.
- `aligned`: the signal must close beyond the range and EMA-align on the closed bar.
- `confirmed`: `aligned`, plus price holds beyond the range and a confirmation bar.

**Gates before an entry.** Both gates are off in the code defaults. The paper profile turns them on.

- **Market context** (`CONTEXT_FILTER_ENABLED`, `src/strategy/marketContext.ts`). The day trend, the market
  structure (swing breaks) and the chain bias each vote for or against the side, and a fresh structure shift
  adds a vote. A trending regime needs one net vote, a ranging regime needs two, and buying against the day
  trend needs one more. Market structure against the side is a veto.
- **Option-chain confluence** (`CHAIN_ANALYSIS_ENABLED`, `src/options/chainAnalyzer.ts`). Refuses a CE within
  `CHAIN_ANALYSIS_MIN_HEADROOM_PTS` (default 15) below major call-OI resistance, and a PE within that distance
  above put-OI support. Refuses a bullish entry when PCR is below 0.55, and a bearish entry when PCR is above 1.8.

**Contract:** expiry is the nearest one with at least `MIN_DAYS_TO_EXPIRY` days left. The
strike is ATM ± `STRIKE_OFFSET_STEPS` × the strike step derived from the live chain. Bullish
buys the CE, bearish buys the PE. A positive offset is always further out-of-the-money.
Every check fails closed: a missing leg, a missing quote, a crossed quote, a security-id
mismatch with the scrip master, a spread above `MAX_SPREAD_PCT`, or OI/volume below the
minimums rejects the signal.

**Brackets and sizing:** entry reference is the ask × (1 + `ENTRY_LIMIT_BUFFER_PCT`), rounded up to
tick. Live entries are LIMIT super orders at that price, so a fill can never be above it and the
realised risk never exceeds the sized risk. A limit not filled within `ORDER_TIMEOUT_MS` is cancelled;
a partial fill keeps what filled. Stop = entry × (1 − `STOP_LOSS_PCT`),
rounded up to tick. Target = entry + `TARGET_RR` × risk, rounded down to tick. Lots are
floored so that `lots × lotSize × (entry − stop)` fits `min(CAPITAL_INR, available funds) ×
MAX_RISK_PER_TRADE_PCT`. `CAPITAL_INR` is a ceiling, never raised by a larger broker balance, so
one stop-out stays inside the daily loss limit (also a percentage of `CAPITAL_INR`).
If one lot does not fit the budget, the trade is skipped (`RISK_BUDGET_TOO_SMALL`). The agent never rounds risk up.

**Exits.** The stop and the target are on the broker's super order in live mode. The agent also exits on:
a breakeven move at `BREAKEVEN_AT_RR` (0.8R in the paper profile); a trailing step of `TRAILING_JUMP_PCT`
once the stop has reached breakeven (`calculateTrailingStop`, `src/options/pricing.ts`); the time stop
`MAX_HOLD_MINUTES`; a structure break against the side (`STRUCTURE_BREAK`, when `CONTEXT_STRUCTURE_EXIT` is
on); the daily-loss flatten; a manual close; and the end-of-day flatten at `FLATTEN_BY`.

## Risk controls

| Control | Where | Behaviour |
| --- | --- | --- |
| Mandatory stop loss | `bracketLevels`, `evaluatePreTrade`, SDK super-order schema | Every entry carries a stop and target. An entry cannot be built without them, and the SDK rejects a super order that lacks either. |
| Max risk per trade | `sizePosition`, re-checked in `evaluatePreTrade` | Lots floored to budget. Zero lots means skip. |
| Max daily loss | `DayBook`, `Orchestrator.enforceDailyLoss` | Realised + unrealised day P&L ≤ −limit: entries blocked, all positions flattened, then broker kill switch. Realised P&L is net of estimated charges (`roundTripChargesInr`: ₹20/order brokerage, STT 0.15% on the sell premium, exchange and SEBI fees, stamp duty, GST); the journal records gross, charges and net. The contract note is authoritative. |
| Daily-loss brake | `d` in the cockpit; `ENFORCE_DAILY_LOSS` | `d` toggles the brake for the session, after a second press. The config key sets the starting state. |
| Max daily loss at risk | `DayBook.openRiskInr`, `evaluatePreTrade` | Realised P&L − every open or pending stop − this trade's stop must stay above −limit, across all underlyings and both sides. Otherwise `DAILY_LOSS_AT_RISK`. A trailed stop lowers open risk only on the paper and sandbox venues, which enforce the agent's own model. On the live venue open risk stays at the initial stop. |
| All-in risk | `ALL_IN_RISK_POLICY`; `src/risk/allInLoss.ts`, `src/risk/riskShadow.ts` | `off`, `shadow` or `enforce`. Shadow journals the all-in adverse loss (fill, stop slippage, charges) beside the planned risk and decides on the planned figure. Enforce decides on the all-in figure, and in live mode needs `ALL_IN_RISK_LIVE_ACK`. The roadmap has not approved live enforce. |
| Trades per day, open positions, one per underlying | `evaluatePreTrade` | Hard limits. Code defaults: 3 trades and 1 open position. The paper profile sets unlimited trades and 6 open positions. |
| Opposing sides | `evaluatePreTrade` (`OPPOSING_SIDE_OPEN`) | With `ALLOW_OPPOSING_SIDES=false`, no CE is opened while any PE is open or pending, and the reverse, across all underlyings. The indices move together, so the pair pays decay and spread twice. Code default `true`; the paper profile sets `false`. |
| Cooldown per underlying | `DayBook` | `COOLDOWN_SECONDS` after each exit. |
| Entry window and expiry-day cutoff | `evaluatePreTrade` | Outside the window, or after `EXPIRY_DAY_ENTRY_CUTOFF` on expiry day: no entry. |
| Stale data | `evaluatePreTrade`, `DhanFeed.ageMs` | Spot tick older than `FEED_STALE_MS` (or never received) on local receipt time, or a chain snapshot older than `FEED_STALE_MS`: no entry. |
| Client-side protection | `ExecutionPort.protection`, `UnderlyingAgent.watchStaleOptionTicks`, `UnderlyingAgent.exitReason` | Paper and the sandbox gateway hold the stop and target in the agent, so they fire only on option ticks. The cockpit marks such a stop `client-side`. An open position with no option tick for longer than `FEED_STALE_MS` refuses entries on its underlying and journals `position_stale`. Past `STALE_POSITION_GRACE_MS` it is sold with reason `STALE_DATA`, priced from the last option tick the agent holds, or the entry price if none arrived. The watch cannot tell a silent feed from a strike that has not traded, so a short grace closes quiet strikes. Live positions keep their stop at the exchange and are not watched. |
| Broker P&L exit (live, opt-in) | `LiveExecutionPort.armBrokerPnlExit` | `BROKER_PNL_EXIT=true` sets Dhan's daily loss exit to the daily loss limit at start, with the kill switch left to the agent. A definitive refusal is tried again by the next entry. An ambiguous outcome is never resent: entries are refused as unconfirmed, which halts the underlying. The `lossValue` sign and units, the broker's action when the rule fires and its persistence across sessions are unverified (BROKER_CONTRACT row 1.9). |
| Time stop, EOD flatten | `UnderlyingAgent.exitReason` | `MAX_HOLD_MINUTES`, and every position flattened at `FLATTEN_BY` IST. |
| Kill switch | `DayBook`, `engageBrokerKillSwitch` | Local block on entries at once. Broker kill switch on halts, and on a daily-loss breach once no position is open (Dhan refuses it otherwise), tried again if a late fill reopens and closes one. `BROKER_KILL_SWITCH_ON_BREACH` controls the breach case. |
| Market feed ended by the server | `DhanFeed.handleDisconnect`, `entryBlockReason` | A terminal reason from the market socket (804 to 810: no Data API plan, bad token, connection or instrument cap) ends the feed for good. Entries are refused until the process restarts, the event `feed_terminal` alerts, and exits keep running on the broker's legs and the clock. Fix the cause before restarting. |
| Clock alignment | `assertWarmupClock` | Startup refuses if bar timestamps are inconsistent with the wall clock (wrong epoch convention). |
| Broker positions at start | `Orchestrator.start` | Adopts open option positions only when every one of them matches a position the agent can manage. Otherwise it refuses to start. Reconcile manually first. Until then only the position's bracket legs and Dhan's own intraday square-off (from about 15:18 IST, with a charge) protect it: no agent exit runs. |
| Flatten before the broker does | `loadConfig` | `FLATTEN_BY` must be 15:15 IST or earlier, before Dhan auto-squares intraday positions. |
| Unknown YAML keys | `loadConfig` | A key in the YAML file that sets nothing the agent reads refuses startup and is named in the error. A misspelt limit cannot fall back to its default. |
| Live risk ceilings | `loadConfig` | `MODE=live` refuses `MAX_RISK_PER_TRADE_PCT` above 2 and `MAX_DAILY_LOSS_PCT` above 6, whatever `.env` or the YAML says. Not configurable. |
| Day state across restarts | `restoreDayBook` | Day P&L, trade count, cooldown, and breach state are rebuilt from today's journal file (`data/journal/events-YYYY-MM-DD.jsonl`). A malformed line in that file refuses startup. |
| Drawdown reset | `r` in the cockpit | Resets the daily drawdown threshold after review, on a second press. |

## Execution invariants (live)

- **BUY to open, SELL only to close.** The type system has no SELL-to-open shape. The risk
  gate rejects any non-BUY entry.
- **An exit SELL is sent only when the broker reports a net long quantity**, and never for
  more than that quantity. A negative net halts the underlying.
- **Fills are confirmed from the order-update stream**, not from the HTTP response.
- **No replay of trading writes.** Ambiguous placement outcomes (timeouts, 5xx, 401, 429,
  network) become `ENTRY_UNCONFIRMED` / `EXIT_UNCONFIRMED`, which halt the underlying and
  engage the broker kill switch. Only definitive 4xx rejections are `REJECTED`.
- **The broker P&L exit request is never resent after an ambiguous outcome.** A definitive refusal is tried again by the
  next entry. Any other failure leaves every entry refused as unconfirmed until restart.
- **Reconciliation** polls `positions.list` while tracked positions are open. It reports
  external (bracket) closes and late fills exactly once, through the same terminal-key
  dedupe that prevents double-reporting.

## LLM advisor (`@nemesis-oss/ollama-sdk`)

Enabled with `LLM_ADVISOR=on`, `OLLAMA_HOST`, and `OLLAMA_MODEL`. The advisor gets a
structured snapshot of one entry candidate and must reply with a schema-validated
`{decision: ENTER|SKIP, confidence, reason}`.

- It is a **veto only**. It can stop an entry; it cannot create one, change size, strike,
  stop, or target, or override the risk gate.
- **Fail-closed.** Timeout, network error, auth error, malformed reply, or schema mismatch
  all resolve to SKIP.
- Structured output uses `chatWithSchema` with Zod validation. A second `safeParse` is applied
  to the result.

## Configuration

Every key, its type and its bounds are in `src/config.ts`. [`.env.example`](.env.example) lists every
key the code reads, with its default. Invalid or unsafe values stop startup with a message that names
the key. Unknown keys in a YAML config file stop startup too.

**Where values come from.** `.env` is loaded into the environment at start. When a YAML config file is
given (`CONFIG_FILE`, `CONFIG_PATH` or `--config`), its keys override the same keys from the environment.
`npm run dev:paper` sets `CONFIG_FILE=config.paper.yml`. So for every key that file sets, the `.env` value
has no effect while paper runs under `dev:paper`. Keys the file does not set come from `.env`, and then
from the code default.

### Defaults and the paper profile

The table gives the code default and the value in `config.paper.yml`. `tests/docsConsistency.test.ts` fails
if either column stops matching the code or the file.

| Setting | Env | Code default | Paper profile |
| --- | --- | --- | --- |
| Strategy posture | `STRATEGY_POSTURE` | aligned | scout |
| Risk per trade (%) | `MAX_RISK_PER_TRADE_PCT` | 1 | 2 |
| Daily loss limit (%) | `MAX_DAILY_LOSS_PCT` | 3 | 4 |
| Capital (INR) | `CAPITAL_INR` | 300000 | 1000000 |
| Max lots per order | `MAX_LOTS_PER_ORDER` | 1 | 15 |
| Max trades per day | `MAX_TRADES_PER_DAY` | 3 | 0 |
| Max open positions | `MAX_OPEN_POSITIONS` | 1 | 6 |
| Max positions per underlying | `MAX_POSITIONS_PER_UNDERLYING` | 2 | 2 |
| Max positions per side | `MAX_POSITIONS_PER_SIDE` | 1 | 1 |
| Allow opposing sides | `ALLOW_OPPOSING_SIDES` | true | false |
| Enforce the daily-loss brake | `ENFORCE_DAILY_LOSS` | true | true |
| Cooldown after an exit (s) | `COOLDOWN_SECONDS` | 300 | 900 |
| All-in risk policy | `ALL_IN_RISK_POLICY` | off | shadow |
| Broker kill switch on breach | `BROKER_KILL_SWITCH_ON_BREACH` | true | false |
| Min days to expiry | `MIN_DAYS_TO_EXPIRY` | 0 | 0 |
| Max days to expiry | `MAX_DAYS_TO_EXPIRY` | 4 | 6 |
| Expiry-day entry cutoff | `EXPIRY_DAY_ENTRY_CUTOFF` | 13:30 | 15:15 |
| Entry start (IST) | `ENTRY_START` | 09:30 | 09:15 |
| Entry end (IST) | `ENTRY_END` | 14:30 | 14:00 |
| Flatten by (IST) | `FLATTEN_BY` | 15:05 | 15:15 |
| Stop loss (% of premium) | `STOP_LOSS_PCT` | 30 | 50 |
| Target (R) | `TARGET_RR` | 2 | 1 |
| Max hold (minutes) | `MAX_HOLD_MINUTES` | 20 | 30 |
| Trailing step (%) | `TRAILING_JUMP_PCT` | 0 | 8 |
| Breakeven at (R) | `BREAKEVEN_AT_RR` | 1 | 0.8 |
| Runner mode | `RUNNER_MODE` | false | false |
| Chain analysis gate | `CHAIN_ANALYSIS_ENABLED` | false | true |
| Chain headroom (points) | `CHAIN_ANALYSIS_MIN_HEADROOM_PTS` | 15 | 15 |
| Market context gate | `CONTEXT_FILTER_ENABLED` | false | true |
| Structure-break exit | `CONTEXT_STRUCTURE_EXIT` | false | true |
| Bar size (minutes) | `BAR_MINUTES` | 5 | 5 |
| Opening range (minutes) | `ORB_MINUTES` | 15 | — |
| Paper slippage (bps) | `PAPER_SLIPPAGE_BPS` | 25 | 25 |
| Market feed mode | `DHAN_MARKET_FEED_MODE` | ticker | — |
| Stale grace for client-side positions (ms) | `STALE_POSITION_GRACE_MS` | 30000 | — |
| Broker P&L exit, live only | `BROKER_PNL_EXIT` | false | — |

**Calibration.** The code defaults are starting points (see `.env.example`). The paper profile's exit values,
a 50% stop, a 1R target and a 30-minute time stop, were chosen from Time Machine replays of 2025-10 to 2026-09.
The roadmap counts that period as spent, so those values are in-sample, not validated. Tune per index and per
regime only against data that is not spent.

Live mode refuses `MAX_RISK_PER_TRADE_PCT` above 2 and `MAX_DAILY_LOSS_PCT` above 6 in code, whatever
`.env` or the YAML file says.

## Dhan authentication

Set one source. Setting two is a startup error.

- **OTP login (preferred).** `DHAN_PIN` and `DHAN_TOTP_SECRET`. On first login (or after expiry)
  the agent sends the client id, PIN and a fresh TOTP code to `auth.dhan.co`. Valid tokens are
  cached on disk (`~/.dhanhq` by default, or `DHAN_TOKEN_CACHE_DIR`) so `smoke:live` and
  `dev:paper` in the same user account reuse one token instead of each starting a new PIN+TOTP
  login. Dhan rate-limits repeated logins. The token renews via `RenewToken` before expiry. If a
  request gets a 401, one renewal runs and all calls waiting on it share the result. A TOTP code
  with under 5 s left in its 30 s window is not sent. The agent waits for the next window
  instead, because the code could expire in transit.
- **Static token.** `DHAN_ACCESS_TOKEN`, copied from the Dhan portal. It expires and is not
  renewed. Used only when neither OTP variable is set.
- **Token authority.** `DHAN_TOKEN_AUTHORITY_URL` and `DHAN_TOKEN_AUTHORITY_KEY`, for when another process
  already owns the account's token, such as the Rails app (`GET /api/dhan/token`, key = its `API_OPERATOR_TOKEN`).
  Dhan invalidates the previous token on every login (DH-906), so this agent fetches the token and **never logs in**.
  It re-reads the token at least every 30 seconds, and five minutes before expiry, because the owner can replace it well before expiry (it renews 30 minutes early and force-refreshes on auth errors) and the old token dies at once. A 401 from Dhan forces a fresh read that fails loudly; it never retries the token that was just rejected. The URL must be https, or
  http on loopback. If the owner is down, a still-valid token keeps working and a warning is logged once. At
  startup the agent waits up to ten minutes for the owner, then exits with a message. It does not fall back to its
  own login, because that would invalidate the owner's token when the owner returns. To run without the owner, set
  `DHAN_PIN` and `DHAN_TOTP_SECRET` instead, and do not run the owner that day.

The option-chain gate is separate: `DHAN_SHARED_RATE_LIMIT_KEY` (opt-in, needs `REDIS_URL`) makes chain calls
queue in one line with the Rails app, which reserves slots under `dhan:rate_limit:option_chain`. Both must use the
same Redis database.

The PIN and the TOTP secret together let anyone mint tokens for the account indefinitely.
Keep both in `.env` (gitignored) or your secret store. Never commit them, paste them into an
issue, or put them in a log. The agent logs the token expiry time. It never logs the token,
the PIN or the secret.

The login path is covered by tests that replace the SDK's HTTP call with a stub. The real broker
exchange has not been run from this environment. Run `npm run smoke:live` with real credentials
before relying on it. The first check it runs is the login.

## Tools

Run them with `npm run <name>`. "Reads the broker" means the script calls Dhan. "Writes the ledger" means it
changes PostgreSQL. CLAUDE.md requires an operator to start any script that reads the broker or writes the
ledger. Nothing here starts on its own, except the weekday cron that runs `scripts/session.sh`.

| Script | What it does | Needs | Safety |
| --- | --- | --- | --- |
| `dev:paper` | Paper agent on live market data with simulated fills. Loads `config.paper.yml`. | Dhan, PostgreSQL | writes the paper ledger |
| `dev:sandbox` | Agent on the Dhan sandbox account. | Dhan, sandbox credentials, PostgreSQL, Redis | orders go to the sandbox |
| `dev:live` | Agent on the production account. | Dhan, PostgreSQL, Redis, `LIVE_TRADING_ACK` | real orders |
| `dev`, `start` | Agent with the settings in `.env`. `start` runs the built code. | as the mode in `.env` | as the mode |
| `cockpit:demo` | The cockpit on fakes. | none | none |
| `smoke:live` | Read-only check of the assumptions in "Verification required before live". Places no orders, and forces MODE to paper. | Dhan | reads the broker |
| `smoke:feed` | Read-only check of the market WebSocket: connects, subscribes to index spots, and counts ticks. | Dhan | reads the broker |
| `smoke:trade` | The trade cycle on live market data with paper execution. | Dhan | reads the broker |
| `journal:summary` | Summarises a day's journal: trades, P&L, exit reasons, dropped signals, halts. Takes a date. | none | none |
| `report:performance` | Results by strategy, posture, underlying, option type, exit reason, entry hour, days to expiry and day. Groups under 30 trades are flagged as too few to judge. | none | none |
| `timemachine` | `fetch` builds a research dataset from Dhan rolling-option premiums ([docs/TIME_MACHINE.md](docs/TIME_MACHINE.md)). `run --data FILE` replays the live rules offline. | `fetch`: Dhan | `fetch` reads the broker |
| `trail-study` | Replays the trailing-stop grid over frozen entries. Research only. | none | none |
| `risk:shadow` | The OTA-311 comparison for one IST day, from the journal. Reads only. | none | none |
| `ledger` | `verify` checks the research ledger's hash chain. `register` pre-registers a hypothesis. `import` and `backfill-docs` write past evidence, once each. | none | `register`, `import` and `backfill-docs` write the ledger |
| `reconcile` | Checks the paper ledger for inconsistencies and prints each issue with a severity. The script contains no write statements. | PostgreSQL | reads the ledger |
| `withdraw` | Takes profit out of the paper wallet for the last week or month. Without `--confirm` it only shows the amount. | PostgreSQL, `DHAN_CLIENT_ID` | with `--confirm`, writes the paper ledger |
| `db:status` | Applied migrations, the current trading lease, and live runs that never ended. | PostgreSQL | none |
| `db:migrate` | Applies pending migrations and exits. The agent also applies them at start. | PostgreSQL | writes the schema |
| `db:acknowledge` | Records that a run that never ended has been reviewed, so a new live run can start. | PostgreSQL | writes the ledger |
| `db:reset-wallet` | Sets the paper wallet to `--amount`, or to `CAPITAL_INR` if set, else 1,000,000. `--clean` truncates every paper wallet first. | PostgreSQL | destroys paper balances |
| `reset:paper` | Resets the paper session: truncates the paper tables, deletes paper leases and paper runs, and moves today's journal file aside. | PostgreSQL | destroys paper history |
| `test:integration` | The PostgreSQL and Redis suite. | `TEST_DATABASE_URL`, `TEST_REDIS_URL` | a test database |

`scripts/session.sh` starts the paper agent in a detached tmux session (`tmux attach -t options-agent` for
the cockpit), or stops it with SIGTERM. Cron runs it on weekdays at 08:45 and 15:45 IST. A non-zero exit
sends a crash alert.

Set `ALERT_WEBHOOK_URL` (https, for example an ntfy.sh topic URL) to receive daily-loss stops, kill switch,
halts, rejected entries and exits, late fills and audit gaps as plain-text POSTs. Delivery is best effort and
never blocks trading. Treat the URL as a secret: anyone who knows an ntfy topic can read it.

Run `smoke:live` before a live session, and `journal:summary` after every paper session. Use
`report:performance` to judge settings, and change a setting only on a group with enough trades. Each entry
journals its strategy, posture, direction, option type, expiry, days to expiry and entry minute for this report.
Operator test trades are journalled as strategy `test`, so they never count as a strategy's results.

## Testing

```bash
npm run check   # typecheck + build + tests
```

The suite needs no network and no broker credentials. The advisor is also exercised over HTTP against a local Ollama
stub. The PostgreSQL and Redis suite runs only when `TEST_DATABASE_URL` and `TEST_REDIS_URL` are set, and the
paper-exchange suite only when `PAPER_EXCHANGE_E2E_URL` is set. `npm test` prints the test count. It covers:

- the state machine's full transition table and illegal-transition rejection
- indicators, bar aggregation, the signal families with their postures and gates, including session-boundary
  and previous-day contamination cases
- bracket geometry, tick rounding, lot sizing, contract selection, and expiry choice
- the pre-trade gate (every violation code), the day book, and the kill switch
- the paper venue (gap-through stops, targets fired once, rejected unknown exits)
- the live adapter against a fake broker: placement classification, fill confirmation,
  exit net-quantity guard, short-position halt, reconciliation, and duplicate suppression
- the Ollama advisor's fail-closed behaviour
- the Time Machine: rolling-option parsing and strike pivot, dataset validation, replay fills (target, stop,
  ambiguous bar, gap-through, time stop, EOD, data gap, spread), the live gate inside the replay, Wilson and
  bootstrap intervals, path drawdowns, and every verdict
- end-to-end runtime scenarios: winning trade, EOD flatten, gap-through stop plus
  daily-loss breach, advisor veto, stale data, unconfirmed entry halt, shutdown flatten,
  and refusal to start with broker positions open
- the cockpit's key handling on a fake terminal, and the key table
- the documentation against the code: script names, paths, `.env.example`, the README default and key
  tables, the state diagram, and the statements that were found wrong (`tests/docsConsistency.test.ts`)

**Not covered by tests:** the live DhanHQ wire behaviour, including the broker P&L exit's semantics, and a real feed outage
under the stale-position watch. There are no broker credentials
in this environment. The items under [Verification required](#verification-required-before-live) must be
exercised against a Dhan sandbox or with a minimal-size live run.

## Developer tooling

Coding assistants work from [`CLAUDE.md`](CLAUDE.md), the repository skills in `.claude/skills/`, and a TypeScript
code-intelligence server.

- **`ts-language-mcp` 2.3.1** (`.mcp.json`, exact pin in `devDependencies`, [ADR-012](docs/DECISIONS.md)). It answers
  definition, reference, type, diagnostic and call-hierarchy questions from the TypeScript compiler, for `src`, `tests`
  and `scripts`. It runs from the installed package, so run `npm ci` first. Claude Code asks you to approve the project
  server on first use.
- Four of its tools write files: `rename_symbol`, `format_document`, `apply_code_fix`, and `organize_imports` with
  `apply: true`. Keep them out of allow rules, so each use is prompted. The rest are read-only.
- It is a development dependency only. `npm ci --omit=dev` installs none of it, and nothing in `src/` or `scripts/` imports it.

- **Codebase graph** (`scripts/graphify.sh`, pinned `graphifyy` 0.9.104 through `uvx`, [ADR-013](docs/DECISIONS.md)). It builds
  `graphify-out/` (gitignored) from the code, offline: `scripts/graphify.sh extract . --code-only`, then `query`, `path`,
  `explain`, `god-nodes` or `affected`. It needs `uv`. The wrapper refuses LLM, global-graph, git-hook and assistant-install
  commands.

## Verification required before live

These are assumptions the code depends on that the SDK docs do not settle:

1. **Super-order leg cancel.** `LiveExecutionPort` detaches the bracket with
   `superOrders.cancel({orderLeg: 'STOP_LOSS_LEG' | 'TARGET_LEG'})` before a manual exit. The
   SDK does not document the semantics once the entry has traded. If a leg cancel fails and
   the position is still long, the exit is refused and the underlying halts. Confirm the
   sequence on sandbox.
2. **Epoch convention.** Verified 2026-10-26/27: `DHAN_EPOCH_IST_SHIFTED=false` matches live bars
   (09:15 IST opens at 03:45 UTC), and Dhan's stray after-close history bar is now dropped.
3. **Chain and scrip-master fields.** Verified 2026-10-27 by `smoke:live` on NIFTY, BANKNIFTY and
   SENSEX: no chain leg lacks ltp, bid, ask, OI, volume or security id. The scrip master's
   `TICK_SIZE` is in paise and is converted to rupees (₹0.05).
4. **Freeze limits.** The exchange's per-order freeze quantity is not hardcoded, because the
   exchanges revise it. Set `FREEZE_QTY_<SYMBOL>` (YAML: `limits.freeze_quantity.<SYMBOL>`) to the
   current exchange value for each underlying. An entry is then sized in whole lots at or below it.
   Without it only `MAX_LOTS_PER_ORDER` caps an order. Orders are not sliced.
5. **Broker kill-switch semantics.** Whether an activated kill switch also squares off open
   positions, and whether it blocks exit orders, is not documented in the SDK. The daily-loss
   path engages it only after flat for that reason.
   The local breach state is restored from today's journal on restart. The broker-side switch is
   the durable control: after a breach, reset it in the Dhan console only after reviewing the day.
6. **Holidays.** There is no NSE/BSE holiday calendar. The weekday cron starts the agent on
   holidays too; with no ticks there are no bars or signals, and the 15:45 stop ends it.
7. **Intraday warmup depth.** `WARMUP_DAYS` determines how many days of 5-minute bars are
   seeded. Confirm the Dhan response length for your chosen bar size.
8. **Static IP.** Dhan accepts order API calls only from a registered static IP. Register the
   host's IP in the Dhan console before a sandbox or live run; otherwise every order is rejected.
9. **Market exits are protected limits.** Dhan converts an API `MARKET` order to a LIMIT with market
   price protection. A SELL that rests unfilled is cancelled at `ORDER_TIMEOUT_MS` and the exit is
   retried. The bracket legs are already cancelled by then, so watch this path on sandbox.

### Staged rollout to real money

Do these in order, and do not start a stage until the previous one is clean:

1. **Paper evidence.** At least 30 paper trades on the current settings
   (`npm run report:performance -- --from <first day>`) with positive net expectancy. The Time
   Machine shows these rules near breakeven, so this gate may not pass.
2. **Sandbox.** `MODE=sandbox` with `DHAN_SANDBOX_*` for at least one full session. Watch one
   entry, its stop and target legs, a manual exit (`c` in the cockpit, which exercises item 1
   above), and the EOD flatten. Compare every order against the sandbox order book by hand:
   no tool here reconciles against Dhan.
3. **Live, one lot.** `MODE=live`, `LIVE_TRADING_ACK` set, `MAX_LOTS_PER_ORDER=1`, risk inside the
   built-in ceilings (2% per trade, 6% a day). Start it in the cockpit, not under cron, and check
   Dhan's order book against the journal after each trade and at the end of the day.
4. **Scale.** Raise lots only after a week of one-lot live sessions that match the journal.

## Known limits

- The Time Machine's data source (`/charts/rollingoption`) has not been checked against a live response from this
  environment. Run `timemachine fetch --dump-raw` once before trusting a dataset. It cannot replay the chain gate
  or quote-based liquidity gates. See [docs/TIME_MACHINE.md](docs/TIME_MACHINE.md#verification-required-before-trusting-a-dataset).
- Paper fills model neither queue position nor partial fills, and slippage is a flat bps
  parameter. Paper P&L is an approximation.
- The indicator parameters are starting points, and the paper profile's exit values come from spent replays
  (see Configuration). Treat paper results as a smoke test until the roadmap's gate passes.
- The default feed mode is `ticker` (`DHAN_MARKET_FEED_MODE`). The agent uses the last traded price and time.
  No strategy rule reads bar volume.
- Paper and sandbox stops depend on option ticks. A `STALE_DATA` exit is priced from the last option tick the agent holds,
  so while the feed is silent the paper fill uses a stale mark. Treat paper P&L for those exits as an estimate.

## What was removed

From `crypto-trading-agent` main (the full tree is in the baseline commit):

- `src/binance`, `src/coindcx`: exchange adapters (replaced by `src/dhan`)
- `src/strategies/smc-ml`, `src/minicpm`, `src/research`, `src/learning`, `src/backtesting`. This repository
  has its own `src/research`: the Time Machine, which is offline and not the crypto research plane.
- perpetual, funding, carry, crowding, and open-interest logic in `src/market`, `src/agents`,
  `src/decision`, `src/position`, `src/risk`
- crypto docs, improvement notes, scripts, and tests

The Ink dashboard was rebuilt for options rather than removed. See [Operator cockpit](#operator-cockpit).

`npm test` is a fresh suite for the index-options system. The dependency on
`@nemesis-oss/ollama-sdk` is kept and upgraded to the 1.13 line. The DhanHQ dependency,
`@nemesis-oss/dhanhq-sdk`, is pinned exactly to 2.0.1 from npm. It replaces the earlier git pin to
commit `353901e` (v1.2.0) of the SDK repository.

## Layout

```
src/
  config.ts            validated env and YAML configuration (names and defaults)
  time/                IST clock, calendar arithmetic (expiry rules), epoch conversion, session coverage
  domain/              shared types, composite keys, trade FSM (the transition table)
  dhan/                SDK adapters: client, scrip master, market data, feed, live venue, sandbox gateway, wire recorder
  market/              indicators, bar builder and series, stop lines
  strategy/            signal families, postures, market context, previous-day break (research)
  options/             bracket pricing, lot sizing, contract selection, option-chain analysis
  risk/                pre-trade gate, day book, all-in risk and its shadow journal
  execution/           ExecutionPort contract, paper venues (in-memory and Postgres), gateway port
  llm/                 Ollama advisor
  ops/                 event log, console logger, alerts, day state, journal summary, performance report
  persistence/         PostgreSQL and Redis access, rate gate, trading lease, migrations
  paper/               paper_exchange client and gateway (PAPER_BACKEND=exchange)
  exits/               trailing-stop engine for the research study (see docs/TRAILING_STOPS.md)
  runtime/             orchestrator, per-underlying agent, serial queue, clock guard, trading gate, entry plan, wiring, read-only views
  research/            Time Machine: datasets, historical replay, statistics, context cells, trailing study, ledger (offline)
  ui/                  operator cockpit: pure renderer (cockpit.ts), key table (keymap.ts), Ink app (App.tsx)
  index.tsx            entry point: cockpit on a terminal, plain logs otherwise
tests/                 offline suite (node:test via tsx), one tsconfig.json per folder for tooling
scripts/               operator and research CLIs (run with tsx)
docs/                  architecture, ADRs, roadmap, research pre-registration and ledger
.claude/               repository skills for coding assistants (.claude/skills/)
```
