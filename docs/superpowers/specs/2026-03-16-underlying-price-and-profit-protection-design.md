# Fix Underlying Price Propagation & Profit Protection

**Date:** 2026-03-16
**Approach:** Surgical Fix (Approach A)
**Branch:** `fix/logging-and-job-run-improvements`

## Context

Analysis of 612 positions from the last week (Mar 9-14) revealed two critical bugs:

1. **`entry_underlying_price` not propagated** — Supertrend path never stores the underlying index price. BOS path stores it but mixes underlying and option premium domains when calculating `initial_sl_pct`, `premium_stop_price`, and `entry_risk_rupees`. Result: `initial_sl_pct` values like 13174% instead of 12%, negative `premium_stop_price`, and no underlying reference for structure-based exits.

2. **Profit protection fails on fast moves** — Two compounding issues: (a) `TrailingEngine.check_peak_drawdown` runs only every 5 seconds in the enforcement loop, so fast crashes between cycles are missed; the sub-second path (`UnifiedExitChecker`) has no peak drawdown logic. (b) When the activation gate IS enabled (`enable_peak_drawdown_activation: true`), it requires both peak profit AND SL offset to meet thresholds (AND logic), blocking protection when the tiered SL hasn't ratcheted up on fast rallies. 250 positions reached ₹2k-₹4.6k HWM profit then closed in loss.

Additionally, `UnderlyingExitRule` and `UnderlyingMonitor` are fully built but disabled. Enabling them provides structure-break and trend-weakness exits using the underlying index price.

## Changes

### 1. Fix Underlying Price Propagation

#### 1a. Signal::Engine — Pass underlying price in Supertrend entry_metadata

**File:** `app/services/signal/engine.rb` (~line 504)

Add `entry_underlying_price` to the supertrend `entry_metadata.merge!` block:

```ruby
entry_metadata.merge!(
  bos_id: "st_#{index_cfg[:key]}_#{Time.current.to_i}",
  bos_timeframe: primary_tf,
  bos_origin_price: primary_series.candles.last&.close,
  bos_level: primary_series.candles.last&.close,
  entry_underlying_price: primary_series.candles.last&.close  # INDEX close price
)
```

`primary_series` is the index candle series (not the option), so `.candles.last&.close` is the underlying index LTP (e.g., 23838 for NIFTY).

#### 1b. EntryGuard.apply_bos_metadata! — Fix domain separation

**File:** `app/services/entries/entry_guard.rb` (lines 888-934)

**Principle:** `premium_stop_price`, `premium_target_price`, `initial_sl_pct` stay in option premium domain. `structure_invalidation_price` stays in underlying domain.

**BOS path fix (lines 899-905):**

Before (broken — mixes domains):
```ruby
origin_price = bos_context[:origin_swing][:price].to_f
entry_underlying_price = bos_context[:entry_underlying_price]
reference_price = entry_underlying_price || entry_price
entry_risk_rupees = (reference_price.to_f - origin_price).abs * quantity.to_i
premium_r = entry_risk_rupees / quantity.to_f
```

After (fixed — consistent premium domain for stops):
```ruby
origin_price = bos_context[:origin_swing][:price].to_f
entry_underlying_price = bos_context[:entry_underlying_price]
# Premium-domain risk: use configured SL% (same as Supertrend path)
sl_decimal = supertrend_sl_decimal
premium_r = entry_price.to_f * sl_decimal
entry_risk_rupees = premium_r * quantity.to_i
```

This ensures `premium_stop_price = entry_price - (entry_price * 0.12)` (correct option domain) for both paths.

`structure_invalidation_price` continues to store the BOS origin level in the underlying index domain (line 909, unchanged).

#### 1c. Always store underlying price in meta

**File:** `app/services/entries/entry_guard.rb` (line 915)

Before:
```ruby
meta_hash[:entry_underlying_price] = entry_underlying_price if entry_underlying_price
```

After — add TickQuery fallback so it's never nil:
```ruby
meta_hash[:entry_underlying_price] = entry_underlying_price || fetch_current_underlying_ltp(meta_hash[:index_key])
```

New private method:
```ruby
def fetch_current_underlying_ltp(index_key)
  cfg = AlgoConfig.fetch[:indices]&.find { |i| i[:key].to_s == index_key.to_s }
  return nil unless cfg

  Live::TickQuery.for_security(segment: cfg[:segment], security_id: cfg[:sid])&.ltp
rescue StandardError
  nil
end
```

### 2. Fix Peak Drawdown Activation Gate

#### 2a. TrailingConfig.peak_drawdown_active? — Change AND to OR with emergency override

**File:** `app/services/positions/trailing_config.rb` (lines 132-135)

Before:
```ruby
def peak_drawdown_active?(profit_pct:, current_sl_offset_pct:)
  profit_pct.to_f >= config[:activation_profit_pct] &&
    current_sl_offset_pct.to_f >= config[:activation_sl_offset_pct]
end
```

After:
```ruby
def peak_drawdown_active?(profit_pct:, current_sl_offset_pct:)
  # Emergency: always protect if peak profit exceeds 2x activation threshold
  return true if profit_pct.to_f >= config[:activation_profit_pct].to_f * 2.0

  # Normal: either profit threshold OR SL already moved up is sufficient
  profit_pct.to_f >= config[:activation_profit_pct] ||
    current_sl_offset_pct.to_f >= config[:activation_sl_offset_pct]
end
```

#### 2b. Add emergency peak-loss check to UnifiedExitChecker (sub-second path)

**File:** `app/services/live/unified_exit_checker.rb`

**Why here, not TrailingEngine:** `TrailingEngine.process_tick` runs only every 5 seconds in the enforcement loop. The sub-second path (`RiskManagerService.handle_pnl_event` → `UnifiedExitChecker.check_exit_conditions`) fires on every tick. Fast crashes must be caught here.

Add early in the check chain (priority: after stop loss, before trailing):

```ruby
# Emergency: position had significant profit and flipped to loss
if emergency_peak_loss_exit_triggered?(tracker)
  peak_pct = tracker.high_water_mark_pnl.to_f / (tracker.entry_price.to_f * tracker.quantity.to_i)
  current_pct = tracker.current_pnl_pct.to_f
  return {
    exit: true,
    reason: "EMERGENCY_PEAK_LOSS (peak: #{(peak_pct * 100).round(2)}%, current: #{(current_pct * 100).round(2)}%)"
  }
end
```

New private method:
```ruby
def emergency_peak_loss_exit_triggered?(tracker)
  drawdown_cfg = AlgoConfig.fetch.dig(:position_sizing, :drawdown) || {}
  return false if drawdown_cfg[:emergency_peak_loss_exit] == false

  min_peak_pct = (drawdown_cfg[:emergency_min_peak_pct] || 0.10).to_f
  entry_value = tracker.entry_price.to_f * tracker.quantity.to_i
  return false if entry_value <= 0

  peak_pct = tracker.high_water_mark_pnl.to_f / entry_value
  current_pct = tracker.current_pnl_pct.to_f

  peak_pct >= min_peak_pct && current_pct < -0.02  # Had significant profit, now >2% in loss
end
```

Note: `current < -0.02` (not `current < 0`) to avoid false triggers from brief sub-1% dips after a 10%+ peak. Options premium is volatile; a tiny negative blip shouldn't force exit.

#### 2c. Also add to TrailingEngine as defense-in-depth

**File:** `app/services/live/trailing_engine.rb` (after line 77, before the activation gate)

Same logic, reading config from `AlgoConfig.fetch` directly (not `TrailingConfig.config` which doesn't parse these keys):

```ruby
# Emergency defense-in-depth (sub-second path in UnifiedExitChecker is primary)
drawdown_cfg = AlgoConfig.fetch.dig(:position_sizing, :drawdown) || {}
unless drawdown_cfg[:emergency_peak_loss_exit] == false
  emergency_min_peak = (drawdown_cfg[:emergency_min_peak_pct] || 0.10).to_f
  if peak >= emergency_min_peak && current < -0.02
    tracker = PositionTracker.find_by(id: position_data.tracker_id)
    if tracker&.active?
      reason = "emergency_peak_loss_exit (peak: #{(peak * 100).round(2)}%, current: #{(current * 100).round(2)}%)"
      Live::ExitEngine.execute_exit(tracker: tracker, reason: reason, source: :trailing_engine)
      return true
    end
  end
end
```

#### 2d. Enable peak_drawdown_activation flag

**File:** `config/algo.yml`:
```yaml
feature_flags:
  enable_peak_drawdown_activation: true  # was false — needed for 2a OR-logic to take effect
```

Without this flag enabled, the activation gate block (lines 91-107) is skipped entirely, and the OR-logic fix in 2a has no runtime effect. Enabling it activates the improved gate with OR logic + emergency override.

#### 2e. Config addition

**File:** `config/algo.yml` — Add under `position_sizing.drawdown`:

```yaml
drawdown:
  # ... existing config ...
  emergency_peak_loss_exit: true   # Exit immediately if profitable position flips to loss
  emergency_min_peak_pct: 0.10    # 10% minimum peak before emergency logic applies
```

Note: threshold is 10% (not 5%) combined with `current < -0.02` to avoid false triggers from normal intraday premium volatility.

### 3. Enable Underlying-Aware Exits

#### 3a. Enable feature flag

**File:** `config/algo.yml`:
```yaml
feature_flags:
  enable_underlying_aware_exits: true  # was false
```

This activates `Risk::Rules::UnderlyingExitRule` which checks:
- Structure break against position direction
- Trend score weakness (underlying trend fading)
- ATR collapse (volatility dying)

#### 3b. Add structure invalidation check to UnifiedExitChecker

**File:** `app/services/live/unified_exit_checker.rb`

Add in the check chain after trailing stop and premium momentum failure checks, before the time-based exit check. This ensures trailing/profit-locking rules fire first; structure invalidation is a secondary safety net:

```ruby
# Structure invalidation: underlying broke past entry structure level
if (invalidation_price = tracker.meta&.dig('structure_invalidation_price'))
  underlying_ltp = fetch_underlying_ltp(tracker)
  if underlying_ltp && structure_invalidated?(tracker, underlying_ltp, invalidation_price)
    return {
      exit: true,
      reason: "STRUCTURE_INVALIDATION (underlying #{underlying_ltp.round(2)} broke #{invalidation_price})"
    }
  end
end
```

New private methods:

```ruby
def structure_invalidated?(tracker, underlying_ltp, invalidation_price)
  # Verified: meta['direction'] stores 'long_pe' or 'long_ce' (confirmed from DB)
  direction = tracker.meta&.dig('direction').to_s
  case direction
  when 'long_pe'  # bearish bet — invalidate if underlying rises above structure
    underlying_ltp > invalidation_price.to_f
  when 'long_ce'  # bullish bet — invalidate if underlying falls below structure
    underlying_ltp < invalidation_price.to_f
  else
    false
  end
end

def fetch_underlying_ltp(tracker)
  index_key = tracker.meta&.dig('index_key')
  return nil unless index_key

  cfg = AlgoConfig.fetch[:indices]&.find { |i| i[:key].to_s == index_key.to_s }
  return nil unless cfg

  Live::TickQuery.for_security(segment: cfg[:segment], security_id: cfg[:sid])&.ltp
rescue StandardError
  nil
end
```

#### 3c. Extract shared underlying LTP helper

Both `EntryGuard.fetch_current_underlying_ltp` (section 1c) and `UnifiedExitChecker.fetch_underlying_ltp` (section 3b) resolve index config from `index_key` and call `TickQuery.for_security`. Extract to a shared module to avoid drift:

**File:** `app/services/live/underlying_ltp_resolver.rb` (new)

```ruby
module Live
  module UnderlyingLtpResolver
    def resolve_underlying_ltp(index_key)
      return nil unless index_key

      cfg = AlgoConfig.fetch[:indices]&.find { |i| i[:key].to_s == index_key.to_s }
      return nil unless cfg

      Live::TickQuery.for_security(segment: cfg[:segment], security_id: cfg[:sid])&.ltp
    rescue StandardError
      nil
    end
  end
end
```

Include in both `EntryGuard` and `UnifiedExitChecker`. The private methods `fetch_current_underlying_ltp` (section 1c) and `fetch_underlying_ltp` (section 3b) are replaced by this shared module — they show the logic but should not be implemented as separate private methods.

**Note on ActiveCache:** `ActiveCache.attach_underlying_metadata` (line 546-562) already correctly resolves the underlying security_id via `MetadataResolver.underlying_meta`, which checks `derivative.underlying_security_id` first. No change needed there.

### 4. Testing Strategy

#### 4a. Unit tests

- **`spec/services/entries/entry_guard_spec.rb`** — `apply_bos_metadata!` for both paths:
  - `entry_underlying_price` always stored (never nil)
  - `initial_sl_pct` in reasonable range (0-100)
  - `premium_stop_price` positive, below entry_price
  - BOS path uses premium domain for stops

- **`spec/services/positions/trailing_config_spec.rb`** — `peak_drawdown_active?`:
  - Emergency override at 2x activation
  - OR logic (either condition sufficient)
  - Edge cases: peak=0, negative current

- **`spec/services/live/trailing_engine_spec.rb`** — Emergency defense-in-depth:
  - Peak >10% + current < -2% → exit
  - Peak <10% + current < -2% → no emergency exit
  - Peak >10% + current = -1% → no exit (above -2% threshold)

- **`spec/services/live/unified_exit_checker_spec.rb`** — Structure invalidation:
  - long_pe + underlying above invalidation → exit
  - long_ce + underlying below invalidation → exit
  - Missing LTP or invalidation price → skip (graceful)

#### 4b. Post-deploy validation

Run `rake trading:analyze_positions` and verify:
- `initial_sl_pct` values ≈ 12% across all positions
- "HWM profit → final loss" count drops significantly
- `STRUCTURE_INVALIDATION` appears in exit reasons
- No regression in overall PnL or win rate

### Files Modified

| File | Change |
|------|--------|
| `app/services/signal/engine.rb` | Add `entry_underlying_price` to supertrend metadata |
| `app/services/entries/entry_guard.rb` | Fix BOS domain mixing, include UnderlyingLtpResolver |
| `app/services/positions/trailing_config.rb` | AND→OR gate, emergency override in `peak_drawdown_active?` |
| `app/services/live/trailing_engine.rb` | Emergency peak-loss defense-in-depth |
| `app/services/live/unified_exit_checker.rb` | Emergency peak-loss (sub-second), structure invalidation, include UnderlyingLtpResolver |
| `app/services/live/underlying_ltp_resolver.rb` | **NEW** — shared helper for index LTP lookup |
| `config/algo.yml` | Enable `enable_underlying_aware_exits`, `enable_peak_drawdown_activation`, add emergency drawdown config |

### Files NOT Modified

- PnL calculation (`pnl_updater_service.rb`)
- Order placement (`gateway_paper.rb`, `gateway_live.rb`)
- Redis caching (`redis_pnl_cache.rb`, `tick_cache.rb`)
- WebSocket handling (`market_feed_hub.rb`, `order_update_handler.rb`)
