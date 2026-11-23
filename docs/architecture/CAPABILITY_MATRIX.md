# Capability matrix - unified options-trading infrastructure

Companion to [`UNIFIED_SYSTEM_PLAN.md`](UNIFIED_SYSTEM_PLAN.md) (which specifies signal routing).
This matrix is the **strategy-agnostic** inventory: what each service can do today, read from the
code of both repositories (analysis date: 2026-11-23), and who owns each capability in the unified
stack. Maturity: **full** = production-shaped; **partial** = works but limited; **missing** = absent.

## Ownership model (summary)

| Capability | Owner | Notes |
|---|---|---|
| Dhan login & token | Rails (authority) | Agent fetches `GET /api/dhan/token`; never logs in itself (DH-906) |
| Underlying ticks | **Each keeps its own feed** | Independent staleness safety; WS connection budget shared |
| Option chain | Rails publishes canonical snapshot | Redis `dhan:chain:{sid}:{expiry}`, schema `chain-snapshot/1` (S3); shared 3 s account rate budget |
| Chain analytics (PCR, max pain, walls) | Rails = analytics hub; agent keeps its entry-time confluence gate | Today PCR/max-pain exist only in the dashboard frontend; backend gap G1 |
| VIX / IV / Greeks | Rails (live authority) | Agent's live path currently has none of the three (research-only); it consumes them as advisory data |
| Strike selection | Each decides for its own trades | Data shared, decisions never shared |
| Positions & exits | Whoever executes, manages | One trading authority per mode; the other side mirrors read-only |
| Risk limits | Layered hierarchy | Broker kill switch > agent day book > Rails circuit breaker > per-book limits |
| Signal routing | Rails forwards *intents*, agent pulls | A signal, not an order; agent decides strike/size/stop/target |

## Summary matrix

| # | Capability | `algo_scalper_api` (Rails) | `options-trading-agent` (TS) | Unified owner |
|---|---|---|---|---|
| 1 | Underlying data (ticks, candles, replay) | **full** - WS `MarketFeedHub` (India VIX rides the same socket), Redis `TickCache`, `CandlePoller`, 1-minute `candles` table (~163k rows), REST `GET /api/candles/:index_key` | **full** - `DhanFeed` WS (incl. manual binary index-packet parsing), `CandleBuilder`, `intradayCandles` warmup, Time Machine replay | Each keeps its own feed; Rails also serves consumers |
| 2 | Option-chain data | **full** - `DhanAdapter`, `ChainWatchService` (4 s staggered REST poll ATM±5 + 1 s tick merge, per-leg ltp/oi/oi_change/iv/greeks/bid/ask), REST `GET /api/option_chain/:index_key`, ActionCable `option_chain_<INDEX>` | **full** - `optionChain()` with 3 s account gate (serialized + in-flight dedupe), JSONL chain recorder, cockpit chain watch | **Rails publishes the canonical snapshot** (S3); agent consumes + records |
| 3 | Chain analysis | **partial** - OI flow score (5-sample window), gamma-ramp detector, delta acceleration, 1,600-line chain analyzer; **PCR and max pain are computed frontend-only** (`dashboard/src/views/OptionChain.jsx`) with no backend service, and the frontend "max pain" is just the max-call-OI strike | **full-minus** - PCR (full + ATM), OI walls as support/resistance, ATM straddle & expected range, sentiment score; **no max pain** | Rails = analytics hub; agent keeps its entry-time confluence gate; **backend PCR + true max pain = gap G1** |
| 4 | VIX | **full** - `VixGate` (entry ceiling 20.0, force-exit 22.0, fail-closed; evaluated at daemon boot + `VixGateGuard#ensure_evaluated!` in the 41-guard pipeline; standalone `VixGateJob` exists but is not in `recurring.yml`), `vix_at_entry` persisted, REST `GET /api/market/vix` | **research-only** - `vixTerciles()` in Time Machine context cells; live path never reads VIX | **Rails is the live VIX authority**; agent consumes (G2) |
| 5 | IV | **full mechanics, unarmed** - broker chain IV, BSM Newton-Raphson solver, `iv_rank_tracker` (rolling 20 d / <=500 samples / min 30), `iv_snapshots` table, pre-market baseline job - **but `IvSnapshotJob` and `PreMarketIvBaselineJob` are not in `recurring.yml`, so the IV-rank guards no-op until scheduled** (the `IvVolGateGuard` comment says so itself) | **research-only** - `ivBucketFor()` / `atmIvByMinute()` in replay research; live path has no IV | **Rails is the IV authority**; schedule the jobs (G7, quick win), then agent consumption (G2) |
| 6 | Greeks | **full** - complete BSM (`theoretical_price, delta, gamma, theta/day, vega/1%, rho/1%`, r = 0.065, dividend-yield aware), broker chain values first (`Calculator` 3-tier: broker -> BSM -> heuristic), per-leg greeks in ChainWatch broadcasts; rho internal-only | **missing** - no greeks anywhere; risk is premium-based by design | **Rails owns Greeks**; agent consumes per-strike greeks via chain snapshot, position aggregation proposed (G3) |
| 7 | Strike selection | **full** - 4 parallel selectors (NEMESIS trend-score OTM depth; qualification tiers execution_only/scale_ready/full_deploy; prop-style weighting delta 0.35/liquidity 0.30/distance 0.20/flow 0.15; chain-analyzer scoring + expected-move validator), per-index rules, premium band | **full** - ATM ± offset steps with fail-closed liquidity floors (spread <= 2 %, OI >= 10 000, volume >= 1 000, two-way security-id check), expiry window 0-6 DTE | **Each decides for its own trades**; data shared, decisions never |
| 8 | Positions management | **full** - `PositionTracker` (602 lines, 50+ context columns), state machine, 3-layer cache, orders manager + multi-leg executor + 30 s reconciler, double-entry ledger, paper venue | **full** (single-shot model) - `TradeStateMachine` (one transition table), per-underlying serial agents, restart position adoption (fail-closed), append-only `trade_events` ledger; no scale-in/roll/hedge | Whoever executes, manages; the other mirrors read-only (S7) |
| 9 | Avoid giving back | **full** - portfolio `ProfitLockEngine` (₹20 k -> 60 %, ₹35 k -> 70 %, ₹50 k -> 73 % ratchet floor) + `DrawdownGuard` (idempotent global flatten + session entry block + Telegram), per-trade `fast_profit_lock` tiers (+5 %->+2 %, +8 %->+4.5 %, +12 %->+7 %, +18 %->+11 %), `secure_profit` (>= ₹1 000 -> 3 % peak-drawdown), fee-aware breakeven | **full** - breakeven at 0.8 R, 8 % jump trail (monotonic), day drawdown baseline reset, `GIVEBACK` trail spec (research, not wired) | Per-trade: the executor; portfolio layer: each book's own engine - independent layers |
| 10 | Trailing stops & targets | **full** - per-tick `TrailingEngine` (peak-drawdown -> HWM update -> fee-aware BE -> tailored/direct/tiered SL), 3-stage engine, regime-adaptive (15/25/35 %), gamma-aware engine (4 states), MFE retrace exits, bracket placer, R:R and premium targets | **full** - mandatory bracket (stop + target at entry; live: Dhan super order, exchange-held), 8 % jump trail, `RUNNER_MODE`; research: 14 `TrailSpec` families (~60-config grid, paired bootstrap + White reality-check) - **no variant showed a net edge** | Whoever executes, manages exits (never both on one position) |
| 11 | Trends & momentum | **full** - `TrendScorer` (0-21 composite), regime detector (RANGING/TRENDING_UP/TRENDING_DOWN/CHOPPY), 19 indicator files, full SMC suite (7 detectors, MTF bias, confluence, AVRZ), momentum validator/scaler | **full** - EMA/ALMA/HMA/adaptive SuperTrend (efficiency-ratio scaled), 5 signal families x 3 postures, market-context voting gate (regime + structure, structure-break exit) | Each keeps its own signal layer; Rails publishes a regime snapshot for observability |
| 12 | Risk limits | **full** - 41-guard entry pipeline, circuit breaker (fail-closed, REST trip/untrip, 8 h TTL), per-index + global daily limits incl. unrealized (fail-closed on Redis down), dynamic risk allocation, 24 exit rules + `UnifiedExitChecker` | **full** - 22-violation pre-trade gate, shared `DayBook`, live ceilings hard-coded (2 %/trade, 6 %/day), broker kill switch, all-in-loss model + shadow comparison | Layered hierarchy (S8) |
| 13 | Execution | **full** - `GatewayPaper` (slippage model) / `GatewayLive` (3 retries, 8 s timeout, idempotent client-order-ids), 11-state order FSM, limit chaser, slicer (freeze qty), stuck-order cleanup, 30 s reconciliation, multi-leg with rollback | **full** - `ExecutionPort` 4 paths (PG paper / paper_exchange / Dhan sandbox / live), super-order brackets, WS fill confirmation, UNCONFIRMED never replayed -> halt, 5 s reconciliation, broker P&L exit opt-in | One authority per mode (D1) |
| 14 | API surface | **full** - ~50 REST resources, 9 ActionCable channels, static-token auth tiers (dashboard/operator/settings/circuit-breaker; production fails closed), OpenAPI **partial** (18 paths), 17 read-only MCP tools | **missing** (by design) - no inbound ports (Dockerfile states it), Ink terminal or headless; outbound alerts webhook/Telegram | **Rails is the API gateway**; the agent pulls (D3) |
| 15 | Persistence | **full** - 91 tables (incl. `iv_snapshots`, ledger, research warehouse, `solid_queue`), documented Redis key registry | **full** - append-only `trade_events` + `v_closed_trades`, leases (Postgres, not Redis - failover safety), paper venue, JSONL journal WAL | Separate databases, separate roles (`deploy/unified/initdb/`); read-only bridge (S7) |
| 16 | Events & messaging | **partial** - in-process `EventBus` (debug-only by design; live services use direct calls), EventStore append + replay, Telegram; **no outbound webhook** | **partial** - in-process event log, outbound alerts webhook (ntfy-style) + Telegram | Redis snapshot + HTTP pull; no broker introduced (deliberate) |

## Notable asymmetries (why both services stay)

- The **agent's execution discipline** is the strongest in the pair: fail-closed restart, position
  adoption, UNCONFIRMED-never-replayed, broker-side brackets, hard-coded live ceilings. Rails'
  equivalent is good but its exits live client-side in the daemon.
- The **Rails analytics stack** is the strongest: VIX gate, IV rank, BSM greeks, chain flow, regime,
  SMC - none of which the agent's live path has. But two analytics pieces are **not actually armed**:
  the IV snapshot/baseline jobs are unscheduled (guards no-op), and PCR/max-pain live only in the
  dashboard JS. Closing those two is the cheapest capability win in the whole stack (G1, G7).
- **Strike selection** exists on both sides with different philosophies. Sharing either would violate
  "share data, not decisions", so both stay.
- **Max pain** is missing everywhere in backend code; the dashboard's "max pain" is the max-call-OI
  strike, which is not the payout-minimising strike. A proper implementation belongs in the analytics
  hub (G1).

## What is deliberately NOT unified

Per plan §14 (explicitly not recommended) and the ownership model above:

- Merging the codebases or rewriting either service.
- Sharing live tick feeds or the pre-trade gate (two safety layers -> one failure domain).
- One side dictating strike, size, stop or target to the other.
- Running both engines live on one account simultaneously (the agent refuses to start over a broker
  position it cannot adopt; Dhan's account kill switch cannot engage with open positions).

## Integration status (what is already done)

| Piece | Status | Where |
|---|---|---|
| Token authority (agent reads token from Rails, never logs in) | **deployed** | agent PR #14; `dhan/token_manager.rb`, `/api/dhan/token` |
| Shared chain rate budget (byte-identical Lua, 3 s/account) | **deployed** | `dhan/shared_rate_limit.rb`, agent `ReservationRateGate`, key `dhan:rate_limit:option_chain` |
| Unified runtime (one Postgres, one Redis, one login) | **deployed** | `deploy/unified/` (compose, initdb, checklist, staged rollout) |
| Canonical chain snapshots (S3) | **planned** | plan §6 S3; schema `chain-snapshot/1` in `contracts/` |
| Trade-intent intake (S6) | **planned** | plan §7; schemas in `contracts/`; `/api/trade_intents` does not exist yet |
| Read-only ledger + agent dashboard (S7/S12) | **planned** | plan §6 |

## File-level references (spot checks)

| Fact | Where |
|---|---|
| VIX gate thresholds 20/22, fail-closed | `app/services/market/vix_gate.rb` (entry_ceiling / force_exit_above) |
| VIX boot + guard evaluation (job unscheduled) | `lib/trading_system/bootstrap.rb#boot_market_gates!`, `app/services/entries/guards/vix_gate_guard.rb` |
| IV jobs unscheduled (guards no-op) | `app/jobs/iv_snapshot_job.rb`, `app/jobs/pre_market_iv_baseline_job.rb` vs `config/recurring.yml`; comment in `app/services/entries/guards/iv_vol_gate_guard.rb` |
| PCR / max pain frontend-only | `dashboard/src/views/OptionChain.jsx` (pcr = putOi/callOi; maxPain = maxCallOiStrike) |
| fast-profit-lock tiers | `app/services/risk/rules/fast_profit_lock_rule.rb` (DEFAULT_TIERS) |
| Portfolio profit-lock floor levels | `app/services/portfolio/profit_lock_engine.rb` |
| BSM greeks + IV solver | `app/services/options/greeks/black_scholes.rb`, `calculator.rb` |
| Chain watch + WS channel | `app/services/options/chain_watch_service.rb`, `app/channels/option_chain_channel.rb` |
| IV rank window (20 d / 500 / min 30) | `app/services/options/iv_rank_tracker.rb` |
| 41-guard pipeline | `app/services/entries/entry_guard_pipeline.rb` |
| Agent liquidity gates (2 % / 10 k / 1 k) | `options-trading-agent/src/config.ts` (MAX_SPREAD_PCT, MIN_OPEN_INTEREST, MIN_VOLUME) |
| Agent live ceilings (2 % / 6 %, hard-coded) | `options-trading-agent/src/config.ts` (LIVE_MAX_RISK_PER_TRADE_PCT, LIVE_MAX_DAILY_LOSS_PCT) |
| Agent paper exits (50 % SL, 1 R, 8 % jump, 0.8 R BE) | `options-trading-agent/config.paper.yml` (exits) |
| Agent PCR + OI walls + sentiment | `options-trading-agent/src/options/chainAnalyzer.ts` |
| Agent trailing research (14 specs) | `options-trading-agent/src/exits/trail.ts`, `src/research/trailStudy.ts` |
| Agent token authority consumption | `options-trading-agent/src/dhan/authorityToken.ts` |
