# Entry + Exit Strategy Redesign: RSI/MACD/SMC Confluence + Spot-Anchored Trailing

**Date:** 2026-04-13
**Status:** Draft — pending approval
**Scope:** Alpha layer only (signal/, indicators/, entries/guards/, risk/rules/)

---

## Problem

### Exit Bleed (DB Evidence — 2,389 positions)

| Exit Rule | Count | Win% | Avg PnL% | Issue |
|---|---|---|---|---|
| TIME_STOP ("scalp exceeded N candles") | 313 (13%) | 35% | **-70.7%** | Forces exit at worst possible moment |
| PREMIUM_MOMENTUM_FAILURE | 430 (18%) | **8%** | -3.0% | 2-min stall fires on consolidation, not failure |
| TRAILING_STOP | 454 (19%) | 93% | **+5.8%** | Works, but premium-noise causes early exit |
| PERCENTAGE_PNL | 171 (7%) | 100% | **+53.0%** | Best rule — proves big moves exist |

The trailing stop activates at 10% profit and allows a 5% premium drawdown. Because option
premiums oscillate 15-30% on normal consolidation even while the underlying trend is fully
intact, this exits at +5.8% avg while PERCENTAGE_PNL — which waits longer — exits at +53%.

**The fundamental problem:** exit decisions are based on option *premium* noise rather than
whether the *underlying spot* trend has actually ended.

### Entry Quality (Signal Data — 51,741 signals)
- 89% bearish signals (10% bullish) — reflects market reality but creates concentration risk
- RSI (`rsi_indicator.rb`) and MACD (`macd_indicator.rb`) are fully implemented but **not wired**
  into Signal::Engine's confidence score or validation
- SMC (36-file implementation) acts only as a binary permission gate — not a scored confluence factor
- IV filter uses a 5-candle price-volatility *proxy* instead of the actual `implied_volatility`
  field already returned by `DhanAdapter` option chain

### Recent Trajectory
Last 7 days: 40% win rate, avg winner +4.49%, avg loser -3.15% (EV ≈ -0.09%).
System is nearly breakeven already. These changes target +3–5% EV per trade.

---

## Goal

1. **Spot-anchored trailing**: hold winners as long as the underlying spot trend is intact;
   exit when the *spot* shows structural breakdown — not when option premium wobbles.
2. **SMC as scored confluence**: BiasEngine + BOS/CHOCH alignment elevates confidence and
   provides discount/premium zone filters for entry direction.
3. **Wire RSI + MACD**: use already-implemented indicators as entry confirmation and
   confidence score factors.
4. **Fix TIME_STOP and PREMIUM_MOMENTUM**: both are exiting too aggressively; recalibrate
   to only fire when the position is genuinely dead.
5. **Real IV filter**: replace the volatility-proxy hack with actual IV from option chain data.

---

## Architecture

```
Signal::Engine#execute_standard_analysis_flow
  ├── [existing] Supertrend (1m) → primary direction
  ├── [existing] ADX strength gate
  ├── [NEW] EmaDirectionIndicator (9/21) → tie-break direction confirm
  ├── [existing] comprehensive_validation()
  │     ├── [existing] IV rank proxy check   ← replace with real IV check
  │     ├── [existing] Theta risk check (after 14:00)
  │     ├── [existing] ADX minimum
  │     ├── [existing] Trend confirmation (price action)
  │     ├── [existing] Market timing
  │     └── [NEW] RSI momentum check (6th gate)
  ├── calculate_confidence_score()
  │     ├── [existing] ADX factor (+0.3 max)
  │     ├── [existing] multi-TF alignment (+0.2)
  │     ├── [existing] validation pass (+0.1)
  │     ├── [NEW] MACD histogram factor (+0.1)
  │     └── [NEW] SMC BiasEngine factor (+0.2)
  └── execute_execution_gates()
        ├── [existing] SMC PermissionResolver (BLOCKED gate)
        └── [NEW] SMC Discount/Premium Zone check (direction filter)

UnifiedExitChecker (per-tick)
  ├── [existing] PortfolioFloorRule (10)
  ├── [existing] EmergencyPeakLossRule (15)
  ├── [existing] StopLossRule (20)
  ├── [FIXED]   TimeStopRule (25)          ← only fires when spot trend broken
  ├── [existing] EarlyTrendFailureRule (25)
  ├── [FIXED]   PremiumMomentumFailureRule (30)  ← spot-confirm before exit
  ├── [existing] TakeProfitRule (35)
  ├── [REPLACED] TrailingStopRule (50)     ← spot-anchored HWM trailing
  ├── [existing] TimeBasedExitRule (55)
  └── [existing] StructureInvalidationRule (60)
```

---

## Part 1 — Entry Changes

### 1.1 New Indicator: EmaDirectionIndicator

**File:** `app/services/indicators/ema_direction_indicator.rb`

```ruby
# Computes 9/21 EMA cross direction on the candle series.
# Returns: { direction: :bullish | :bearish | :neutral, fast: Float, slow: Float, aligned: Boolean }
class Indicators::EmaDirectionIndicator
  DEFAULT_FAST = 9
  DEFAULT_SLOW = 21

  def initialize(series:, config: {})
    @series = series
    @fast_period = config.fetch(:fast_period, DEFAULT_FAST)
    @slow_period = config.fetch(:slow_period, DEFAULT_SLOW)
  end

  def calculate
    closes = @series.candles.map(&:close)
    return neutral if closes.size < @slow_period
    fast_ema = ema(closes, @fast_period)
    slow_ema = ema(closes, @slow_period)
    direction = fast_ema > slow_ema ? :bullish : fast_ema < slow_ema ? :bearish : :neutral
    { direction: direction, fast: fast_ema, slow: slow_ema,
      aligned: direction != :neutral, spread_pct: ((fast_ema - slow_ema).abs / slow_ema * 100).round(3) }
  end

  private

  def ema(closes, period)
    k = 2.0 / (period + 1)
    closes.each_with_index.reduce(nil) do |prev, (c, i)|
      i < period - 1 ? nil : (prev.nil? ? closes[0..period-1].sum / period : c * k + prev * (1 - k))
    end
  end

  def neutral
    { direction: :neutral, fast: nil, slow: nil, aligned: false, spread_pct: 0 }
  end
end
```

**Wiring into Signal::Engine `execute_standard_analysis_flow`:**
- Compute EMA direction at end of primary analysis
- If Supertrend says :bullish but EMA says :bearish → require ADX ≥ 25 to proceed
  (cross-confirmation or strength override)
- If both agree → normal ADX threshold (≥ 15 in trend_continuation)
- Store in `analysis_context[:ema_direction]` for use in confidence_score

### 1.2 RSI as 6th Validation Gate

**File:** `app/services/signal/engine.rb` — `comprehensive_validation()` method

Add a 6th check after the existing 5:

```ruby
# RSI Momentum Check (new, check 6)
if mode_config[:require_rsi_check]
  rsi_result = RsiIndicator.new(series: series).calculate_at(-1)
  rsi_val = rsi_result[:value].to_f

  if final_direction == :bullish
    # Buying CE: RSI must not be in overbought territory (no chasing tops)
    # RSI 45–75 is the ideal momentum zone for CE entries
    if rsi_val > mode_config.fetch(:rsi_overbought_block, 78)
      return validation_failure("RSI overbought (#{rsi_val.round(1)}) — avoid chasing CE entry")
    end
  elsif final_direction == :bearish
    # Buying PE: RSI must not be in oversold territory (no chasing bottoms)
    # RSI 25–55 is the ideal momentum zone for PE entries
    if rsi_val < mode_config.fetch(:rsi_oversold_block, 22)
      return validation_failure("RSI oversold (#{rsi_val.round(1)}) — avoid chasing PE entry")
    end
  end
end
```

**Config additions to each validation mode in `algo.yml`:**
```yaml
conservative:
  require_rsi_check: true
  rsi_overbought_block: 72   # CE blocked above RSI 72
  rsi_oversold_block: 28     # PE blocked below RSI 28

balanced:
  require_rsi_check: true
  rsi_overbought_block: 78
  rsi_oversold_block: 22

aggressive:
  require_rsi_check: false   # No RSI gate in aggressive mode
```

**Rationale:** The RSI check is NOT a direction signal — it is an *anti-chase* filter. It prevents
buying CE when RSI is already at 80 (everyone has already bought, move is exhausted) and buying PE
when RSI is at 15 (everyone has already sold, exhaustion). It does not block entries in the
50-70 RSI zone for CE or 30-50 zone for PE — those are the ideal trending momentum entries.

### 1.3 MACD as Confidence Score Factor

**File:** `app/services/signal/engine.rb` — `calculate_confidence_score()` method

Add to the confidence formula:

```ruby
# MACD histogram alignment (+0.10 when histogram agrees with direction)
macd_result = MacdIndicator.new(series: series).calculate_at(-1)
histogram = macd_result.dig(:value, :histogram).to_f
macd_factor = 0.0
if final_direction == :bullish && histogram > 0
  macd_factor = 0.10
elsif final_direction == :bearish && histogram < 0
  macd_factor = 0.10
end
```

Cap remains at 1.0. MACD alignment does not block an entry — it raises confidence when present.

### 1.4 SMC BiasEngine as Scored Confluence (replaces binary gate)

**Current behaviour:** `Smc::BiasEngine` result passes through `Trading::PermissionResolver` which
returns :bullish/:bearish/:blocked. If blocked → signal dropped. If direction mismatches → signal
dropped. Binary.

**New behaviour:** Keep the hard block for :blocked status. For direction alignment, move from
binary kill to scored confluence:

```ruby
# In calculate_confidence_score():
smc_bias = get_smc_bias(index_cfg)   # :bullish | :bearish | :neutral | :blocked
smc_factor = case smc_bias
             when final_direction then 0.20   # Full alignment
             when :neutral        then 0.05   # No SMC read, small neutral boost
             else 0.0                         # Misaligned — no boost (but not blocked)
             end
# SMC BLOCKED status still hard-blocks (existing behaviour preserved)
```

**Net effect:** A signal with Supertrend bullish + SMC bullish scores 0.20 higher than one with
SMC neutral. Misaligned SMC (SMC bearish but Supertrend bullish) scores zero here, reducing total
confidence below minimum threshold in most cases — effectively blocking without a hard gate.

### 1.5 SMC Discount/Premium Zone Filter

**File:** `app/services/entries/guards/bos_structure_guard.rb` (or new inline check in `execute_execution_gates`)

```ruby
# Use Smc::Detectors::PremiumDiscount to classify current price
pd = Smc::Detectors::PremiumDiscount.new(candles: series.candles)
zone = pd.zone   # :premium | :discount | :equilibrium

if final_direction == :bullish && zone == :premium
  # Buying CE when price is in premium zone = chasing highs; block or require ADX ≥ 30
  return execution_gate_failure("SMC premium zone — CE entry risk") if adx_value < 30
elsif final_direction == :bearish && zone == :discount
  # Buying PE when price is in discount zone = chasing lows; block or require ADX ≥ 30
  return execution_gate_failure("SMC discount zone — PE entry risk") if adx_value < 30
end
# Ideal: CE in discount zone (+0.10 confidence), PE in premium zone (+0.10 confidence)
```

**Rationale:** SMC principle — buy CE (calls) when spot is in *discount* (below equilibrium, likely
to revert up); buy PE (puts) when spot is in *premium* (above equilibrium, likely to revert down).
Only bypass when ADX ≥ 30 (very strong momentum — trend can stay extended).

### 1.6 Real IV Filter (replace volatility proxy)

**File:** `app/services/signal/engine.rb` — `validate_iv_rank()` method

**Current:** Uses `avg(|price_change|) * 1000` as IV proxy.
**New:** Use actual `implied_volatility` from option chain data already available in
`analysis_context[:option_data][:implied_volatility]`.

```ruby
def validate_iv_rank_real(analysis_context, mode_config)
  iv = analysis_context.dig(:option_data, :implied_volatility).to_f
  return :pass if iv.zero?   # No IV data — pass through

  iv_min = mode_config.fetch(:iv_rank_min, 0.10)
  iv_max = mode_config.fetch(:iv_rank_max, 0.75)

  if iv > iv_max
    return validation_failure("IV too high (#{(iv*100).round(1)}%) — option too expensive, IV crush risk")
  elsif iv < iv_min
    return validation_failure("IV too low (#{(iv*100).round(1)}%) — insufficient premium")
  end
  :pass
end
```

**Config:**
```yaml
balanced:
  iv_rank_max: 0.75   # Block entries when IV > 75% (pre-event spike)
  iv_rank_min: 0.10   # Block entries when IV < 10% (dead market)
conservative:
  iv_rank_max: 0.60
aggressive:
  iv_rank_max: 0.90
```

---

## Part 2 — Exit Changes

### 2.1 Spot-Anchored HWM Trailing (core innovation)

**Problem:** TrailingStopRule checks if `option_premium_HWM - current_ltp >= drop_threshold`.
Premium oscillates 15-30% on consolidation → fires at +5.8% avg while the underlying is still
trending.

**New design:** Two-layer check on every tick.

**Layer 1 — Spot Trend Alive? (hold condition)**
```
Supertrend direction matches position side?   → AND
ADX ≥ min_adx_to_hold (config, default 15)?  → AND
No CHOCH detected by Smc::Detectors::Structure in last 3 candles?
```
If all three → **hold unconditionally** (ignore premium drawdown from HWM).

**Layer 2 — Hard Premium Safety Floor (catastrophe guard)**
Premium must not fall below `entry_price × (1 - hard_floor_pct)`.
Default `hard_floor_pct: 0.50` — if option loses 50% from *entry* even while holding, exit.
This prevents a scenario where the spot trend is technically intact but the option has decayed
to near-zero due to theta or a quick intraday reversal.

**Layer 3 — Spot Structure Break (exit trigger)**
When Layer 1 fails (Supertrend flips, ADX collapses, CHOCH detected):
- Immediately check premium vs HWM
- If premium > HWM × 0.70 → graceful trailing exit (accept up to 30% pullback from HWM)
- If premium ≤ HWM × 0.70 → immediate exit (trend already reversed, big drawdown)

**Implementation in `app/services/risk/rules/trailing_stop_rule.rb`:**

```ruby
def evaluate(context)
  tracker = context[:tracker]
  snapshot = context[:snapshot]
  return skip_result unless trailing_armed?(snapshot)

  # Layer 1: Is the underlying spot trend still alive?
  spot_context = evaluate_spot_trend(tracker, snapshot)

  if spot_context[:trend_alive]
    # Layer 2: Hard premium safety floor only
    entry_price = tracker.entry_price.to_f
    current_ltp = snapshot[:ltp].to_f
    hard_floor = entry_price * (1.0 - hard_floor_pct)
    if current_ltp < hard_floor
      return exit_result(reason: "TRAILING_HARD_FLOOR", metadata: spot_context)
    end
    return skip_result   # Trend alive, premium above floor — hold
  end

  # Layer 3: Spot trend broken — apply spot-break trailing
  hwm_ltp = snapshot[:hwm_ltp].to_f
  current_ltp = snapshot[:ltp].to_f
  drawdown_from_hwm = hwm_ltp > 0 ? (hwm_ltp - current_ltp) / hwm_ltp : 0
  allowed_drawdown = spot_break_drawdown_pct(spot_context[:severity])  # 0.20-0.30

  if drawdown_from_hwm >= allowed_drawdown
    return exit_result(reason: "TRAILING_SPOT_BREAK", metadata: spot_context)
  end

  skip_result
end

private

def evaluate_spot_trend(tracker, snapshot)
  side = tracker.side  # 'long_ce' or 'long_pe'
  underlying_series = snapshot[:underlying_series]   # passed from RiskManagerService tick context
  return { trend_alive: true, severity: :none } unless underlying_series

  # CandleExtension methods confirmed at app/models/concerns/candle_extension.rb
  supertrend = instrument.supertrend_signal(interval: '1') rescue {}
  adx_value  = instrument.adx(14, interval: '1') rescue 0
  series     = instrument.candle_series(interval: '1') rescue nil
  structure  = series ? (Smc::Detectors::Structure.new(candles: series.candles).detect rescue {}) : {}

  trend_direction = supertrend[:trend]   # :long or :short
  expected_direction = side == 'long_ce' ? :long : :short
  supertrend_ok = trend_direction == expected_direction
  adx_ok = adx_value.to_f >= min_adx_to_hold
  no_choch = !structure[:choch_detected]

  trend_alive = supertrend_ok && adx_ok && no_choch
  severity = if !supertrend_ok && !adx_ok then :severe
             elsif !supertrend_ok || !no_choch then :moderate
             else :mild
             end

  { trend_alive: trend_alive, severity: severity,
    supertrend_ok: supertrend_ok, adx_ok: adx_ok, no_choch: no_choch,
    adx_value: adx_value, trend_direction: trend_direction }
end

def spot_break_drawdown_pct(severity)
  case severity
  when :severe   then 0.15  # Supertrend flipped AND ADX collapsed → tight 15%
  when :moderate then 0.22  # One condition broken → moderate 22%
  else                0.28  # Mild weakness → allow 28% pullback from HWM
  end
end
```

**Config additions to `algo.yml`:**
```yaml
trailing:
  spot_anchored:
    enabled: true
    min_adx_to_hold: 15
    hard_floor_pct: 0.50        # Exit if option falls 50% from entry even while holding
    spot_break_drawdown:
      severe: 0.15
      moderate: 0.22
      mild: 0.28
  # Keep existing 3-phase activation thresholds (they now control WHEN trailing arms, not exit)
  activation_pct: 0.10          # Still arm at 10% profit
```

**Underlying data access — no RiskManagerService change needed:**
`UnifiedExitChecker` already fetches underlying context directly using
`instrument.adx(14, interval: '5') rescue nil` (line 246). The `SpotTrendEvaluator` follows
the same self-contained pattern — it resolves the spot instrument from `index_key` and calls
indicators on it directly. No changes to the locked `RiskManagerService` files.

### 2.2 TIME_STOP Recalibration

**File:** `app/services/risk/rules/time_stop_rule.rb`

**Current:** Bypass only if `pnl_pct >= 0.05` (5% profit). Below that, exits at avg -70.7%.

**New bypass conditions (any one = skip TIME_STOP):**
1. `pnl_pct >= 0` — any profitable position is immune; let trailing own the exit
2. Spot trend alive (same check as trailing Layer 1) — if underlying still trending, give it time
3. `pnl_pct >= -0.10` AND hold_time < 15 min — in the normal loss zone, give 15 min not 8 min

**New config:**
```yaml
time_stop:
  enabled: true
  scalp:
    max_minutes: 15             # raised from 8
    max_candles: 15             # raised from 8 (was "2" in old data)
    bypass_if_profitable: true  # immune when pnl >= 0
    bypass_if_spot_trend: true  # immune when underlying trend intact
  trend:
    NIFTY: 30
    BANKNIFTY: 25
    SENSEX: 25
```

### 2.3 PREMIUM_MOMENTUM_FAILURE Recalibration

**File:** `app/services/live/unified_exit_checker.rb` — `premium_momentum_failure_hit?()`
**Also:** `app/services/risk/rules/premium_momentum_failure_rule.rb`

**Current:** Fires when premium hasn't made new high for 2 min AND pnl_pct ≤ 0.

**New conditions — ALL must be true:**
1. Premium stall: no new HWM for `stall_minutes` (raised to 6 min default)
2. Position at loss: `pnl_pct < -0.05` (must be -5% or worse, not just zero)
3. **Spot confirms failure:** underlying Supertrend direction has flipped against position
   OR ADX < 12 (trend has collapsed)

```ruby
def premium_momentum_failure_hit?(tracker, snapshot)
  cfg = AlgoConfig.fetch.dig(:risk, :exits, :premium_momentum_failure) || {}
  return false unless cfg[:enabled]

  # Gate 1: Stall time
  elapsed_since_peak = stall_elapsed_minutes(tracker, snapshot)
  return false if elapsed_since_peak < resolve_stall_minutes(tracker)

  # Gate 2: Must be at meaningful loss (not just zero)
  return false if snapshot[:pnl_pct].to_f >= -0.05

  # Gate 3: Spot must confirm the failure (NEW)
  spot_context = evaluate_spot_trend_for(tracker, snapshot)
  spot_confirms_failure = !spot_context[:trend_alive]
  return false unless spot_confirms_failure

  true
end
```

**Config:**
```yaml
premium_momentum_failure:
  enabled: true
  default_stall_minutes: 6     # raised from 2
  min_loss_pct: 0.05           # only fire at -5% or worse (new)
  require_spot_confirmation: true   # new — spot must also confirm failure
  index_overrides:
    SENSEX:
      stall_minutes: 6
  session_overrides:
    chop_decay:
      stall_minutes_add: 0
    close_gamma:
      stall_minutes_add: 2
```

---

## Part 3 — Configuration Summary (algo.yml changes)

```yaml
# Validation mode additions
signals:
  validation_modes:
    balanced:
      require_rsi_check: true
      rsi_overbought_block: 78
      rsi_oversold_block: 22
      iv_rank_max: 0.75           # real IV from option chain
      iv_rank_min: 0.10
    conservative:
      require_rsi_check: true
      rsi_overbought_block: 72
      rsi_oversold_block: 28
      iv_rank_max: 0.60
    aggressive:
      require_rsi_check: false

  # New indicator registrations
  indicators:
    - type: ema_direction
      enabled: true
      config: { fast_period: 9, slow_period: 21 }
    - type: rsi
      enabled: true
      config: { period: 14 }
    - type: macd
      enabled: true
      config: { fast_period: 12, slow_period: 26, signal_period: 9 }

  smc:
    use_as_scored_confluence: true    # NEW — replaces pure binary gate
    discount_premium_zone_filter: true  # NEW
    zone_filter_adx_override: 30      # bypass zone filter if ADX >= 30

# Exit recalibration
risk:
  exits:
    trailing:
      spot_anchored:
        enabled: true
        min_adx_to_hold: 15
        hard_floor_pct: 0.50
        spot_break_drawdown:
          severe: 0.15
          moderate: 0.22
          mild: 0.28

    time_stop:
      scalp:
        max_minutes: 15
        max_candles: 15
        bypass_if_profitable: true
        bypass_if_spot_trend: true
      trend:
        NIFTY: 30
        BANKNIFTY: 25
        SENSEX: 25

    premium_momentum_failure:
      default_stall_minutes: 6
      min_loss_pct: 0.05
      require_spot_confirmation: true
```

---

## Files to Create / Modify

### New Files
- `app/services/indicators/ema_direction_indicator.rb` — EMA 9/21 cross

### Modified Files (Alpha Layer — safe to change)
| File | Change |
|---|---|
| `app/services/signal/engine.rb` | Add EMA direction check, RSI 6th gate, MACD confidence factor, SMC BiasEngine scoring, real IV filter, SMC zone filter |
| `app/services/risk/rules/trailing_stop_rule.rb` | Replace premium-% trailing with spot-anchored 3-layer logic |
| `app/services/risk/rules/time_stop_rule.rb` | Add profitable bypass + spot trend bypass |
| `app/services/risk/rules/premium_momentum_failure_rule.rb` | Add -5% loss gate + spot confirmation |
| `app/services/live/unified_exit_checker.rb` | Pass underlying_series in snapshot context; update `premium_momentum_failure_hit?` |
| `config/algo.yml` | Config additions per Part 3 |

### Unchanged (Locked Layer — do not touch)
`exit_engine.rb`, `gateway_live.rb`, `market_feed_hub.rb`, `tick_cache.rb`, `pnl_updater_service.rb`,
all `orders/`, all `positions/states/`, all `lib/trading_system/`

---

## Shared Helper: `evaluate_spot_trend_for(tracker, snapshot)`

Both `TrailingStopRule` and `PremiumMomentumFailureRule` need the same spot-trend check.
Extract into a shared module:

**File:** `app/services/live/spot_trend_evaluator.rb`

```ruby
module Live::SpotTrendEvaluator
  # Returns { trend_alive: Boolean, severity: :none|:mild|:moderate|:severe, ... }
  # Mirrors the existing pattern: instrument.adx(14, interval: '5') rescue nil
  # (UnifiedExitChecker line 246) — no locked-layer changes needed.
  def evaluate_spot_trend_for(tracker, _snapshot = nil)
    index_key = tracker.meta&.dig('index_key')
    return { trend_alive: true, severity: :none } unless index_key

    # Resolve instrument following UnifiedExitChecker line 87:
    #   tracker.instrument || tracker.watchable&.instrument
    # Implementer note: verify whether this returns the option contract or the spot index
    # instrument. For a true spot-trend check, the spot index instrument is needed.
    # If tracker.instrument is the option, check tracker.watchable&.instrument or look up
    # the spot by index_key via Instrument.find_by(symbol_name: index_key, segment: 'I').
    instrument = tracker.instrument || tracker.watchable&.instrument
    return { trend_alive: true, severity: :none } unless instrument

    side = tracker.side
    expected_st_direction = side == 'long_ce' ? :long : :short

    # instrument.adx returns Float|nil; instrument.supertrend_signal returns :long_entry|:short_entry|nil
    # Smc::Detectors::Structure takes a CandleSeries directly, not a candles: keyword
    adx_value = instrument.adx(14, interval: '1').to_f rescue 0.0
    st_signal = instrument.supertrend_signal(interval: '1') rescue nil
    series    = instrument.candle_series(interval: '1') rescue nil
    choch_detected = if series
                       structure = Smc::Detectors::Structure.new(series) rescue nil
                       structure ? (structure.choch? != false) : false
                     else
                       false
                     end

    min_adx = AlgoConfig.fetch.dig(:risk, :exits, :trailing, :spot_anchored, :min_adx_to_hold).to_f
    supertrend_ok = st_direction == expected_st_direction
    adx_ok        = adx_value >= min_adx
    no_choch      = !choch_detected

    severity = if !supertrend_ok && !adx_ok then :severe
               elsif !supertrend_ok || !no_choch then :moderate
               else :mild
               end

    { trend_alive: supertrend_ok && adx_ok && no_choch,
      severity: severity, supertrend_ok: supertrend_ok,
      adx_ok: adx_ok, no_choch: no_choch, adx_value: adx_value }
  end
end
```

Include this module in both `TrailingStopRule` and `PremiumMomentumFailureRule`.

---

## Expected Impact (based on DB analysis)

| Metric | Current | Expected After |
|---|---|---|
| TIME_STOP avg PnL | -70.7% | ~-15% (bypasses profitable + trending positions) |
| PREMIUM_MOMENTUM win rate | 8% | ~35-45% (spot confirm gate filters false fires) |
| TRAILING avg winner | +5.8% | +20-40% (spot-anchored HWM lets winners run) |
| PERCENTAGE_PNL count | 171 | ↑ more exits through this high-quality rule |
| Overall EV/trade | ~-0.09% | Target +3-5% |

---

## Verification

### Unit Tests
- `spec/services/indicators/ema_direction_indicator_spec.rb` — verify cross detection
- `spec/services/risk/rules/trailing_stop_rule_spec.rb` — test 3-layer spot-anchored logic
- `spec/services/risk/rules/time_stop_rule_spec.rb` — test bypass conditions
- `spec/services/risk/rules/premium_momentum_failure_rule_spec.rb` — test spot confirm gate
- `spec/services/live/spot_trend_evaluator_spec.rb` — test severity classifications

### Paper Trading Verification
1. Start paper trading with `ENABLE_TRADING_SERVICES=true bundle exec rake trading:daemon`
2. After 50+ positions, run:
   ```ruby
   rails runner "
   exited = PositionTracker.where(status: 'exited').where('created_at > ?', 7.days.ago)
   by_reason = exited.group_by { |p| p.meta&.dig('exit_reason')&.split(' ')&.first || 'unknown' }
   by_reason.each { |r, ps|
     pnls = ps.map { |p| p.last_pnl_pct.to_f }
     avg = (pnls.sum/pnls.count*100).round(1)
     win = (pnls.count { |p| p > 0 }.to_f/pnls.count*100).round(0)
     puts \"#{r}: #{ps.count} trades, #{win}% win, #{avg}% avg\"
   }
   "
   ```
3. Check targets:
   - TRAILING_SPOT_BREAK avg > +20%
   - PREMIUM_MOMENTUM win rate > 30%
   - TIME_STOP count < 50/week (should rarely fire)
   - PERCENTAGE_PNL count increases

### Signal Quality Check
Run after 100 signals:
```ruby
rails runner "
sigs = TradingSignal.where('created_at > ?', 7.days.ago)
puts \"Bullish/Bearish: #{sigs.where(direction: 'bullish').count}/#{sigs.where(direction: 'bearish').count}\"
puts \"Avg confidence: #{(sigs.pluck(:confidence_score).map(&:to_f).sum / sigs.count).round(3)}\"
# Confidence should be higher now with MACD + SMC scoring factors
"
```
