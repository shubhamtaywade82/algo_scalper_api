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

## Entry Blockers and Tightness

This section lists every condition that can block an entry (signal layer → guard pipeline → post-pipeline) and notes which are likely **tight** and where relaxation might increase trade count.

### Blockers Before EntryGuard (Signal::Engine)

| Blocker | When it blocks | Config / code | Tight? |
|--------|-----------------|---------------|--------|
| Market closed | After 3:30 PM IST | `TradingSession::Service.market_closed?` | No — intended. |
| Instrument missing | Index instrument not in DB/cache | `IndexInstrumentCache` | No — data dependency. |
| Supertrend config missing | `signals.supertrend` absent | `algo.yml` | No. |
| Primary analysis fail | Candle/series or Supertrend fail | — | No. |
| Supertrend :none | No trend direction | — | **Maybe** — single-TF flip only. |
| Index TA filter | `enable_index_ta_filter: true` and (neutral or confidence &lt; min) | `signals.enable_index_ta_filter`, `signals.ta_min_confidence` | **Yes** — default off; enable only if you want fewer trades. |
| Comprehensive validation | IV rank, theta risk, ADX strength, trend confirm | `signals.validation_mode`, ADX thresholds per index | **Yes** — balanced/conservative and per-index ADX (e.g. 15–18) can block often. |
| EntryFilterEngine | Structure/liquidity/volatility alignment | `Entries::EntryFilterEngine` | **Yes** — institutional filter; relax only if you accept weaker structure. |
| PermissionResolver | Returns `:blocked` | SMC/AVRZ permission | **Yes** — SMC gating can block many setups. |
| SMC decision alignment | SMC call/put/no_trade not aligned with signal | `signals.enable_smc_decision_alignment` (default true) | **Yes** — double gate with permission; set false to skip alignment. |
| ExpiryModel | Midday decay period on expiry day | `Strategies::ExpiryModel.trade_allowed?` | **Maybe** — avoids expiry midday; relax to allow. |
| Missing ATR / expected_spot_move | No ATR for strike qualification | — | No — chain needs it. |
| No strikes qualified | `ChainAnalyzer.pick_strikes_with_qualification` empty | Premium band, liquidity, OI, IV in `algo.yml` | **Yes** — premium band and scoring can be very strict. |

### Blockers in Entry Guard Pipeline (Order)

| # | Blocker | When it blocks | Config / default | Tight? |
|---|---------|-----------------|------------------|--------|
| 1 | Circuit breaker | Tripped (manual or auto) | API / Redis | No — safety. |
| 2 | BOS contract | `entry_metadata` fails BOS check | Supertrend path bypasses with synthetic BOS | **Yes** for BOS path — requires valid BOS; use Supertrend-only to avoid. |
| 3 | Time regime | Current regime has `allow_entries: false` | `risk.time_regimes.*.allow_entries`; **chop_decay (11:30–13:45) = false** | **Yes** — no entries for ~2h in lunch; intentional. |
| 4 | BANKNIFTY last week | Not in last 7 days before monthly expiry | — | **Yes** — BANKNIFTY only in last week of month. |
| 5 | Edge failure | Rolling PnL ≤ -₹3k (last 5 trades) or 2 consecutive SLs or S3 + 2 SLs | `risk.edge_failure_detector`; pause 60 min | **Yes** — 2 SLs → 1h pause; rolling -3k → 1h. |
| 6 | Daily limits | Daily profit target hit; or (daily/global loss limit when profit ≥ ₹20k); or **≥ 3 trades today per index** | `risk.daily_limits`, **hard-coded 3 trades/index** in EntryGuard | **Yes** — 3 trades/index is hard cap (algo.yml has 2/1/2 per index but code uses 3). |
| 7 | Instrument lookup | Index instrument not found | — | No. |
| 8 | Exposure | Already 1 position same side (or Supertrend duplicate for index) | `indices[].max_same_side` (default 1) | **Yes** — max_same_side: 1 = no pyramiding. |
| 9 | Cooldown | Same symbol traded within last N seconds | `indices[].cooldown_sec` (default **180**) | **Yes** — 3 min per symbol; reduce for more re-entries. |
| 10 | LTP resolution | No valid LTP for pick | — | No — data. |

### Post-Pipeline Blockers (EntryGuard)

| Blocker | When it blocks | Tight? |
|---------|----------------|--------|
| BOS / structure gate | Non-Supertrend entry fails structure entry gate | **Yes** — BOS level/confirmation/distance. |
| Cooldown (again) | Same symbol within cooldown (duplicate check) | Same as pipeline. |
| Weekly-only (NIFTY/SENSEX) | Pick is monthly contract | **Yes** — only weekly allowed for NIFTY/SENSEX (non-paper). |
| Execution profile | Permission `:execution_only` and profile disallows | Depends on profile. |
| Sizing cap | `max_lots` ≤ 0 | Capital/config. |
| Quantity | Allocator or cap gives &lt; 1 lot | **Maybe** — risk sizing can cap to 0. |
| Order placement fail | Gateway/API error | No. |

### Summary: Likely “Too Tight” Levers

1. **Time regime** — `chop_decay.allow_entries: false` (11:30–13:45) blocks all entries in lunch.  
2. **Cooldown** — 180 s per symbol; reducing (e.g. 60–120) allows more re-entries on same symbol.  
3. **max_same_side: 1** — Only one position per side per index; increasing allows pyramiding.  
4. **Institutional 3-trades-per-index cap** — Hard-coded in `EntryGuard.daily_limits_allow_entry?`; algo.yml per-index limits (2/1/2) are not used for this check.  
5. **BANKNIFTY last week** — Only 7 days per month for BANKNIFTY; remove guard if you want all month.  
6. **Edge failure** — 2 consecutive SLs or last-5 net ≤ -₹3k → 60 min pause; increase `max_consecutive_sls` or pause duration, or disable.  
7. **SMC + Permission** — PermissionResolver + SMC alignment (both on by default) block when SMC is neutral or misaligned; set `enable_smc_avrz_permission` / `enable_smc_decision_alignment` false to relax.  
8. **Comprehensive validation** — ADX/IV/theta checks; use less strict validation_mode or lower per-index ADX.  
9. **EntryFilterEngine** — Structure/liquidity/volatility; relax only if you accept weaker setups.  
10. **Strike qualification** — Premium band (min/max), liquidity, OI; widen band or relax scoring to get more strikes.  
11. **Weekly-only NIFTY/SENSEX** — Code blocks monthly contracts; bypass only with Supertrend or paper.  
12. **BOS contract** — Required for non-Supertrend; use Supertrend-only mode to avoid BOS requirement.

### Quick Relaxation Checklist

- **More trades per day:** Lower cooldown (e.g. 60–120 s), raise or remove the 3-trades-per-index cap (make it configurable from algo.yml).  
- **More entries in lunch:** Set `chop_decay.allow_entries: true` (and optionally higher `min_adx`).  
- **Less SMC gating:** Set `signals.enable_smc_avrz_permission: false` and/or `signals.enable_smc_decision_alignment: false`.  
- **Softer validation:** Use `validation_mode: balanced` or lower ADX thresholds in indices.  
- **More strikes:** Widen `indices[].premium_band` or relax chain_analyzer scoring.  
- **BANKNIFTY all month:** Remove or bypass `BankniftyLastWeekGuard`.  
- **Fewer edge-failure pauses:** Increase `edge_failure_detector.max_consecutive_sls` or `rolling_window_threshold_rupees`, or disable.

---

## Related Files

- **Entry:** `app/services/entries/entry_guard_pipeline.rb`, `app/services/entries/entry_guard.rb`, `app/services/entries/guards/*.rb`
- **Exit (per-tick):** `app/services/live/unified_exit_checker.rb`
- **Exit (5s loop):** `app/services/live/risk_manager_service.rb`, `app/services/live/risk_manager_service/runner.rb`, `app/services/live/risk_manager_service/exit_enforcement.rb`, `app/services/live/risk_manager_service/config.rb`
- **Exit execution:** `app/services/live/exit_engine.rb`
- **Risk rules:** `app/services/risk/rules/*.rb`
