# Market data and analytics layer

The heart of the unified infrastructure: who produces each kind of market data, who consumes it,
which contract it travels on, and what is missing. This is the **strategy-agnostic** layer - it must
serve any future signal source, not just today's. Companion to
[`UNIFIED_SYSTEM_PLAN.md`](UNIFIED_SYSTEM_PLAN.md) (signal routing) and
[`CAPABILITY_MATRIX.md`](CAPABILITY_MATRIX.md) (full inventory).

## Planes and core decisions (context)

| Plane | Owner | Contains |
|---|---|---|
| Control + analytics | Rails | Feeds, canonical chain, VIX/IV/Greeks analytics, guards, circuit breaker, dashboard, MCP, token authority |
| Execution | Agent | Signal intake, strike selection, sizing, pre-trade gate, brackets, trailing exits, ledger |
| Shared data | Redis | Rate budget, canonical chain snapshots, agent snapshot (heartbeat); **no decisions** |
| System of record | Postgres | Two roles, separate databases (`deploy/unified/initdb/`); agent trades live in the agent DB, read by Rails through a read-only role (S7) |

1. **Rails is the market-data and analytics authority.** It owns the Dhan login, the option-chain
   rate budget, and the only complete VIX/IV/Greeks stack. Everything it publishes is *data with
   provenance* (`source`, `fetched_at_ms`, gate state), never a verdict.
2. **The agent consumes data, keeps every decision.** Strike, size, stop, target, and whether a VIX
   reading forbids entry are the agent's own policy applied to shared data.
3. **Independent tick feeds.** Both subscribe to market data separately on purpose: staleness
   detection is a safety layer and must not share a failure domain. Only the *connection budget* is
   shared (Redis-leased slots, S5).
4. **Agent pulls; Rails never pushes.** No inbound ports on the agent. "Rails is down" naturally
   means "no new entries"; open positions keep their broker-side brackets.

## 3.1 Underlying data

**Rails** (`app/services/live/market_feed_hub.rb`, `tick_cache.rb`, `tick_query.rb`,
`candle_poller_service.rb`, `app/services/candles/repository.rb`): Dhan WS (ticker/quote/full) with
watchlist subscribe, reconnect watchdog and frame-freshness checks; India VIX rides the same socket;
write-through tick cache with staleness semantics (`TickQuery` nil = stale); 30 s candle polling with
gap backfill; persisted 1-minute index candles (~163k rows) with higher timeframes derived on read;
REST `GET /api/candles/:index_key`.

**Agent** (`src/dhan/feed.ts`, `src/market/barSeries.ts`, `src/dhan/marketData.ts`): its own Dhan WS
with manual binary index-packet parsing (the SDK lacks that branch), tick-freshness age, terminal
close codes 804-810 permanently refusing new entries, upsert-idempotent bars, intraday charts with
warmup, and the Time Machine research replay (real recorded premiums, not synthetic).

**Unified design.** Feeds stay **separate**. Sharing is limited to: the WS *connection budget*
(Redis-leased slots, S5); historical candles export to the agent's Time Machine format (S17, so one
hypothesis can be replayed on both engines); and spot readings for analytics the agent does not
maintain itself (it always re-reads its own feed for any *decision*).

## 3.2 Option chain

**Rails** is the canonical publisher: `ChainWatchService` polls ATM±5 per index every 4 s
(staggered, under the shared budget), merges ticks every 1 s, and broadcasts over ActionCable
`option_chain_<INDEX>` with per-leg `ltp/oi/oi_change/iv/delta/gamma/theta/vega/bid/ask`;
`GET /api/option_chain/:index_key` serves REST consumers; legs held by open positions are protected
from unsubscription.

**Agent** fetches on demand behind the same 3 s account gate (serialized queue, in-flight dedupe,
per-key cache), and records every snapshot to JSONL for chain-replay research.

**Unified design (S3).** One canonical snapshot per (underlying, expiry) at Redis
`dhan:chain:{sid}:{expiry}`, contract [`chain-snapshot/1`](../../contracts/schemas/chain-snapshot-1.schema.json)
(this repo, `contracts/`). Whoever holds the rate slot writes; both read; each applies its own
freshness limit against `fetched_at_ms`. This:

- halves the chain calls per hour at identical coverage (the measurable Phase 1 gate);
- gives the agent per-strike IV/greeks it cannot otherwise get (Dhan's normalised chain on the TS
  side carries no IV);
- gives Rails the agent's recorded chain history for free (the agent's JSONL recorder keeps running
  on snapshot data).

## 3.3 Chain analysis

| Analysis | Rails today | Agent today | Unified |
|---|---|---|---|
| OI support/resistance (walls) | implicit (chain radar, gamma ramp) | **full** - max call OI = resistance, max put OI = support, with point distances | Rails analytics hub computes and publishes alongside the snapshot; agent keeps its entry-time confluence gate |
| PCR (full chain + ATM) | **frontend-only** (`dashboard/src/views/OptionChain.jsx`: `pcr = putOi/callOi`, with sparklines) - no backend service, no API | **full** - plus gates (PCR < 0.55 no long CE, > 1.8 no long PE) | Backend PCR in the analytics hub (G1) serving dashboards/reports; the agent keeps its own gate version (data shared, decisions not) |
| Max pain | **frontend-only and not max pain** - the dashboard plots the max-call-OI strike, which is not the payout-minimising strike | **missing** | **Gap G1**: proper payout-minimising max pain in the analytics hub, published with snapshot metadata |
| OI flow / unusual activity | **partial** - flow score (OI change 50 % + volume spike 30 % + price change 20 %, 5-sample rolling window), gamma-ramp detector, delta acceleration | missing (recorder only) | Rails owns; publish flow score per strike with snapshot metadata. Deeper OI analytics (buildup classification matrix, GEX profile, longer OI-change series) remain open extensions |
| ATM straddle / expected range | missing | **full** (straddle premium -> expected range band) | Compute in the analytics hub for both |
| Sentiment score | missing | **full** (-100..100 bull/bear/neutral) | Keep agent-side (it feeds its gate); mirror into dashboards via reports |

**Principle.** *Measurements* (PCR value, max-pain strike, flow score) belong to the analytics hub and
are published as data. *Thresholds* (PCR > 1.8 forbids a short) stay with whoever trades.

## 3.4 VIX

**Rails is the VIX authority**: the only INDIA_VIX WS subscription (`IDX_I:21`, on the market-feed
socket), a three-tier LTP fallback (tick cache -> instrument -> REST), and `VixGate` - a fail-closed
state machine that locks its own entries above 20.0 and arms force-exit above 22.0, evaluated at
daemon boot and re-checked by `VixGateGuard#ensure_evaluated!` in the 41-guard pipeline (the
standalone `VixGateJob` exists but is not scheduled - boot + guard evaluation cover the live path),
`vix_at_entry` persisted per position, exposed at `GET /api/market/vix`.

**Agent today**: live path never reads VIX. Research uses `vixTerciles()` - India VIX daily opens
bucketed into LOW/MID/HIGH terciles over a 252-session lookback - purely as Time Machine context
labels ("never changes a trade").

**Unified design (G2).** The agent consumes
[`vix-snapshot/1`](../../contracts/schemas/vix-snapshot-1.schema.json) (reading + Rails gate state)
and applies its **own** policy. Candidate policies, in increasing ambition (each must first be
validated in Time Machine replays, honouring the agent's no-unvalidated-live-rules invariant):

1. *Observability only*: journal VIX tercile at entry (research label becomes live label).
2. *Sizing modulation*: HIGH tercile -> halve risk budget per trade (a data-driven tweak, not a veto).
3. *Entry gate*: refuse new entries above a ceiling of its own choosing (Rails' 20/22 are NOT
   inherited - share data, not decisions).

## 3.5 IV

**Rails**: all the mechanics exist - broker chain IV where present, its own Newton-Raphson/bisection
BSM solver otherwise, a rolling **IV rank** (20 trading days / <=500 samples / min 30, percentile;
absolute-band fallback when history is thin), an `iv_snapshots` table, and a pre-market baseline job.
**But the two IV jobs are not in `config/recurring.yml`**, so the IV history never accumulates and
the `iv_vol_gate_guard` / `selling_iv_rank_guard` are no-ops today (the guard's own comment says so).
Scheduling them is the single cheapest capability win in the stack (**G7**, roadmap).

**Agent**: research-only (`ivBucketFor()` - 20-day percentile bucketed by same-minute-of-day; Time
Machine datasets carry an `iv` field). Live path has no IV at all; the Dhan normalised chain on the
TS side does not expose IV.

**Unified design (G2).** Two consumption paths:

- *Per-strike IV* arrives free with `chain-snapshot/1` (Rails populates `iv` per leg).
- *IV rank context* arrives via [`iv-snapshot/1`](../../contracts/schemas/iv-snapshot-1.schema.json)
  (endpoint lands with G2, once the snapshots job makes rank non-null). The agent's use is the same
  escalation as VIX: journal first, then size modulation (high IV rank -> fewer lots / cheaper
  premium band), never a borrowed threshold.

## 3.6 Greeks

**Rails**: complete BSM (`theoretical_price, delta, gamma, theta/day, vega/1%, rho/1%`, r = 0.065
India 91-day T-bill default, dividend-yield aware), with a disciplined 3-tier sourcing policy -
broker chain values first, BSM when IV+DTE available, legacy ATM±N heuristic last - and per-leg
greeks already broadcast by ChainWatch (rho is internal-only, via BSM).

**Agent**: none. Position risk is deliberately premium-based (stops/targets in rupees of premium).

**Unified design.**

- Stage 1 (free): per-strike greeks in the chain snapshot give the agent everything needed for
  *reporting* - entry delta, position theta burn, vega exposure per lot.
- Stage 2 (G3, proposed): the analytics hub publishes
  [`greeks-snapshot/1`](../../contracts/schemas/greeks-snapshot-1.schema.json) per position (net
  delta/gamma/theta/vega/rho with a `source: broker|bsm|heuristic` provenance tag). The agent's
  *decisions* stay premium-based until its own research (Time Machine) shows a greeks-based exit rule
  with a net edge - consistent with its "no strategy has shown an edge" honesty.

## 3.7 Strike selection

Both sides select strikes for their own trades and will keep doing so:

- **Rails**: qualification-tiered (execution_only / scale_ready / full_deploy), NEMESIS trend-score
  OTM depth (score >= 12 -> 1 OTM, >= 18 -> 2 OTM; momentum windows -> ITM/ATM), prop-style weighted
  (delta 0.35 / liquidity 0.30 / distance 0.20 / flow 0.15, gamma-pressure multiplier), per-index
  rules + premium band + expected-move validator.
- **Agent**: ATM ± offset steps with strike step derived from the live chain, hard fail-closed
  liquidity floors (spread <= 2 %, OI >= 10 000, volume >= 1 000, two-way security-id check against
  the scrip master), expiry window 0-6 DTE.

The infrastructure's job is to make sure **both selectors see the same chain** (S3) and that the
analytics hub publishes the shared context (walls, max pain, expected range) so a human can compare
choices after the fact.

## 3.8 Trends and momentum

Both sides keep independent signal layers (the agent: EMA/ALMA/HMA/adaptive SuperTrend, 5 families,
market-context voting with structure-break exits; Rails: 0-21 trend scorer, regime detector, 19
indicator files, full SMC suite). The shared piece is **observability**: Rails' regime snapshot and
the agent's market-context verdict land side by side in dashboards, so the operator can see when the
two engines disagree about the same market - historically the most interesting moment of any session.
No attempt is made to unify the *detectors*: two independent trend opinions are a feature.
