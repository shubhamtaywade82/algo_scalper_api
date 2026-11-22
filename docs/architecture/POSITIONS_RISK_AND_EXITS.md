# Positions, risk and exits

How open money is managed across the two services: position ownership, profit protection (avoiding
give-back), trailing stops and targets, and the risk hierarchy. Companion to
[`UNIFIED_SYSTEM_PLAN.md`](UNIFIED_SYSTEM_PLAN.md) and
[`CAPABILITY_MATRIX.md`](CAPABILITY_MATRIX.md). The rule that shapes everything:

> **Whoever executes a position, manages it.** The other side mirrors it read-only. There is never a
> second pair of hands on an open position.

## 4.1 Trading authority and position ownership

| Concern | Owner | Mechanism |
|---|---|---|
| Order placement (agent-routed strategies) | Agent only | `ExecutionPort`; Rails stops placing orders for those strategies (plan D1) |
| Order placement (Rails-routed strategies) | Rails only | `Orders::Gateway` paper/live, 11-state order FSM, idempotent client-order-ids |
| Position state | The executor | Agent: `TradeStateMachine` (single transition table, illegal transitions throw) + append-only `trade_events`; Rails: `PositionTracker` (50+ context columns, JSONB meta) |
| Mirror for dashboards | The non-executor | Rails reads the agent's `v_closed_trades` view through the read-only `rails_ro` PG role (S7); the agent heartbeats `agent-snapshot/1` into Redis every ~2 s (S15) |
| Restart safety | Each side | Agent: fail-closed position adoption (cannot match -> refuses to start); Rails: startup position sync + reconciliation loop |
| Broker reconciliation | Each side | Agent: 5 s polling, terminal-state dedup; Rails: 30 s `ReconciliationService` with `reconciliation_runs`/`discrepancies` tables |
| Multi-leg | Rails only | `multi_leg_executor` with hedge-first sequencing + rollback on leg failure (`leg_groups`); the agent is deliberately single-shot |

Both books are single-shot on the agent side (one entry, one exit; no scale-in, no rolls, no hedges)
and multi-leg capable on the Rails side. The unified stack keeps that asymmetry: complexity lives
where the exit machinery already handles it.

## 4.2 Avoiding give-back (profit protection)

Four independent layers, two per service. They never consult each other; each is sufficient alone.

### Agent, per trade

- **Breakeven lock**: at **+0.8 R** profit the stop moves to entry (`breakeven_at_rr: 0.8` in
  `config.paper.yml` - with the 50 % premium stop this is roughly +40 % on premium).
- **Jump trail**: stop steps up by **8 % of entry** as price advances (`trailing_jump_pct: 8`),
  monotonic - it never loosens. On the live venue the broker holds the trailed stop (Dhan super-order
  trailing-jump leg); the agent's level is the estimate.
- Research-only: `GIVEBACK` (keep 1-giveback of peak), `R_STAIRCASE`, `TIME_DECAY` specs in
  `src/exits/trail.ts` and the trail-study harness, unwired to live - the study found **no exit
  variant with a net edge** (all mean R < 0.02), so nothing was promoted.

### Agent, per day

- **Day drawdown baseline**: the operator can lock in realised profit as the new floor
  (`DayBook.resetDrawdownBaseline`); the orchestrator tracks the day peak P&L.

### Rails, per trade (its own positions)

- **Fast profit lock tiers** (single-exit-path emulation of partial profit taking):
  touch **+5 % -> guarantee +2 %**, **+8 % -> +4.5 %**, **+12 % -> +7 %**, **+18 % -> +11 %**
  (`fast_profit_lock_rule.rb` DEFAULT_TIERS, priority 33).
- **Secure profit**: profit >= ₹1 000 tightens the trail to 3 % of peak (priority 35).
- **Emergency peak loss**: peak >= +10 % then < -2 %.
- **Fee-aware breakeven**: locked price must cover exit fees + half spread (`fee_aware_exit_targets`).

### Rails, portfolio

- **Profit-lock ratchet floor**: net profit ₹20 k -> lock 60 %, ₹35 k -> 70 %, ₹50 k -> 73 %
  (`ProfitLockEngine`, levels configurable in `algo.yml`; runs on every `:ltp` event).
- **Drawdown guard**: floor breach -> idempotent global flatten of all positions + entry block for
  the session + Telegram alert (Redis 26 h TTL guard against re-entry loops; manual clear via
  `DELETE /api/drawdown_guard/trip`).

**Unified policy.** Nothing to merge - by design. The unified dashboard (S12) shows all four layers
side by side per position, so the operator sees which layer would have acted first.

## 4.3 Trailing stops and targets

| Engine | Where | Shape |
|---|---|---|
| Mandatory bracket | Agent, every entry | Stop = entry x (1 - SL%), target = entry + RR x risk; **live: Dhan super order (exchange-held)**; paper: client-side with stale-tick watchdog. No bracket -> no order (ADR-004) |
| Jump trail | Agent | +0.8 R breakeven then 8 % steps (above) |
| Runner mode | Agent (opt-in) | No target; trail only |
| Per-tick trailing | Rails | Priority chain: peak-drawdown exit -> HWM update -> fee-aware BE lock -> tailored/direct/tiered SL (`live/trailing_engine.rb`) |
| Three-stage trail | Rails | early slack -> breakeven lock -> HWM trailing, parameterised per index |
| Adaptive trail | Rails | regime low/normal/high -> 15/25/35 % distance |
| Gamma-aware trail | Rails | 4 states (survival / gamma expansion loosens / exhaustion velocity tightens / normal), per-index configs |
| MFE capture | Rails | retrace 35/45 % of peak favourable excursion |
| Research harness | Agent | 14 `TrailSpec` families x ~60 configs with paired bootstrap + White reality-check + Holm correction |

**Rules in the unified stack.**

1. The executor's exits are the only exits on a position (agent brackets for agent trades; Rails
   rule engines for Rails trades). No cross-management, ever.
2. Agent live exits are broker-side wherever the venue supports it; Rails exits are client-side in
   the daemon - its known weakness, tracked in its own docs.
3. Anything promoted from the research harness to live follows the agent's trading-change process:
   pre-registered hypothesis, Time Machine evidence, failing test first (none has qualified yet).
4. `FLATTEN_BY` (agent, default 15:05 IST) fires before the broker's 15:18 forced square-off; Rails
   clears carried overnight positions at 09:15.

## 4.4 Trend and momentum capture

Not unified by contract - unified by **observability**:

- Rails publishes its regime snapshot (RANGING / TRENDING_UP / TRENDING_DOWN / CHOPPY, trend score
  0-21) and the agent journals its own market-context verdict per entry.
- The dashboard juxtaposes both verdicts per underlying; persistent disagreement is itself a signal
  for the operator (and a candidate research label for Time Machine context cells).
- Signal *routing* (Rails strategies -> agent execution) is the intent bridge (plan §5-7);
  signal *generation* stays duplicated and independent on purpose.

## 4.5 Risk hierarchy (S8)

Strongest authority first; each layer is independently sufficient:

1. **Broker kill switch** - Dhan refuses it while positions are open; the agent engages it only once
   flat (after its day-book breach chain: book breach -> normal exits -> flat -> kill switch).
2. **Agent day book** - live ceilings hard-coded, not configurable: **2 % per trade, 6 % per day**
   (`LIVE_MAX_RISK_PER_TRADE_PCT` / `LIVE_MAX_DAILY_LOSS_PCT`); breach blocks entries, then flattens.
3. **Rails circuit breaker** - fail-closed (cache failure = tripped; 8 h TTL); when tripped, the
   intent control block carries `circuit_breaker.tripped = true` and the agent drops pending intents
   with `CIRCUIT_BREAKER`. It never touches the agent's open positions.
4. **Per-book limits** - Rails per-index + global daily limits (incl. unrealized, fail-closed on
   Redis down) for its own book; agent's 22-violation pre-trade gate (kill switch, day loss,
   worst-case-at-risk, count/exposure/opposing-side/cooldown/window/expiry/staleness/price-sanity/
   lot-range/risk-budget/funds) for its own.

**Capital split.** A single configured `AGENT_CAPITAL_SHARE` (shared env, plan Appendix C) partitions
the account so the two books cannot over-commit margin. Margin/netting behaviour with both books
exposed is an open question (plan §15.4) - resolved before any live promotion.

**Data-staleness risk** (both sides, independently): the agent drops entries on stale spot/option
quotes and exits on silent option ticks (`STALE_DATA`); Rails' tick queries carry staleness checks
(`TickQuery` nil = stale) and VixGate is fail-closed. Shared snapshots add their own freshness rule
per reader - a stale snapshot is treated exactly like a stale quote.

## 4.6 Drills (Phase 4 of the plan, mandatory before live)

| Drill | Expected |
|---|---|
| Kill switch with an open paper position | Entries halt; position exits normally; switch engages once flat |
| Rails down mid-session | Agent: no new entries; positions protected; token survives to expiry |
| Agent down mid-session | Rails: dead-man alert; intents expire; (live) broker brackets still held |
| Redis down mid-session | Both fall back to own limiters; watch for Dhan 429; snapshots stop; no wrong entries |
| Agent restart with open position | Fail-closed: adopt-or-refuse, never double-manage |
| Token rotated mid-session | 401 -> refetch; no replayed writes |
| Intent in flight when breaker trips | Dropped `CIRCUIT_BREAKER` if unsubmitted; managed normally if filled |
