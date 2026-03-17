# Options Profit Optimization Design Spec

**Date:** 2026-03-16
**Scope:** NIFTY and SENSEX options buying — entries and exits
**Modes:** Both production (`algo.yml`) and exit testing (`exit_testing.yml`)

## Problem Statement

Analysis of today's 101 positions reveals systemic issues killing options buying profitability:

1. **Structure invalidation bug** — sub-second path bypasses `enabled: false` config, causing 90% of exits to fire as STRUCTURE_INVALIDATION within 6 seconds of entry
2. **Loose SL/TP** — existing `risk.sl_pct: 0.12` (12%) is too loose for options; `risk.tp_pct: 0.50` (50%) is unrealistic for scalps (winners peak at 8-15%)
3. **No adaptive trailing** — existing 40-tier `position_sizing.trailing_tiers` and 3-phase `institutional_trailing` don't adapt drawdown tolerance to momentum; winners give back gains, runners get stopped out on normal pullbacks
4. **Excessive trade frequency** — 101 trades/day means rapid-fire low-quality entries bleeding bid-ask spread and theta
5. **Weak entry filters** — ADX 20 and min_score 40 allow entries in weak trends where options decay without follow-through
6. **No session awareness in entry quality** — entries in chop_decay session (11:30-13:45) bleed premium despite `allow_entries: false` in time_regimes (which is checked elsewhere)

## Existing Systems Reference

### Current Exit Check Order (`unified_exit_checker.rb`)

1. Early Trend Failure (ETF) → `early_exit_triggered?`
2. Stop Loss → `loss_limit_hit?` (reads `risk.sl_pct`)
3. Emergency Peak Loss → `emergency_peak_loss_exit_triggered?`
4. Take Profit → `profit_target_hit?` (reads `risk.tp_pct` and `risk.percentage_pnl_exit`)
5. Premium Momentum Failure → `premium_momentum_failure_hit?`
6. Trailing Stop → `trailing_stop_hit?`
7. Structure Invalidation → `structure_invalidated?`
8. Time-Based Exit → `time_based_exit?`

### Current Config Paths

| Setting | Path | Current Value |
|---------|------|---------------|
| Stop Loss | `risk.sl_pct` | 0.12 (12%) |
| Take Profit | `risk.tp_pct` | 0.50 (50%) |
| Percentage PnL Exit | `risk.percentage_pnl_exit.target_pct` | 0.30 (30%) |
| Trailing Tiers | `position_sizing.trailing_tiers` | 40 tiers (trigger_pct/sl_offset_pct pairs) |
| Institutional Trailing | `risk.institutional_trailing` | 3-phase per-index (early/breakeven/activation) |
| Structure Invalidation | `risk.exits.structure_invalidation` | enabled: false, min_hold: 120s, buffer: 0.004 |
| Cooldown | `indices[N].cooldown_sec` | 180 (per-symbol, not per-index) |
| Session Boundaries | `risk.time_regimes.chop_decay` | 11:30 - 13:45 IST |

### Existing Trailing Systems

1. **`position_sizing.trailing_tiers`** — 40-tier SL offset table (trigger_pct → sl_offset_pct). Parsed by `Positions::TrailingConfig.parse_tiers()`.
2. **`risk.institutional_trailing`** — 3-phase system (early_trigger → breakeven → HWM trailing). Per-index config with session-aware afternoon tightening.
3. **Gamma-aware/MFE trailing** — in `unified_exit_checker.rb` lines 176-218, handles NIFTY/BANKNIFTY/SENSEX specifically.
4. **Peak drawdown** — in `Positions::TrailingConfig`, tiered thresholds based on profit level.

### Existing Peak Premium Tracking

`Risk::Rules::PremiumMomentumFailureRule` already tracks `peak_premium` and `peak_premium_at` in `tracker.meta` (lines 50-53). Updates on each evaluation when current LTP exceeds stored peak. The structure invalidation redesign will reuse this same `peak_premium` meta key.

---

## Design

### Section 1: Structure Invalidation Fix & Redesign

#### Bug Fix

The sub-second structure invalidation check in `unified_exit_checker.rb` (lines 86-96) never checks the `risk.exits.structure_invalidation.enabled` config flag. The 5-second interval path in `exit_enforcement.rb` (lines 369-404) correctly checks via `structure_invalidation_enabled?`.

**Fix:** Add `structure_invalidation_enabled?` config check to the sub-second path. When `enabled: false`, both paths skip structure invalidation entirely.

#### Options-Aware Redesign

Replace the single underlying-price check with a dual condition:

- **Condition A:** Underlying has moved 1%+ against the trade direction from entry
- **Condition B:** Option premium has dropped 5%+ from peak premium (not from entry — from peak, to avoid triggering on normal retracements)

Both conditions must be true simultaneously to trigger exit. This prevents premature exits from normal option premium fluctuations that don't reflect actual structural breakdown.

**Peak premium tracking:** Reuse the existing `peak_premium` meta key already maintained by `PremiumMomentumFailureRule`. Ensure `entry_guard.rb` sets the initial `peak_premium` value at entry time so it's available immediately (currently `PremiumMomentumFailureRule` only updates it on evaluation, which may lag).

#### Config changes

Update existing `risk.exits.structure_invalidation`:

```yaml
structure_invalidation:
  enabled: true               # re-enable after fix
  min_hold_seconds: 120       # unchanged
  buffer_pct: 0.004           # unchanged (backward compat)
  underlying_move_pct: 0.01   # NEW: 1% underlying move required
  premium_drop_pct: 0.05      # NEW: 5% premium drop from peak required
```

#### Files to modify

- `app/services/live/unified_exit_checker.rb` — add config check to sub-second path, implement dual condition logic
- `app/services/live/risk_manager_service/exit_enforcement.rb` — align 5-second path with new dual condition
- `app/services/entries/entry_guard.rb` — store initial `peak_premium` in tracker meta at entry time

### Section 2: Exit Tuning — SL/TP, Trailing, and TP Suppression

#### Hard Stop-Loss (6%) — tighten existing SL

**Not a new exit check.** Modify the existing `loss_limit_hit?` check (priority #2) by updating its config value:

- Change `risk.sl_pct` from `0.12` → `0.06`
- The existing static SL logic already checks `pnl_pct <= -sl_pct` — no code change needed, just config
- The old 12% SL becomes dead — replaced by the tighter 6%

#### Take Profit (12%) with Trailing Suppression

**Modify the existing `profit_target_hit?` check (priority #4):**

- Change `risk.tp_pct` from `0.50` → `0.12`
- Add suppression logic: if trailing is **armed** (peak profit has exceeded activation threshold of 2.5%) AND current profit >= TP threshold → suppress TP, let trailing manage the exit
- "Trailing armed" means the trailing system has been activated (profit crossed `activation_pct`), not that the trailing stop has been hit. This is checked via `tracker.meta['trailing_active']` or equivalent state.

#### Percentage Exit (15%)

- Update `risk.percentage_pnl_exit.target_pct` from `0.30` → `0.15`
- Acts as safety net when trailing is not active

#### Adaptive Trailing Drawdown — extending institutional trailing

**Do not replace existing trailing systems.** Instead, modify the institutional trailing config to implement the 4-tier adaptive drawdown:

The existing `risk.institutional_trailing` already has per-index 3-phase trailing. We extend it by replacing the flat `trailing_distance` with a tiered drawdown that adapts to profit level:

```yaml
risk:
  institutional_trailing:
    enabled: true
    session_aware: true
    expiry_day_tightening: 0.60
    nifty:
      early_trigger: 0.025        # was 0.03 — activate trailing earlier
      early_sl_offset: -0.06      # was -0.12 — tighter to match new hard SL
      breakeven_trigger: 0.05     # was 0.08 — move to breakeven sooner
      activation_trigger: 0.10    # was 0.15 — full trailing kicks in sooner
      trailing_distance: 0.018    # base trailing distance (tier 1)
      adaptive_drawdown:          # NEW: tiered drawdown overrides
        - { min_profit: 0.025, drawdown: 0.018 }  # 2.5-10%: tight
        - { min_profit: 0.10, drawdown: 0.022 }   # 10-20%: moderate
        - { min_profit: 0.20, drawdown: 0.025 }   # 20-35%: wider
        - { min_profit: 0.35, drawdown: 0.030 }   # 35%+: widest
    sensex:
      early_trigger: 0.025
      early_sl_offset: -0.06
      breakeven_trigger: 0.05
      activation_trigger: 0.10
      trailing_distance: 0.018
      adaptive_drawdown:
        - { min_profit: 0.025, drawdown: 0.018 }
        - { min_profit: 0.10, drawdown: 0.022 }
        - { min_profit: 0.20, drawdown: 0.025 }
        - { min_profit: 0.35, drawdown: 0.030 }
```

The existing `position_sizing.trailing_tiers` (40-tier SL offset table) and gamma-aware trailing remain unchanged — they serve different purposes (SL offset from entry vs drawdown from peak). The adaptive drawdown tiers control how far price can pull back from peak before trailing triggers exit.

**Drawdown tier selection:** Based on **peak profit** (not current profit). Once peak profit crosses a tier boundary, the allowed drawdown widens. It never tightens back — this prevents getting stopped out of a runner during a normal pullback.

#### Updated Exit Priority Order

The check order in `unified_exit_checker.rb` remains the same. Only the behavior within existing checks changes:

1. Early Trend Failure (ETF) — **unchanged**
2. Stop Loss → `loss_limit_hit?` — **config change:** `risk.sl_pct: 0.06` (was 0.12)
3. Emergency Peak Loss — **unchanged**
4. Take Profit → `profit_target_hit?` — **config change:** `risk.tp_pct: 0.12` (was 0.50), **code change:** add trailing suppression
5. Premium Momentum Failure — **unchanged**
6. Trailing Stop → `trailing_stop_hit?` — **code change:** use adaptive drawdown tiers from institutional trailing config
7. Structure Invalidation — **code change:** dual condition (Section 1)
8. Time-Based Exit — **unchanged**

No new exit checks are added. No reordering needed.

#### Files to modify

- `app/services/live/unified_exit_checker.rb` — TP suppression logic in `profit_target_hit?`, adaptive drawdown in `trailing_stop_hit?`
- `app/services/positions/trailing_config.rb` — parse `adaptive_drawdown` tiers, select drawdown based on peak profit
- `config/algo.yml` — update `risk.sl_pct`, `risk.tp_pct`, `risk.percentage_pnl_exit.target_pct`, `risk.institutional_trailing` with adaptive_drawdown
- `config/profiles/exit_testing.yml` — matching values for test profile

### Section 3: Entry Strengthening — Session Filtering, ADX, Quality Score, Trade Frequency

#### Session-Aware Entry Rules

Chop decay session (11:30-13:45 IST, matching existing `risk.time_regimes.chop_decay` boundaries) entries require elevated thresholds:

- `min_score: 60` (vs 55 default)
- `min_adx: 30` (vs 25 default)

**Session detection mechanism:** `EntryQualityFilter.evaluate` reads the `risk.time_regimes` config from `AlgoConfig.fetch` and checks `Time.current.in_time_zone('Asia/Kolkata')` against session boundaries. If current time falls within `chop_decay` start/end, apply the session override. All other sessions use standard thresholds.

Config:
```yaml
entry_quality:
  session_overrides:
    chop_decay:              # matches time_regimes key name
      min_score: 60
      gates:
        min_adx: 30
```

#### Global ADX Increase

- `entry_quality.gates.min_adx: 25` (up from 20)
- Filters out weak trends where options bleed premium

#### Quality Score Threshold

- `entry_quality.min_score: 55` (up from 40)
- Forces higher conviction across all 5 scoring components

#### Trade Frequency Controls

**Cooldown — change from per-symbol to per-index:**

Currently `cooldown_guard.rb` tracks cooldown per option symbol (`context[:pick][:symbol]`). This means entering NIFTY 24000CE doesn't prevent immediately entering NIFTY 24050CE. For options buying, we want per-index cooldown — entering any NIFTY option starts the 180s cooldown for all NIFTY entries.

- Modify `cooldown_guard.rb` to use `context[:index_cfg][:key]` instead of `context[:pick][:symbol]` for cooldown tracking
- The existing `indices[N].cooldown_sec: 180` config remains the source of truth (already 180s)
- No new config path needed

**Max 2 concurrent positions per index:**

- Create new guard: `app/services/entries/guards/max_concurrent_guard.rb`
- Query `PositionTracker.where(index_key: index_key, status: 'open').count`
- If count >= config threshold, reject with reason `max_concurrent_positions`
- Insert in pipeline after `DailyLimitsGuard` and before `InstrumentLookupGuard`
- Config: add `max_concurrent_per_index: 2` to each index config in `indices[N]`

#### Files to modify

- `app/services/signal/entry_quality_filter.rb` — add session detection and chop_decay override logic
- `config/algo.yml` — update min_adx, min_score, add session_overrides, add max_concurrent_per_index to index configs
- `app/services/entries/guards/cooldown_guard.rb` — change from per-symbol to per-index tracking
- `app/services/entries/guards/max_concurrent_guard.rb` — **new file**, concurrent position limit guard
- `app/services/entries/entry_guard_pipeline.rb` — register MaxConcurrentGuard in pipeline
- `config/profiles/exit_testing.yml` — matching entry config for test profile

---

## Config Changes Summary

### `config/algo.yml` changes

```yaml
# Entry quality (existing section, update values)
entry_quality:
  enforce: true                    # was false (log-only)
  min_score: 55                    # was 40
  gates:
    min_adx: 25                    # was 20
    # block_choppy_regime, min_body_ratio, require_momentum_confirm unchanged
  session_overrides:               # NEW
    chop_decay:
      min_score: 60
      gates:
        min_adx: 30

# Index configs (existing, add max_concurrent_per_index)
indices:
  - key: NIFTY
    cooldown_sec: 180              # unchanged (already 180)
    max_concurrent_per_index: 2    # NEW
  - key: SENSEX
    cooldown_sec: 180
    max_concurrent_per_index: 2

# Risk section (existing paths, update values)
risk:
  sl_pct: 0.06                    # was 0.12
  tp_pct: 0.12                    # was 0.50
  percentage_pnl_exit:
    enabled: true
    target_pct: 0.15              # was 0.30

  # Institutional trailing (existing, update values + add adaptive_drawdown)
  institutional_trailing:
    enabled: true
    session_aware: true
    expiry_day_tightening: 0.60
    nifty:
      early_trigger: 0.025        # was 0.03
      early_sl_offset: -0.06      # was -0.12
      breakeven_trigger: 0.05     # was 0.08
      activation_trigger: 0.10    # was 0.15
      trailing_distance: 0.018    # was 0.20
      adaptive_drawdown:          # NEW
        - { min_profit: 0.025, drawdown: 0.018 }
        - { min_profit: 0.10, drawdown: 0.022 }
        - { min_profit: 0.20, drawdown: 0.025 }
        - { min_profit: 0.35, drawdown: 0.030 }
    sensex:
      early_trigger: 0.025
      early_sl_offset: -0.06
      breakeven_trigger: 0.05
      activation_trigger: 0.10
      trailing_distance: 0.018
      adaptive_drawdown:
        - { min_profit: 0.025, drawdown: 0.018 }
        - { min_profit: 0.10, drawdown: 0.022 }
        - { min_profit: 0.20, drawdown: 0.025 }
        - { min_profit: 0.35, drawdown: 0.030 }

  # Structure invalidation (existing path, update values)
  exits:
    structure_invalidation:
      enabled: true                # was false — re-enable after bug fix
      min_hold_seconds: 120        # unchanged
      buffer_pct: 0.004            # unchanged
      underlying_move_pct: 0.01    # NEW: 1% underlying move required
      premium_drop_pct: 0.05       # NEW: 5% premium drop from peak required
```

### `config/profiles/exit_testing.yml` changes

Mirror the above with:
- `entry_quality.enforce: false` for log-only mode
- All other values identical to production

### Superseded config values

| Old Path | Old Value | New Value | Status |
|----------|-----------|-----------|--------|
| `risk.sl_pct` | 0.12 | 0.06 | Tightened |
| `risk.tp_pct` | 0.50 | 0.12 | Tightened |
| `risk.percentage_pnl_exit.target_pct` | 0.30 | 0.15 | Tightened |
| `risk.institutional_trailing.nifty.trailing_distance` | 0.20 | 0.018 | Replaced by adaptive tiers |
| `risk.exits.structure_invalidation.enabled` | false | true | Re-enabled with dual condition |

The existing `position_sizing.trailing_tiers` (40-tier SL offset table) is **not modified** — it serves a different purpose (SL offset from entry price) and continues to function alongside the adaptive drawdown (pullback from peak).

---

## Rollback Strategy

Each section can be independently reverted via config:

| Section | Rollback |
|---------|----------|
| Structure invalidation | Set `risk.exits.structure_invalidation.enabled: false` |
| SL/TP | Revert `risk.sl_pct`, `risk.tp_pct`, `risk.percentage_pnl_exit.target_pct` to old values |
| Adaptive trailing | Remove `adaptive_drawdown` from institutional trailing config; code falls back to flat `trailing_distance` |
| Session overrides | Remove `entry_quality.session_overrides` section |
| Entry thresholds | Revert `entry_quality.min_score` to 40, `gates.min_adx` to 20 |
| Cooldown per-index | Revert `cooldown_guard.rb` to use `context[:pick][:symbol]` |
| Max concurrent | Remove `MaxConcurrentGuard` from pipeline |

## Testing Strategy

- Unit tests for each modified service (structure invalidation dual condition, TP suppression, adaptive drawdown tier selection, session detection, per-index cooldown, max concurrent guard)
- Integration tests verifying exit check behavior with new config values
- Config validation tests ensuring decimal format consistency
- Existing spec suite must pass with 0 regressions
