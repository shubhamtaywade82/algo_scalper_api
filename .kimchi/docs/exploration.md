# algo_scalper_api Options Buying Exploration

**Branch:** `options-buying`
**Date:** 2026-06-09
**Goal:** Diagnose why NIFTY/BANKNIFTY/SENSEX options buying trades are not being taken.

---

## 1. Entry Flow (Signal → Order Placement)

### 1.1 Signal Generation Pipeline

**File:** `app/services/signal/engine.rb` (2036 lines, key orchestrator)

The full entry pipeline is:

```
Signal::Engine.run_for(index_cfg, regime_state)
  └─→ tradable_session?()              # Is market open?
  └─→ fetch_instrument()               # Get Instrument from cache
  └─→ initialize_analysis_context()    # Load timeframe, strategy config
  └─→ execute_standard_analysis_flow() OR execute_supertrend_only_flow()
       └─→ perform_standard_ta()        # Index TA filter (optional)
       └─→ resolve_strategy_recommendation()
       └─→ analyze_primary_and_confirmation() → analyze_timeframe()
       └─→ regime_result = MarketRegimeDetector.new(primary_series).detect
       └─→ direction_gate_blocked?()    # DirectionGate (RANGING blocks all)
       └─→ comprehensive_validation()   # IV rank, theta risk, ADX, timing, RSI anti-chase
       └─→ validate_market_timing()     # 9:15-15:30 IST window check
       └─→ evaluate_entry_quality()     # EntryQualityFilter
       └─→ execute_no_trade_gate()      # NoTradeEngine (can block)
       └─→ entry_dte_guard_blocks?()    # DTE threshold check
       └─→ execute_execution_gates()
            └─→ EntryFilterEngine (institutional filter, optional)
            └─→ PermissionResolver.resolve()  # **CRITICAL: SMC+AVRZ permission**
            └─→ get_smc_decision()     # SMC BiasEngine decision alignment
            └─→ MomentumValidator.validate()
       └─→ execute_options_analysis()   # IV rank, theta risk, gamma pressure
       └─→ execute_entry_gate()
            └─→ options_analysis_gate_blocks_entry?()
            └─→ Options::ChainAnalyzer.pick_strikes_with_qualification()
            └─→ MomentumValidator.validate_option_pick() (premium momentum)
            └─→ evaluate_market_context_for_entry() → MarketPermissionGate
       └─→ trigger_entry_flow()
            └─→ Entries::EntryGuard.try_enter() (for supertrend path)
            OR
            └─→ Entries::BosEntryEngine.run_for() (for BOS path)
```

### 1.2 Entry Guards Pipeline

**File:** `app/services/entries/entry_guard_pipeline.rb`

Guards run in **strict order**; first guard that blocks wins:

```
EntryGuardPipeline (22 guards):
  1. DrawdownGuard           → Portfolio::DrawdownGuard.triggered?
  2. EntryPolicyGuard        → permission execution policy check
  3. CircuitBreakerGuard     → circuit breaker active?
  4. MiddayQualityGuard      → ADX >= 28 bypass (S3/S4 blocks)
  5. EdgeFailureGuard        → edge degradation detected?
  6. LossStreakGuard         → consecutive losses cooldown (default: 2 losses, 30min)
  7. SegmentExpectancyGuard  → negative realized edge in (index, regime) segment
  8. StrikeCooldownGuard     → same contract cooldown after loss (default: 20min)
  9. DailyLimitsGuard        → daily trade limits exceeded?
  10. MaxConcurrentGuard     → max concurrent positions per index?
  11. InstrumentLookupGuard  → instrument found? (sets context[:instrument])
  12. LtpResolutionGuard     → LTP fresh enough? (tick cache age)
  13. ExpiryWeekPowerTrendGuard → expiry week power trend mode
  14. TimeRegimeGuard        → S3 (11:30-13:45) blocks entries unless ADX >= 22
  15. BankniftyLastWeekGuard → BANKNIFTY only trades in last 7 days before monthly expiry
  16. WeeklyExpiryGuard      → weekly expiry check
  17. BosStructureGuard      → BOS confirmation required?
  18. ExposureGuard          → portfolio exposure limit?
  19. CooldownGuard          → index-level re-entry cooldown
  20. SizingGuard            → position sizing validation
  21. RiskPolicyGuard        → risk policy compliance
  22. SmcNavigatorGuard      → SMC Navigator overlay check

If ALL pass → OrderExecutionService.call(context) → creates PositionTracker
```

### 1.3 Key Entry Guard Files

| Guard | File | Key Config |
|---|---|---|
| **DrawdownGuard** | `app/services/entries/guards/drawdown_guard.rb` | `Portfolio::DrawdownGuard` |
| **LossStreakGuard** | `app/services/entries/guards/loss_streak_guard.rb` | `loss_streak_guard.enabled: true`, `consecutive_losses_threshold: 2`, `cooldown_minutes: 30` |
| **SegmentExpectancyGuard** | `app/services/entries/guards/segment_expectancy_guard.rb` | `segment_expectancy_guard.enabled: true` |
| **StrikeCooldownGuard** | `app/services/entries/guards/strike_cooldown_guard.rb` | `strike_cooldown_guard.cooldown_minutes: 20` |
| **DailyLimitsGuard** | `app/services/entries/guards/daily_limits_guard.rb` | `trade_limits.max_trades_per_day` |
| **MaxConcurrentGuard** | `app/services/entries/guards/max_concurrent_guard.rb` | `max_concurrent_per_index: 2` |
| **TimeRegimeGuard** | `app/services/entries/guards/time_regime_guard.rb` | S3 blocks entries unless ADX >= 22 |
| **BankniftyLastWeekGuard** | `app/services/entries/guards/banknifty_last_week_guard.rb` | Only trades last 7 calendar days of month |
| **ExpiryWeekPowerTrendGuard** | `app/services/entries/guards/expiry_week_power_trend_guard.rb` | `expiry_week_power_trend.enabled: true`, `adx_min: 40` |

---

## 2. Entry Guards / Conditions — Full List

### 2.1 Signal Engine Validation Gates (Signal::Engine)

These run **before** entry guards:

| Check | Method | Failure Message |
|---|---|---|
| Market open | `tradable_session?()` → `TradingSession::Service.market_closed?` | "Market closed" |
| Index TA filter | `perform_standard_ta()` | TA signal neutral or low confidence |
| Regime direction gate | `direction_gate_blocked?()` | Counter-trend trade (RANGING/CHOPPY blocks all) |
| Comprehensive validation | `comprehensive_validation()` | IV rank, theta risk, ADX strength, market timing, RSI |
| **Market timing** | `validate_market_timing()` | "Not a trading day", "Market not yet open", "Market closed" |
| Entry quality filter | `evaluate_entry_quality()` | Score below min_score |
| No-trade engine | `execute_no_trade_gate()` | Score too low, insufficient context |
| DTE guard | `entry_dte_guard_blocks?()` | DTE <= threshold |
| Permission resolver | `execute_execution_gates()` → `PermissionResolver.resolve()` | **SMC+AVRZ permission blocked** |
| SMC decision alignment | `smc_decision_aligned?()` | SMC call/put misalignment |
| Strike selection | `execute_entry_gate()` → `ChainAnalyzer.pick_strikes_with_qualification()` | No suitable strikes |
| Options analysis gate | `options_analysis_gate_blocks_entry?()` | IV rank or theta risk failure |
| Market permission gate | `evaluate_market_context_for_entry()` | Low conviction/chain confidence |

### 2.2 PermissionResolver — CRITICAL

**File:** `app/services/trading/permission_resolver.rb`

```ruby
def resolve(symbol:, instrument:)
  # Key config flags:
  enable_smc_permission = config.fetch(:enable_smc_avrz_permission, true)
  permission_mode = config[:permission_mode] || 'strict'  # strict | lenient | bypass

  # Returns: :blocked | :execution_only | :scale_ready | :full_deploy
  # 
  # If enable_smc_permission == false → returns :scale_ready (ALLOWS TRADING)
  # If permission_mode == 'bypass' → returns :execution_only
  # If permission_mode == 'lenient' → needs HTF candles only
  # If permission_mode == 'strict' → needs HTF + MTF + LTF candles
  #
  # Requires Smc::PermissionSnapshot and Smc::AvrzStateResolver
  # On error in lenient mode → :execution_only
  # On error in strict mode → :blocked
end
```

**This is a common blocking point.** If SMC/AVRZ data is missing or the service is not returning candles, trades will be blocked.

### 2.3 TimeRegimeGuard

**File:** `app/services/entries/guards/time_regime_guard.rb`

S3 (11:30-13:45 IST) is the "chop/decay" zone:
- **Entries are blocked in S3** unless `expiry_power_trend` is set AND ADX >= the trending_adx_bypass (28)
- This is a hard block: `return { blocked: "time regime guard: S3 no-entry window" }`

---

## 3. Configurations

### 3.1 AlgoConfig Fetch Order

**File:** `app/lib/algo_config.rb`

```
1. DB document (AlgoConfig::DocumentStore.current_mutable_document) — seeded from algo.yml + legacy overrides
2. Apply signal_tier_preset (exploratory/standard/selective) — overlays from config/signal_tier_presets.yml
3. Apply LIVE_TRADING env override — forces paper_trading.enabled
```

### 3.2 Signal Tier Presets

**File:** `config/signal_tier_presets.yml`

Current algo.yml sets: `signals.signal_tier: selective`

| Setting | exploratory | standard | selective (CURRENT) |
|---|---|---|---|
| validation_mode | aggressive | (from algo.yml) | **conservative** |
| permission_mode | lenient | (from algo.yml) | **strict** |
| enable_direction_gate | false | (from algo.yml) | **true** |
| enable_no_trade_engine | false | (from algo.yml) | **true** |
| halt_on_validation_failure | false | (from algo.yml) | **true** |
| options_analysis_gate | disabled | (from algo.yml) | **enabled** |
| entry_dte_guard | disabled | (from algo.yml) | **enabled** |
| indicator_preset | loose | (from algo.yml) | **tight** |
| min_confidence | 50 | (from algo.yml) | **72** |
| enable_institutional_filter | false | (from algo.yml) | **true** |
| market_context.gate.enabled | false | (from algo.yml) | **true** |
| entry_quality.enforce | false | (from algo.yml) | **true** |
| entry_quality.min_score | 30 | (from algo.yml) | **68** |

**`selective` tier is very strict** — many gates are active.

### 3.3 Key Config Flags

| Config Path | Default | Purpose |
|---|---|---|
| `paper_trading.enabled` | `true` | Paper mode (default) |
| `paper_trading.balance` | `100000` | Paper balance |
| `dhanhq.enable_orders` | `false` | Live order submission |
| `signals.enable_smc_avrz_permission` | `false` | SMC+AVRZ permission checks |
| `signals.permission_mode` | `lenient` | strict/lenient/bypass |
| `signals.enable_direction_gate` | `true` | Block counter-trend trades |
| `signals.enable_no_trade_engine` | `false` | NoTradeEngine validation |
| `signals.enable_adx_filter` | `true` | ADX threshold enforcement |
| `signals.primary_timeframe` | `1m` | Primary analysis timeframe |
| `trading_time_restrictions.enabled` | `false` | Time-based entry restrictions |
| `midday_guard.enabled` | `true` | Midday quality guard |
| `expiry_week_power_trend.enabled` | `true` | Expiry week power trend |
| `loss_streak_guard.enabled` | `true` | Loss streak cooldown |
| `strike_cooldown_guard.enabled` | `true` | Strike re-entry cooldown |
| `market_context.enabled` | `false` | Market context gate |
| `market_context.gate.enabled` | `false` | Hard market permission gate |
| `risk.daily_limits.enable` | `true` | Daily loss limits |
| `risk.max_daily_profit` | `20000` | Daily profit target |

### 3.4 Environment Variables

| Variable | Effect |
|---|---|
| `LIVE_TRADING=true` | Enables live broker path (GatewayLive). Forces `paper_trading.enabled: false` |
| `LIVE_TRADING=false`/`unset` | Paper mode (default) |
| `SIGNAL_TIER=selective` | Overrides `signals.signal_tier` |
| `FORCE_MARKET_OPEN=true` | Bypasses `market_closed?` check |
| `dhanhq.enable_orders=false` | No real orders (dry-run) |

---

## 4. Market Session Logic

**File:** `app/services/trading_session.rb`

### Trading Hours (IST — Asia/Kolkata)

| Check | Time Range | Method |
|---|---|---|
| Entry allowed | **9:20 AM – 3:15 PM IST** | `TradingSession::Service.entry_allowed?` |
| Market open | **9:20 AM – 3:30 PM IST** | `TradingSession::Service.market_open?` |
| Market closed | Outside 9:20-15:30 | `TradingSession::Service.market_closed?` |
| Force exit | >= 3:15 PM IST | `TradingSession::Service.should_force_exit?` |

```ruby
ENTRY_START_HOUR = 8      # 8:45 AM (with 9:20 check)
ENTRY_START_MINUTE = 45
EXIT_DEADLINE_HOUR = 15   # 3:15 PM
EXIT_DEADLINE_MINUTE = 15
MARKET_CLOSE_HOUR = 16    # 4:00 PM
MARKET_CLOSE_MINUTE = 0
```

### Time Regime Service (S1-S4)

**File:** `app/services/live/time_regime_service.rb`

| Regime | Time Range | Entry Allowed? | Notes |
|---|---|---|---|
| **S1: Open Expansion** | 09:15 – 09:45 | Yes | Strict ADX >= 20, no runners |
| **S2: Trend Continuation** | 09:45 – 11:30 | **YES (BEST ZONE)** | ADX >= 15, runners allowed |
| **S3: Chop/Decay** | 11:30 – 13:45 | **NO** (only if ADX >= 22 + expansion) | Theta dominant — hard block |
| **S4: Close/Gamma** | 13:45 – 15:15 | Yes (ATM only, no runners) | Gamma/IV crush |

**Critical:** If the current time is between 11:30-13:45 IST, **entries will be blocked by TimeRegimeGuard** unless ADX >= 28 (trending_adx_bypass) and expiry power trend is detected.

### Weekend/Holiday Check

`Market::Calendar.trading_day?` checks `config/market_holidays.yml` + weekday.

---

## 5. Position Limits

### 5.1 Index-Level Limits (`config/algo.yml`)

| Index | max_concurrent_per_index | max_trades_per_day | max_same_side |
|---|---|---|---|
| NIFTY | 2 | 2 | 1 |
| BANKNIFTY | 2 | 1 | 1 |
| SENSEX | 2 | 2 | 1 |

### 5.2 Global Limits

- `trade_limits.global_max_trades_per_day: 8`
- `risk.daily_limits.global_limit_pct: 0.04` (4% of capital)

### 5.3 Guards Enforcing Limits

| Guard | File | What it Checks |
|---|---|---|
| **DailyLimitsGuard** | `app/services/entries/guards/daily_limits_guard.rb` | `trade_limits.max_trades_per_day` per index |
| **MaxConcurrentGuard** | `app/services/entries/guards/max_concurrent_guard.rb` | `max_concurrent_per_index` |
| **ExposureGuard** | `app/services/entries/guards/exposure_guard.rb` | Portfolio exposure |
| **DrawdownGuard** | via `Portfolio::DrawdownGuard` | Portfolio-level drawdown |

### 5.4 Capital Allocation

**File:** `app/services/capital/allocator.rb`

- Uses `paper_trading.balance: 100000` by default (paper mode)
- Applies `capital_alloc_pct` (0.30 = 30% of available cash per index)
- Applies `post_1100_multiplier: 0.5` after 11:00 AM IST (halves position size)
- Applies `time_regime_size_multiplier`: S3 → 0.5x, S4 → 0.6x
- Applies `post_peak_size_cut`: gives back 50% of peak → cuts size to 0.5x

---

## 6. Paper vs Live

### 6.1 How Paper/Live is Determined

**File:** `app/lib/algo_config.rb`

```ruby
# Precedence: ENV['LIVE_TRADING'] > config file
# LIVE_TRADING unset/false → paper (default)
# LIVE_TRADING=true → live
config[:paper_trading] = { enabled: !live_trading_env_truthy? }
```

### 6.2 Execution Differences

- **Paper** (`GatewayPaper`): Simulated fills, no broker calls
- **Live** (`GatewayLive`): Real DhanHQ order execution
- Both use the **same entry guards and signal engine**
- `dhanhq.enable_orders: false` in algo.yml → dry-run logging even in "live" mode

### 6.3 Key Config

```yaml
paper_trading:
  enabled: true   # Default for ./bin/dev
  balance: 100000

dhanhq:
  enable_orders: false  # Even in live mode, orders are dry-run unless this is true
```

---

## 7. Logging — Tracing Rejections

### 7.1 Where Entry Rejections Are Logged

**Signal Engine level:**
```ruby
# app/services/signal/engine.rb
Rails.logger.info("[Signal] halt_on_validation_failure BLOCKED #{index_cfg[:key]}: #{validation_result[:reason]}")
Rails.logger.info("[Signal] DirectionGate BLOCKED #{index_cfg[:key]}: Counter-trend trade")
Rails.logger.info("[Signal] PermissionResolver BLOCKED #{index_cfg[:key]} - no trade")
Rails.logger.info("[Signal] SMC Decision BLOCKED #{index_cfg[:key]}: signal=#{final_direction}, smc=#{smc_decision}")
Rails.logger.info("[Signal] NoTradeEngine BLOCKED #{index_cfg[:key]}: score=#{result.score} reasons=...")
Rails.logger.info("[Signal] MarketPermissionGate BLOCKED #{index_cfg[:key]}: #{gate.reason}")
```

**Entry Guard Pipeline level:**
```ruby
# app/services/entries/entry_guard.rb
Observability::StructuredLog.info(
  event: 'entry_blocked',
  payload: {
    service: 'Entries::EntryGuard',
    index_key: index_cfg[:key].to_s,
    symbol: pick[:symbol].to_s,
    reason: reason
  }
)
```

**Each guard blocks with a reason string:**
```ruby
{ blocked: 'loss-streak cooldown triggered for NIFTY' }
{ blocked: 'segment expectancy guard: NIFTY/S2 has shown a negative realized edge' }
{ blocked: 'time regime guard: S3 no-entry window' }
{ blocked: 'banknifty_last_week_guard: not in last week before expiry' }
{ blocked: 'strike cooldown active for NFO_EQ:12345 (840s left)' }
```

### 7.2 How to Enable Debug Logging

```ruby
# In Rails console or config
Rails.logger.level = :debug

# Key debug areas to check:
# - TradingSession::Service.market_closed?
# - Signal::Engine decisions
# - EntryGuardPipeline guard chain
# - PermissionResolver.resolve
# - Trading::SegmentExpectancyAnalyzer
```

### 7.3 Structured Log Events

| Event | Location | Purpose |
|---|---|---|
| `entry_blocked` | `Entries::EntryGuard.try_enter` | Entry rejected by guard |
| `entry_blocked` (stage: market_permission_gate) | `Signal::Engine.evaluate_market_context_for_entry` | Market context gate blocked |

### 7.4 Signal State Tracker

**File:** `app/services/signal/state_tracker.rb`

Tracks signal state per index. `Signal::StateTracker.reset(index_key)` is called on most failures, clearing the state.

---

## 8. Recent Changes on `options-buying` Branch

```
cbbfed9  Enhance error handling in Smc services with detailed logging
7effb5f  Refactor Smc::BiasEngine to improve nil handling for context creation
2f0c80d  Enhance Smc::BiasEngine with nil checks for series and context
6ba7271  Merge remote-tracking branch 'origin/develop' into options-buying
548a2ac  Implement Alpha Engine with API endpoints and job scheduling (#198)
dce7016  Add real ATM IV fetching to comprehensive validation (#197)
af032b8  Options buying (#188)
```

**Key commits:**
- `af032b8` — Options buying implementation
- `dce7016` — Real ATM IV fetching added to validation
- `548a2ac` — Alpha Engine (new strategy layer)
- Recent SMC error handling fixes

---

## 9. Diagnostic Checklist

If no trades are being taken, check each of these in order:

### 9.1 Market Hours
- [ ] Is current time 9:20 AM – 3:15 PM IST?
- [ ] Is today a trading day (not weekend/holiday)?
- [ ] `TradingSession::Service.market_closed?` returns false?

### 9.2 Time Regime
- [ ] Is it S3 (11:30-13:45 IST)? If yes, entries blocked unless ADX >= 28 + expiry power trend
- [ ] `Live::TimeRegimeService.instance.current_regime` returns what?

### 9.3 Signal Tier
- [ ] What `SIGNAL_TIER` env is set? (check `AlgoConfig.fetch[:signals][:signal_tier]`)
- [ ] If `selective` — many strict gates are active

### 9.4 SMC+AVRZ Permission
- [ ] `signals.enable_smc_avrz_permission` — if `true` (default in code, but `false` in algo.yml), PermissionResolver may block
- [ ] `signals.permission_mode` — if `strict`, needs HTF+MTF+LTF candle data
- [ ] Check `Smc::PermissionSnapshot` has candle data for HTF/MTF/LTF

### 9.5 Entry Guards (run through all 22)
- [ ] LossStreakGuard: Any consecutive losses today triggering 30min cooldown?
- [ ] StrikeCooldownGuard: Same contract traded and stopped out within 20min?
- [ ] SegmentExpectancyGuard: Negative edge for (index, regime) segment?
- [ ] DailyLimitsGuard: Daily trade limit already reached?
- [ ] MaxConcurrentGuard: Already 2 positions in this index?
- [ ] TimeRegimeGuard: Currently in S3 (11:30-13:45)?
- [ ] BankniftyLastWeekGuard: Is BANKNIFTY expiry more than 7 days away?
- [ ] DrawdownGuard: Is portfolio drawdown guard active?

### 9.6 Signal Engine Validation
- [ ] ADX >= 15? (or >= 25 in conservative mode)
- [ ] Supertrend trend != :none?
- [ ] Regime not RANGING/CHOPPY (DirectionGate)?
- [ ] IV rank within bounds (0.1-0.8 in balanced mode)?
- [ ] RSI not overbought (>78 for CE) or oversold (<22 for PE)?
- [ ] NoTradeEngine passing (if enabled)?
- [ ] Strike selection returning picks?

### 9.7 Capital
- [ ] Available cash > 0 in wallet snapshot?
- [ ] `Capital::Allocator.available_cash` returns what?
- [ ] Post-1100 multiplier halving size to 0.5x after 11:00 AM?

### 9.8 Logging grep commands

```bash
# Find all entry blocks
grep -r "BLOCKED\|entry_blocked\|blocked:" app/services/signal/ app/services/entries/ --include="*.rb"

# Find TimeRegime blocks
grep -r "time regime\|S3\|S4\|S2" app/services/entries/guards/time_regime_guard.rb

# Find PermissionResolver blocks
grep -r "PermissionResolver BLOCKED\|permission_mode\|enable_smc_avrz" app/services/ --include="*.rb"

# Find all guard blocks
grep -r "blocked:" app/services/entries/guards/ --include="*.rb"

# Check market session
grep -r "market_closed\|market_open" app/services/trading_session.rb
```

---

## 10. Most Likely Culprits

Based on code analysis, the most probable reasons for no trades:

1. **TimeRegimeGuard (S3 block)** — If it's 11:30-13:45 IST, entries are hard-blocked. ADX must be >= 28 AND expiry power trend detected to bypass.

2. **PermissionResolver in strict mode** — `permission_mode: lenient` in algo.yml but `selective` tier may override to `strict`. If SMC candle data is missing for HTF/MTF/LTF, returns `:blocked`.

3. **DirectionGate** — RANGING or CHOPPY regime blocks both CE and PE trades.

4. **BANKNIFTYLastWeekGuard** — BANKNIFTY only trades in last 7 calendar days before monthly expiry. If expiry is more than 7 days away, all BANKNIFTY entries are blocked.

5. **LossStreakGuard / StrikeCooldownGuard** — If recent losses or re-entry cooldowns are active.

6. **Daily limits** — `max_trades_per_day: 1` for BANKNIFTY, `2` for NIFTY/SENSEX — if limit reached, no new entries.

7. **NoTradeEngine blocking** — If `enable_no_trade_engine: true` (it defaults to `false` in algo.yml, but `selective` tier sets it to `true`).

8. **Select tier's strict validation** — `min_confidence: 72`, `halt_on_validation_failure: true`, `market_context.gate.enabled: true` — many stacked strict conditions.

---

## Key Files Reference

| Purpose | File |
|---|---|
| Config | `config/algo.yml`, `config/signal_tier_presets.yml` |
| Config loader | `app/lib/algo_config.rb` |
| Signal engine | `app/services/signal/engine.rb` |
| Entry guard orchestrator | `app/services/entries/entry_guard.rb` |
| Entry guard pipeline | `app/services/entries/entry_guard_pipeline.rb` |
| All 22 guards | `app/services/entries/guards/*.rb` |
| Permission resolver | `app/services/trading/permission_resolver.rb` |
| Market session | `app/services/trading_session.rb` |
| Time regimes | `app/services/live/time_regime_service.rb` |
| Capital allocation | `app/services/capital/allocator.rb` |
| Daily limits | `app/services/live/daily_limits.rb` |
| No-trade engine | `app/services/entries/no_trade_engine.rb` |
| Entry quality filter | `app/services/signal/entry_quality_filter.rb` |
| Trading signal model | `app/models/trading_signal.rb` |
| Position tracker | `app/models/position_tracker.rb` |
| Bootstrap (service startup) | `lib/trading_system/bootstrap.rb` |
| Supervisor (daemon) | `lib/trading_system/supervisor.rb` |