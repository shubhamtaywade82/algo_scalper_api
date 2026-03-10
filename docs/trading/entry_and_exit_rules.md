# Entry and Exit Rules

Canonical reference for entry guards and exit rules as implemented in the codebase.  
**Implementation:** `app/services/entries/entry_guard_pipeline.rb`, `app/services/entries/entry_guard.rb`, `app/services/live/unified_exit_checker.rb`, `app/services/live/risk_manager_service/runner.rb`, `app/services/live/risk_manager_service/exit_enforcement.rb`.

---

## Entry Rules

Entry requests are validated by a **guard pipeline** (first block wins). After the pipeline passes, additional **post-pipeline checks** run before order placement.

### Entry Guard Pipeline (Order)

Run by `Entries::EntryGuardPipeline#run`. Each guard returns `PASS` or `{ blocked: reason }`. Order:

| # | Guard | Class | Purpose |
|---|-------|--------|---------|
| 1 | **Circuit breaker** | `Guards::CircuitBreakerGuard` | Block if `Risk::CircuitBreaker.instance.tripped?`. Reason includes trip reason and timestamp. |
| 2 | **BOS contract** | `Guards::BosContractGuard` | Block if `entry_metadata` does not satisfy BOS contract (Break-of-Structure). Pass if `EntryGuard.bos_contract_present?(entry_metadata)`. |
| 3 | **Time regime** | `Guards::TimeRegimeGuard` | Block if current time regime for the index does not allow entries. Uses `Live::TimeRegimeService` and `allow_entries` per regime in `config/algo.yml` (`risk.time_regimes`). |
| 4 | **BANKNIFTY last week** | `Guards::BankniftyLastWeekGuard` | Only for index key `BANKNIFTY`: block unless `EntryGuard.banknifty_last_week?` (entry allowed only in last week before monthly expiry). |
| 5 | **Edge failure** | `Guards::EdgeFailureGuard` | Block if `Live::EdgeFailureDetector.instance.entries_paused?(index_key:)` is true (e.g. repeated stop outs for that index). Reason includes resume time. |
| 6 | **Daily limits** | `Guards::DailyLimitsGuard` | Block if daily loss/profit/trade limits for the index are exceeded. Uses `EntryGuard.daily_limits_allow_entry?(index_cfg:)`. |
| 7 | **Instrument lookup** | `Guards::InstrumentLookupGuard` | Block if instrument cannot be resolved for the index. Sets `context[:instrument]` for later guards. |
| 8 | **Exposure** | `Guards::ExposureGuard` | Block if exposure limit would be exceeded. For Supertrend contract: block if an active Supertrend position already exists for the index. Otherwise uses `EntryGuard.exposure_ok?(instrument:, side:, max_same_side:)` (same side count vs `index_cfg[:max_same_side]`). Sets `context[:side]`, `context[:is_supertrend]`. |
| 9 | **Cooldown** | `Guards::CooldownGuard` | Block if re-entry cooldown is active for the pick symbol. Uses `index_cfg[:cooldown_sec]` and `EntryGuard.cooldown_active?(symbol, cooldown)`. |
| 10 | **LTP resolution** | `Guards::LtpResolutionGuard` | Block if LTP for the pick is missing or invalid. Resolves via cache or REST fallback; requires positive LTP. Sets `context[:ltp]`. |

### Post-Pipeline Checks (EntryGuard)

After the pipeline passes, `EntryGuard.try_enter` runs:

- **BOS / structure gate** — For non-Supertrend entries, `enforce_structure_entry_gate` must pass (BOS level, confirmation, distance). Supertrend contract bypasses with a synthetic BOS context.
- **Cooldown** — Checked again for the pick symbol with `index_cfg[:cooldown_sec]`.
- **Weekly-only (NIFTY/SENSEX)** — For NIFTY/SENSEX (non–Supertrend, non-paper), entry is blocked unless the pick is a weekly contract (`weekly_contract?`). Monthly contracts are blocked.
- **Execution profile** — `Trading::InstrumentExecutionProfile.for(symbol)`: if permission is `:execution_only`, block unless profile allows execution-only.
- **Sizing cap** — `Trading::CapitalAllocator.max_lots(...)` must be > 0; otherwise entry blocked.
- **Quantity** — `Capital::Allocator.qty_for(...)` combined with cap; quantity must be lot-aligned and ≥ 1 lot; otherwise blocked.
- **Order placement** — `Orders.config.gateway.place_market(...)`; on failure or missing order number, entry fails.

### Configuration (Entry)

- **Indices:** `config/algo.yml` → `indices[]` (per-index `cooldown_sec`, `max_same_side`, etc.).
- **Time regimes:** `config/algo.yml` → `risk.time_regimes` (e.g. `open_expansion`, `trend_continuation`, `chop_decay`, `close_gamma`) with `allow_entries`, `min_adx`, `max_tp_rupees`.
- **Circuit breaker:** API `GET/POST/DELETE /api/circuit_breaker/trip`; state in Rails.cache/Redis.
- **Daily limits:** From `algo.yml` and `trade_limits` / per-index `trade_limits`.

---

## Exit Rules

Exits are evaluated in **two paths**. The first path is high-frequency (per-tick); the second is a 5-second enforcement loop. Both ultimately call `Live::ExitEngine.execute_exit` for placement (single source of truth).

### Path A: High-Frequency (Per-Tick) — UnifiedExitChecker

Used by `Live::RiskManagerService` via `EventBus.subscribe(:ltp)`. For each LTP update, `UnifiedExitChecker.check_exit_conditions(tracker)` is called. **Priority order (first match wins):**

| # | Rule | Condition | Config (algo.yml) |
|---|------|-----------|-------------------|
| 1 | **Early trend failure** | Enabled and profit &lt; `profit_threshold`; then `Live::EarlyTrendFailure.early_trend_failure?(position_data)` (ADX/trend reversal). | `exit.early_exit.enabled`, `exit.early_exit.profit_threshold` (DECIMAL, e.g. 0.07) |
| 2 | **Stop loss** | **Static:** `pnl_pct <= -static_sl`. **Adaptive (when type == 'adaptive' and pnl &lt; 0):** `Positions::DrawdownSchedule.reverse_dynamic_sl_pct(...)` vs current `pnl_pct`. | `risk.sl_pct` or `exit.stop_loss.value` (DECIMAL), `exit.stop_loss.type` ('static' / 'adaptive') |
| 3 | **Take profit** | `pnl_pct >= tp`. | `risk.tp_pct` or `exit.take_profit` (DECIMAL) |
| 4 | **Trailing stop** | **NIFTY/BANKNIFTY/SENSEX:** Gamma-aware + MFE: `Orders::Analyzer` / `Orders::MfeExitEngine`; exit when LTP ≤ recommended SL. **Other:** Adaptive (activation profit, drawdown schedule) or fixed drop from HWM. | `exit.trailing.enabled`, `exit.trailing.type`, `exit.trailing.activation_profit`, `exit.trailing.drop_threshold` |
| 5 | **Time-based exit** | Current time ≥ configured exit time. | `exit.time_based.enabled`, `exit.time_based.exit_time` (e.g. '15:20') |

All percentages in config are **DECIMAL** (e.g. 0.12 = 12%). PnL snapshot comes from `Live::RedisPnlCache.instance.fetch_pnl(tracker.id)`.

### Path B: 5-Second Enforcement Loop — RiskManagerService

`RiskManagerService#run_enforcement_cycle` runs every 5 seconds. For each active tracker (skipping if exit already requested/sent), **order of enforcement (first trigger exits and skips rest for that tracker):**

| # | Enforcement | Purpose | Config / Notes |
|---|-------------|---------|-----------------|
| 1 | **advance_trade_state_for** | Updates `trade_state` (init → validated → expansion) and peak trend score from PnL/risk R. | Internal state |
| 2 | **enforce_premium_r_stop_for** | Exit if LTP ≤ `tracker.meta['premium_stop_price']` (rupee stop from entry). | Set at entry in tracker meta |
| 3 | **enforce_dynamic_trailing_stops_for** | Only if `trade_state == 'expansion'` or `be_set?`. Uses `Live::TrailingEngine.process_tick` with ActiveCache position data. | TrailingEngine config, profit_floor |
| 4 | **enforce_profit_floor_for** | Arm floor when net PnL ≥ lock threshold; ratchet floor with HWM; exit if net PnL ≤ floor (+ exit fee) or time-kill after floor armed for N minutes. | `risk.profit_floor`: `enabled`, `lock_pct`, `trail_pct`, `breakeven_at`, `time_kill_minutes` |
| 5 | **enforce_structure_invalidation_for** | `Risk::Rules::StructureInvalidationRule`: exit when trade thesis (structure) is broken. | `risk.exits.structure_invalidation.enabled` (default true) |
| 6 | **enforce_premium_momentum_failure_for** | `Risk::Rules::PremiumMomentumFailureRule`: exit when premium momentum fails (dead option). | `risk.exits.premium_momentum_failure.enabled` (default true) |
| 7 | **enforce_rr_profit_booking_for** | Exit when current R (PnL% / SL%) ≥ target R. | `risk.rr_profit_booking.enabled`, `risk.rr_profit_booking.target_rr` |
| 8 | **enforce_percentage_pnl_exit_for** | `Risk::Rules::PercentagePnlRule`: exit at target % PnL. | `risk.percentage_pnl_exit.enabled`, `risk.percentage_pnl_exit.target_pct` |
| 9 | **enforce_time_stop_for** | `Risk::Rules::TimeStopRule`: max hold time. | `risk.exits.time_stop.enabled` |
| 10 | **enforce_time_based_exit_for** | Exit at configured time (e.g. 15:20) if before market close; optional min profit. | `risk.time_exit_hhmm`, `risk.market_close_hhmm`, `risk.min_profit_rupees` |

Before the cycle, if **circuit breaker is tripped**, all positions are force-closed via `Risk::CircuitBreaker.instance.force_close_all!(exit_engine:, reason:)` and the rest of the cycle is skipped.

### Exit Config Sources

- **UnifiedExitChecker** builds config from `AlgoConfig.fetch` → `risk` and `exit` (see `build_exit_config` / `default_exit_config` in `unified_exit_checker.rb`).
- **RiskManagerService** uses `resolved_risk_config` (merge of `position_sizing` and `risk`) and `profit_floor_config` from `risk.profit_floor`. Feature flags for structure invalidation, premium momentum failure, time stop, RR profit booking come from `risk.exits.*` and `risk.rr_profit_booking`.

### Exit Paths (Logging)

Exit reasons and paths logged include: `early_trend_failure`, `stop_loss`, `take_profit`, `trailing_stop`, `time_based`, `premium_r_stop`, `profit_floor_lock`, `profit_floor_time_kill`, `structure_invalidation`, `premium_momentum_failure`, `rr_profit_booking`, `percentage_pnl_exit`, `time_stop`, `stall_detection`.

---

## Summary Tables

### Entry Guards (Pipeline Order)

| Order | Guard | Blocks when |
|-------|--------|-------------|
| 1 | CircuitBreaker | Circuit breaker tripped |
| 2 | BosContract | BOS contract missing in metadata |
| 3 | TimeRegime | Time regime disallows entries |
| 4 | BankniftyLastWeek | BANKNIFTY and not last week before monthly expiry |
| 5 | EdgeFailure | Edge failure pause for index |
| 6 | DailyLimits | Daily loss/profit/trade limits hit |
| 7 | InstrumentLookup | Instrument not found for index |
| 8 | Exposure | Max same-side positions or Supertrend duplicate |
| 9 | Cooldown | Re-entry cooldown active for symbol |
| 10 | LtpResolution | Invalid or missing LTP |

### Exit Rules (UnifiedExitChecker — Per-Tick)

| Order | Rule | Trigger |
|-------|------|---------|
| 1 | Early trend failure | Enabled, profit &lt; threshold, trend failure |
| 2 | Stop loss | pnl_pct ≤ -SL (static or adaptive) |
| 3 | Take profit | pnl_pct ≥ TP |
| 4 | Trailing stop | Gamma/MFE or adaptive/fixed trailing hit |
| 5 | Time-based | Time ≥ exit_time |

### Exit Rules (5s Loop — Per Tracker)

| Order | Rule | Trigger |
|-------|------|---------|
| 1 | Premium R-stop | LTP ≤ premium_stop_price |
| 2 | Dynamic trailing | TrailingEngine triggers exit |
| 3 | Profit floor | Net PnL ≤ floor or time-kill |
| 4 | Structure invalidation | Rule says exit |
| 5 | Premium momentum failure | Rule says exit |
| 6 | R:R profit booking | Current R ≥ target R |
| 7 | Percentage PnL exit | Target % PnL reached |
| 8 | Time stop | Max hold time exceeded |
| 9 | Time-based exit | Time ≥ time_exit_hhmm |

---

## Related Files

- **Entry:** `app/services/entries/entry_guard_pipeline.rb`, `app/services/entries/entry_guard.rb`, `app/services/entries/guards/*.rb`
- **Exit (per-tick):** `app/services/live/unified_exit_checker.rb`
- **Exit (5s loop):** `app/services/live/risk_manager_service.rb`, `app/services/live/risk_manager_service/runner.rb`, `app/services/live/risk_manager_service/exit_enforcement.rb`, `app/services/live/risk_manager_service/config.rb`
- **Exit execution:** `app/services/live/exit_engine.rb`
- **Risk rules:** `app/services/risk/rules/*.rb`
