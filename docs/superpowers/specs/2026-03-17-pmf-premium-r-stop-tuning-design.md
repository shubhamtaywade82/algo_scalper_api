# PMF & PREMIUM_R_STOP Tuning Design

> **Problem:** PremiumMomentumFailureRule (PMF) caused -₹46,716 across 25 trades on 16 Mar 2026 (20 SENSEX, concentrated in midday/afternoon). PREMIUM_R_STOP caused ~-₹30k across 10 afternoon SENSEX trades. Both rules fire too aggressively in choppy/slow sessions and on SENSEX (higher premium volatility).

**Goal:** Make PMF session+index aware with configurable stall windows, and suppress PREMIUM_R_STOP when trailing is armed.

**Architecture:** Config-driven PMF stall minutes with additive session overrides. R-stop suppression via trailing-armed check in enforcement loop. Shared `SessionDetector` concern for session detection.

---

## Section 1: PMF Session+Index Aware Stall Window

### Current State

- `PremiumMomentumFailureRule` has hardcoded `DEFAULT_STALL_MINUTES = 3`
- No config section exists in `algo.yml` — rule is enabled by default
- No session or index awareness
- Fires on losing positions when LTP hasn't made a new peak within 3 minutes
- Updates `peak_premium` and `peak_premium_at` in tracker meta on new highs
- Invoked from two paths: (1) `UnifiedExitChecker.premium_momentum_failure_hit?` (sub-second, per-tick) and (2) `ExitEnforcement.enforce_premium_momentum_failure_for` (5-second loop). Both instantiate the rule and call `evaluate` — the config-driven change applies to both paths automatically.

### Design

**Config structure** in `config/algo.yml` under `risk.exits.premium_momentum_failure`:

```yaml
risk:
  exits:
    premium_momentum_failure:
      enabled: true
      default_stall_minutes: 3
      index_overrides:
        SENSEX:
          stall_minutes: 4    # SENSEX base: 4 min (vs 3 default)
        # NIFTY and BANKNIFTY use default_stall_minutes (3)
      session_overrides:
        chop_decay:
          stall_minutes_add: 2   # +2 min during 11:30-13:45
        close_gamma:
          stall_minutes_add: 2   # +2 min during 13:45-15:15
        # open_expansion and trend_continuation use base (no additive)
```

**Resulting stall matrix** (base + session additive):

| Index | open_expansion (09:15-09:45) | trend_continuation (09:45-11:30) | chop_decay (11:30-13:45) | close_gamma (13:45-15:15) |
|---|---|---|---|---|
| NIFTY | 3 min | 3 min | 5 min | 5 min |
| SENSEX | 4 min | 4 min | 6 min | 6 min |
| BANKNIFTY | 3 min | 3 min | 5 min | 5 min |

Formula: `stall_minutes = (index_override.stall_minutes || default_stall_minutes) + (session_override.stall_minutes_add || 0)`

Config is read via `AlgoConfig.fetch.dig(:risk, :exits, :premium_momentum_failure)` directly (not via `resolved_risk_config`), since the keys live under `risk.exits`.

### Shared SessionDetector Concern

**File:** `app/services/concerns/session_detector.rb` (NEW)

Extract the `detect_current_session` logic (currently duplicated in `Signal::EntryQualityFilter`) into a shared concern. Both `EntryQualityFilter` and `PremiumMomentumFailureRule` include it.

```ruby
module Concerns
  module SessionDetector
    def detect_current_session
      time_regimes = AlgoConfig.fetch.dig(:risk, :time_regimes)
      return nil unless time_regimes.is_a?(Hash)

      now = Time.current.in_time_zone('Asia/Kolkata')
      current_hhmm = now.strftime('%H:%M')

      time_regimes.each do |name, cfg|
        next unless cfg.is_a?(Hash)
        start_time = cfg[:start] || cfg['start']
        end_time = cfg[:end] || cfg['end']
        next unless start_time && end_time
        return name.to_sym if current_hhmm >= start_time.to_s && current_hhmm < end_time.to_s
      end

      nil
    end
  end
end
```

`EntryQualityFilter` switches from its private `detect_current_session` to `include Concerns::SessionDetector`.

### Changes to PremiumMomentumFailureRule

**File:** `app/services/risk/rules/premium_momentum_failure_rule.rb`

1. `include Concerns::SessionDetector`
2. Replace `DEFAULT_STALL_MINUTES = 3` usage with `resolve_stall_minutes(tracker)`
3. Add private method `resolve_stall_minutes(tracker)`:
   - Read config via `AlgoConfig.fetch.dig(:risk, :exits, :premium_momentum_failure) || {}`
   - Extract index key: `tracker.meta&.dig('index_key')` — if nil, use `default_stall_minutes`
   - Get base: `config.dig(:index_overrides, index_key.to_sym, :stall_minutes) || config[:default_stall_minutes] || 3`
   - Detect current session via `detect_current_session`
   - Add: `config.dig(:session_overrides, session, :stall_minutes_add) || 0` if session present
   - Return final integer

### Config Changes

**File:** `config/algo.yml` — add `premium_momentum_failure` section under `risk.exits`

**File:** `config/profiles/exit_testing.yml` — mirror with shorter values for testing

---

## Section 2: PREMIUM_R_STOP Suppression When Trailing Armed

### Current State

- `enforce_premium_r_stop_for` in ExitEnforcement fires when `ltp <= premium_stop_price`
- `premium_stop_price` is set once at entry: `entry_price - (entry_price × sl_pct)`
- Static — never adjusts after entry
- Priority 1 in enforcement loop (fires before trailing stops)
- Report shows it exits positions that had reached profit and were pulling back — the trailing system should manage those exits instead
- **Note:** PREMIUM_R_STOP exists ONLY in the 5-second enforcement loop (`ExitEnforcement`). It is NOT checked in `UnifiedExitChecker` (sub-second path). Suppression only needs to be applied in `ExitEnforcement`.

### Design

**Suppression logic:** When trailing is armed (position reached trailing activation profit), skip the PREMIUM_R_STOP check entirely. The trailing system owns exit management.

**"Trailing armed" definition** — uses the generic trailing activation threshold (`risk.trailing.activation_pct`, currently 0.025 after our optimization):
- Trailing enabled in config
- `activation_profit > 0` (trailing has an activation threshold)
- `peak_profit_pct >= activation_profit` (HWM reached trailing threshold)

Where `peak_profit_pct = snapshot[:hwm_pnl] / (tracker.entry_price × tracker.quantity)`

**Config path:** `trailing_armed_for?` reads activation from `AlgoConfig.fetch.dig(:risk, :trailing, :activation_pct)` — the same source as `UnifiedExitChecker.build_exit_config`. This uses the generic activation (0.025), NOT the institutional per-index `activation_trigger` (0.10). Using the lower generic threshold means R-stop is suppressed earlier (at 2.5% profit), which is the desired behavior — once any trailing system could be managing the position, R-stop should step aside.

### Changes to ExitEnforcement

**File:** `app/services/live/risk_manager_service/exit_enforcement.rb`

1. Add `trailing_armed_for?(tracker, snapshot)` private method:
   - Read activation: `AlgoConfig.fetch.dig(:risk, :trailing, :activation_pct) || 0.025`
   - Check trailing enabled: `AlgoConfig.fetch.dig(:risk, :trailing, :enabled) != false`
   - Return false unless both above
   - Compute `entry_value = tracker.entry_price.to_f * tracker.quantity.to_i`
   - Return false unless `entry_value.positive?`
   - Compute `peak_profit_pct = snapshot[:hwm_pnl].to_f / entry_value`
   - Return `peak_profit_pct >= activation`
2. In `enforce_premium_r_stop_for`, add early return after snapshot:
   ```ruby
   return if trailing_armed_for?(tracker, snapshot)
   ```
3. Debug-level log when suppressed for observability

### Edge Cases

- **Trailing disarms (profit drops below activation):** R-stop resumes — correct behavior, the hard stop should protect when trailing is no longer active
- **No HWM data in snapshot:** `trailing_armed_for?` returns false, R-stop fires normally — safe default
- **Entry value zero/nil:** Guard with `entry_value.positive?` check, return false — R-stop fires normally

### No Config Changes

This is a behavioral fix. The R-stop distance itself stays at `sl_pct`. No new config keys needed.

---

## Files Modified

| File | Change |
|---|---|
| `app/services/concerns/session_detector.rb` | **NEW** — shared session detection concern |
| `app/services/risk/rules/premium_momentum_failure_rule.rb` | Config-driven stall minutes with index+session resolution |
| `app/services/signal/entry_quality_filter.rb` | Replace private `detect_current_session` with `include Concerns::SessionDetector` |
| `app/services/live/risk_manager_service/exit_enforcement.rb` | R-stop suppression when trailing armed |
| `config/algo.yml` | PMF config section |
| `config/profiles/exit_testing.yml` | PMF test config |
| `spec/services/risk/rules/premium_momentum_failure_rule_spec.rb` | Tests for session+index stall resolution |
| `spec/services/live/risk_manager_service/exit_enforcement_spec.rb` | Tests for R-stop suppression |
| `spec/services/concerns/session_detector_spec.rb` | Tests for shared session detection |

## Rollback Strategy

- **PMF:** Set `risk.exits.premium_momentum_failure.enabled: false` in DB settings to disable entirely, or remove `session_overrides` / `index_overrides` to revert to 3-minute default
- **R-stop suppression:** The `trailing_armed_for?` check is self-contained — removing it restores original behavior. No config dependency.

## Expected Impact

Based on 16 Mar 2026 data:
- **PMF:** 25 trades with -₹46,716 → expect ~60% reduction in midday/afternoon PMF exits (trades that would have recovered within the extended window)
- **R-stop:** 10 afternoon trades with ~-₹30k → expect near-elimination of R-stop exits on positions where trailing was active (these should be managed by trailing instead)
- **Net:** Estimated +₹40-50k improvement on a similar trading day
