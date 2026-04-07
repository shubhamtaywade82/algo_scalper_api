# Entry and Exit Rules

Canonical reference for entry guards and exit rules as implemented in the codebase.

**Implementation:** `app/services/entries/entry_guard_pipeline.rb`, `app/services/entries/entry_guard.rb`, `app/services/live/unified_exit_checker.rb`, `app/services/live/risk_manager_service/runner.rb`, `app/services/live/risk_manager_service/exit_enforcement.rb`.

**Optional pre-pipeline filter (signal path):** After strikes are qualified, `Signal::Engine` may run `MarketContext::RegimeComposer`, `Options::ChainSignalExtractor`, and `Trading::MarketPermissionGate` before building `entry_metadata` for `EntryGuard`. This is **not** part of `EntryGuardPipeline`; it is configured under `market_context` in `config/algo.yml`. See `docs/trading/market_context_and_permission_gate.md`.

---

## Entry Rules

Entry requests are validated by a **20-guard pipeline** (first block wins). After the pipeline passes, additional **post-pipeline checks** run before order placement.

### Entry Guard Pipeline (Order)

Run by `Entries::EntryGuardPipeline#run`. Each guard returns `:pass` or `{ blocked: reason }`.

| # | Guard | Class | Purpose |
|---|-------|--------|---------|
| 1 | **Drawdown** | `Guards::DrawdownGuard` | Block if portfolio drawdown limit hit. |
| 2 | **Entry policy** | `Guards::EntryPolicyGuard` | Block if entry policy disallows current entry. |
| 3 | **Circuit breaker** | `Guards::CircuitBreakerGuard` | Block if `Risk::CircuitBreaker.instance.tripped?`. |
| 4 | **Midday quality** | `Guards::MiddayQualityGuard` | Block if quality gate fails. Bypassed entirely when ADX >= `trending_adx_bypass` (default 28) — covers power-trend cases. |
| 5 | **Edge failure** | `Guards::EdgeFailureGuard` | Block if `Live::EdgeFailureDetector.instance.entries_paused?(index_key:)`. Reason includes resume time. |
| 6 | **Loss streak** | `Guards::LossStreakGuard` | Block if consecutive losses >= `loss_streak_guard.consecutive_losses_threshold` (default: 2). |
| 7 | **Daily limits** | `Guards::DailyLimitsGuard` | Block if daily loss/profit/trade limits for the index are exceeded. |
| 8 | **Max concurrent** | `Guards::MaxConcurrentGuard` | Block if max simultaneous open positions reached. |
| 9 | **Instrument lookup** | `Guards::InstrumentLookupGuard` | Block if instrument cannot be resolved. Sets `context[:instrument]` for later guards. **Required by ExpiryWeekPowerTrendGuard.** |
| 10 | **LTP resolution** | `Guards::LtpResolutionGuard` | Block if LTP for the pick is missing or invalid. Sets `context[:ltp]`. |
| 11 | **Expiry week power trend** | `Guards::ExpiryWeekPowerTrendGuard` | **Does NOT block.** Enriches `context[:expiry_power_trend] = true` and `entry_metadata[:expiry_power_trend] = true` when pattern detected: ADX >= 40 + within 5 days of monthly expiry + time 12:00-13:45. |
| 12 | **Time regime** | `Guards::TimeRegimeGuard` | Block if current time regime for the index does not allow entries. S3 chop-zone block (11:30-13:45) is **bypassed** when `context[:expiry_power_trend] = true`. |
| 13 | **BANKNIFTY last week** | `Guards::BankniftyLastWeekGuard` | Only for BANKNIFTY: block unless within last week before monthly expiry. |
| 14 | **Weekly expiry** | `Guards::WeeklyExpiryGuard` | Block if the selected contract is not a weekly expiry. |
| 15 | **BOS structure** | `Guards::BosStructureGuard` | Block if Break-of-Structure contract requirement not satisfied. |
| 16 | **Exposure** | `Guards::ExposureGuard` | Block if exposure limit would be exceeded. For Supertrend contract: block if active Supertrend position already exists for the index. Otherwise uses `max_same_side` from index config. Sets `context[:side]`, `context[:is_supertrend]`. |
| 17 | **Cooldown** | `Guards::CooldownGuard` | Block if re-entry cooldown is active for the pick symbol. Uses `index_cfg[:cooldown_sec]`. |
| 18 | **Sizing** | `Guards::SizingGuard` | Block if sizing requirements not met. |
| 19 | **Risk policy** | `Guards::RiskPolicyGuard` | Block if risk policy rejects entry. |
| 20 | **SMC navigator** | `Guards::SmcNavigatorGuard` | Block if SMC alignment check fails. |

### ExpiryWeekPowerTrendGuard Details

- **File**: `app/services/entries/guards/expiry_week_power_trend_guard.rb`
- **Pattern**: ADX >= 40 (from `context[:pick][:adx_value]`) + within `expiry_days_max` days of nearest monthly expiry + current time between `entry_start` and `entry_end`
- **Effect**: Sets `context[:expiry_power_trend] = true` — does NOT block
- **Downstream effect**: `TimeRegimeGuard` reads this flag and skips the S3/S4 chop-zone block
- **Config** (`config/algo.yml`):
  ```yaml
  expiry_week_power_trend:
    enabled: true
    adx_min: 40
    expiry_days_max: 5
    entry_start: "12:00"
    entry_end: "13:45"
  ```

### Post-Pipeline Checks (EntryGuard)

After the pipeline passes, `EntryGuard.try_enter` runs:

- **BOS / structure gate** — For non-Supertrend entries, `enforce_structure_entry_gate` must pass (BOS level, confirmation, distance). Supertrend contract bypasses with a synthetic BOS context.
- **Cooldown** — Checked again for the pick symbol with `index_cfg[:cooldown_sec]`.
- **Weekly-only (NIFTY/SENSEX)** — For non-Supertrend, non-paper entries, blocked unless the pick is a weekly contract (`weekly_contract?`).
- **Execution profile** — `Trading::InstrumentExecutionProfile.for(symbol)`: if permission is `:execution_only`, block unless profile allows execution-only.
- **Sizing cap** — `Trading::CapitalAllocator.max_lots(...)` must be > 0.
- **Quantity** — `Capital::Allocator.qty_for(...)` combined with cap; quantity must be lot-aligned and >= 1 lot.
- **Order placement** — `Orders.config.gateway.place_market(...)`; on failure or missing order number, entry fails.

### Configuration (Entry)

- **Indices:** `config/algo.yml` → `indices[]` (per-index `cooldown_sec`, `max_same_side`, `capital_alloc_pct`, etc.)
- **Time regimes:** `config/algo.yml` → `risk.time_regimes` with sessions S1-S4, each with `allow_entries`, `min_adx`, `max_tp_rupees`
- **Loss streak guard:** `config/algo.yml` → `loss_streak_guard.enabled`, `consecutive_losses_threshold` (default 2)
- **Midday quality guard:** `config/algo.yml` → `midday_guard.enabled`, `min_adx: 20`, `trending_adx_bypass: 28`
- **Expiry power trend:** `config/algo.yml` → `expiry_week_power_trend.*`
- **Circuit breaker:** API `GET/POST/DELETE /api/circuit_breaker/trip`; state in Rails.cache/Redis

---

## Exit Rules

Exits are evaluated in **two paths**. Both ultimately call `Live::ExitEngine.execute_exit` (single source of truth).

### Path A: High-Frequency (Per-Tick) — UnifiedExitChecker

Used by `Live::RiskManagerService` via `EventBus.subscribe(:ltp)`. **Priority order (first match wins):**

| # | Rule | Condition | Config (algo.yml) |
|---|------|-----------|-------------------|
| 1 | **Early trend failure** | Enabled and profit < `profit_threshold`; then `Live::EarlyTrendFailure.early_trend_failure?(position_data)` (ADX/trend reversal). | `exit.early_exit.enabled`, `exit.early_exit.profit_threshold` (DECIMAL) |
| 2 | **Stop loss** | **Static:** `pnl_pct <= -static_sl`. **Adaptive (type == 'adaptive' and pnl < 0):** `Positions::DrawdownSchedule.reverse_dynamic_sl_pct(...)` vs current `pnl_pct`. | `exit.stop_loss.value` (DECIMAL), `exit.stop_loss.type` ('static' / 'adaptive') |
| 3 | **Take profit** | `pnl_pct >= tp`. | `exit.take_profit` (DECIMAL) |
| 4 | **Trailing stop** | **NIFTY/BANKNIFTY/SENSEX:** Gamma-aware + MFE: `Orders::Analyzer` / `Orders::MfeExitEngine`; exit when LTP <= recommended SL. **Other:** Adaptive (activation profit, drawdown schedule) or fixed drop from HWM. | `exit.trailing.enabled`, `exit.trailing.type`, `exit.trailing.activation_profit`, `exit.trailing.drop_threshold` |
| 5 | **Time-based exit** | Current time >= configured exit time. | `exit.time_based.enabled`, `exit.time_based.exit_time` |

All percentages in config are **DECIMAL** (e.g. 0.10 = 10%). PnL snapshot comes from `Live::RedisPnlCache.instance.fetch_pnl(tracker.id)`.

### Path B: 5-Second Enforcement Loop — RiskManagerService

`RiskManagerService#run_enforcement_cycle` runs every 5 seconds. Before the cycle: if **circuit breaker is tripped**, all positions are force-closed and the cycle is skipped.

For each active tracker (skipping if exit already requested/sent), **order of enforcement (first trigger exits and skips rest for that tracker):**

| # | Enforcement | Purpose | Config / Notes |
|---|-------------|---------|-----------------|
| 1 | **advance_trade_state_for** | Updates `trade_state` (init → validated → expansion). | Internal state machine |
| 2 | **enforce_premium_r_stop_for** | Exit if LTP <= `tracker.meta['premium_stop_price']` (rupee stop from entry). | Set at entry in tracker meta |
| 3 | **enforce_dynamic_trailing_stops_for** | Only if `trade_state == 'expansion'` or `be_set?`. Uses `Live::TrailingEngine.process_tick`. | TrailingEngine config, profit_floor |
| 4 | **enforce_profit_floor_for** | Arm floor when net PnL >= lock threshold; ratchet with HWM; exit if net PnL <= floor or time-kill after N minutes. | `risk.profit_floor`: `enabled`, `lock_pct`, `trail_pct`, `breakeven_at`, `time_kill_minutes` |
| 5 | **enforce_structure_invalidation_for** | `Risk::Rules::StructureInvalidationRule`: exit when trade thesis (structure) is broken. | `risk.exits.structure_invalidation.enabled` (default true) |
| 6 | **enforce_premium_momentum_failure_for** | `Risk::Rules::PremiumMomentumFailureRule`: exit when premium momentum fails. | `risk.exits.premium_momentum_failure.enabled` (default true) |
| 7 | **enforce_rr_profit_booking_for** | Exit when current R (PnL% / SL%) >= target R. | `risk.rr_profit_booking.enabled`, `risk.rr_profit_booking.target_rr` |
| 8 | **enforce_percentage_pnl_exit_for** | `Risk::Rules::PercentagePnlRule`: exit at target % PnL. Uses DECIMAL target directly. | `risk.percentage_pnl_exit.enabled`, `risk.percentage_pnl_exit.target_pct` |
| 9 | **enforce_time_stop_for** | `Risk::Rules::TimeStopRule`: max hold time. | `risk.exits.time_stop.enabled` |
| 10 | **enforce_time_based_exit_for** | Exit at configured time (default 15:20) if before market close; optional min profit gate. | `risk.time_exit_hhmm`, `risk.market_close_hhmm`, `risk.min_profit_rupees` |

### Exit Config Sources

- **UnifiedExitChecker** builds config from `AlgoConfig.fetch` → `risk` and `exit` sections.
- **RiskManagerService** uses `resolved_risk_config` (merge of `position_sizing` and `risk`) and `profit_floor_config` from `risk.profit_floor`.

### Exit Reasons Logged

`early_trend_failure`, `stop_loss`, `take_profit`, `trailing_stop`, `time_based`, `premium_r_stop`, `profit_floor_lock`, `profit_floor_time_kill`, `structure_invalidation`, `premium_momentum_failure`, `rr_profit_booking`, `percentage_pnl_exit`, `time_stop`, `stall_detection`.

---

## Summary Tables

### Entry Guards (Pipeline Order)

| Order | Guard | Blocks when |
|-------|--------|-------------|
| 1 | DrawdownGuard | Portfolio drawdown limit hit |
| 2 | EntryPolicyGuard | Policy disallows entry |
| 3 | CircuitBreakerGuard | Circuit breaker tripped |
| 4 | MiddayQualityGuard | Quality gate fails (bypassed if ADX >= 28) |
| 5 | EdgeFailureGuard | Edge failure pause for index |
| 6 | LossStreakGuard | Consecutive losses >= threshold |
| 7 | DailyLimitsGuard | Daily loss/profit/trade limits hit |
| 8 | MaxConcurrentGuard | Max concurrent positions reached |
| 9 | InstrumentLookupGuard | Instrument not found for index |
| 10 | LtpResolutionGuard | Invalid or missing LTP |
| 11 | ExpiryWeekPowerTrendGuard | **Never blocks** — enriches context |
| 12 | TimeRegimeGuard | Time regime disallows entries |
| 13 | BankniftyLastWeekGuard | BANKNIFTY and not last week before monthly expiry |
| 14 | WeeklyExpiryGuard | Not a weekly contract |
| 15 | BosStructureGuard | BOS contract requirement not met |
| 16 | ExposureGuard | Max same-side positions or Supertrend duplicate |
| 17 | CooldownGuard | Re-entry cooldown active for symbol |
| 18 | SizingGuard | Sizing requirements not met |
| 19 | RiskPolicyGuard | Risk policy blocks entry |
| 20 | SmcNavigatorGuard | SMC alignment not satisfied |

### Exit Rules (UnifiedExitChecker — Per-Tick)

| Order | Rule | Trigger |
|-------|------|---------|
| 1 | Early trend failure | Enabled, profit < threshold, trend failure |
| 2 | Stop loss | pnl_pct <= -SL (static or adaptive) |
| 3 | Take profit | pnl_pct >= TP |
| 4 | Trailing stop | Gamma/MFE or adaptive/fixed trailing hit |
| 5 | Time-based | Time >= exit_time |

### Exit Rules (5s Loop — Per Tracker)

| Order | Rule | Trigger |
|-------|------|---------|
| 1 | Premium R-stop | LTP <= premium_stop_price |
| 2 | Dynamic trailing | TrailingEngine triggers exit |
| 3 | Profit floor | Net PnL <= floor or time-kill |
| 4 | Structure invalidation | Rule says exit |
| 5 | Premium momentum failure | Rule says exit |
| 6 | R:R profit booking | Current R >= target R |
| 7 | Percentage PnL exit | Target % PnL reached |
| 8 | Time stop | Max hold time exceeded |
| 9 | Time-based exit | Time >= time_exit_hhmm |

---

## Entry Blockers Analysis

### Signal-Level Blockers (Before EntryGuard)

| Blocker | When it blocks | Tight? |
|--------|-----------------|--------|
| Market closed | After 3:30 PM IST | No — intended |
| Instrument missing | Index instrument not in DB/cache | No — data dependency |
| Supertrend :none | No trend direction | Maybe — single-TF flip only |
| Index TA filter | `enable_index_ta_filter: true` and neutral/low confidence | Yes — off by default |
| Comprehensive validation | IV rank, theta risk, ADX strength, trend confirm | Yes — can be strict |
| EntryFilterEngine | Structure/liquidity/volatility alignment | Yes — institutional filter |
| PermissionResolver | SMC/AVRZ permission returns `:blocked` | Yes — SMC gating blocks many setups |
| SMC decision alignment | SMC call/put/no_trade not aligned | Yes — double gate |
| ExpiryModel | Midday decay period on expiry day | Maybe |
| No strikes qualified | `ChainAnalyzer` returns empty picks | Yes — premium band can be strict |

### Guard-Level Blockers

| # | Blocker | Config / default | Tight? |
|---|---------|------------------|--------|
| 3 | Circuit breaker | API / Redis | No — safety |
| 4 | Midday quality | `midday_guard.min_adx: 20`, `trending_adx_bypass: 28` | Moderate |
| 5 | Edge failure | Rolling -₹3k or 2 consecutive SLs → 60 min pause | Yes |
| 6 | Loss streak | `consecutive_losses_threshold: 2` | Yes — 2 SLs = block |
| 7 | Daily limits | Per-index `trade_limits` | Yes |
| 12 | Time regime | S3 chop_decay (11:30-13:45) `allow_entries: false` | Yes — 2h lunch block |
| 13 | BANKNIFTY last week | Only 7 days per month | Yes |
| 16 | Exposure | `max_same_side: 1` default | Yes — no pyramiding |
| 17 | Cooldown | `cooldown_sec` per index | Yes |

### Quick Relaxation Checklist

- **More trades per day:** Lower cooldown, raise daily limits per index in `algo.yml`
- **More entries in lunch:** `exit_testing` profile or set `chop_decay.allow_entries: true`
- **Less SMC gating:** Set `signals.enable_smc_avrz_permission: false` and/or `enable_smc_decision_alignment: false`
- **Softer validation:** Use `validation_mode: balanced` or lower ADX thresholds
- **More strikes:** Widen `indices[].premium_band` or relax `chain_analyzer` scoring
- **BANKNIFTY all month:** Bypass `BankniftyLastWeekGuard`
- **Fewer edge-failure pauses:** Increase `edge_failure_detector.max_consecutive_sls`, or disable

---

## Related Files

- **Entry:** `app/services/entries/entry_guard_pipeline.rb`, `app/services/entries/entry_guard.rb`, `app/services/entries/guards/*.rb`
- **Exit (per-tick):** `app/services/live/unified_exit_checker.rb`
- **Exit (5s loop):** `app/services/live/risk_manager_service/runner.rb`, `exit_enforcement.rb`, `config.rb`
- **Exit execution:** `app/services/live/exit_engine.rb`
- **Risk rules:** `app/services/risk/rules/*.rb`
