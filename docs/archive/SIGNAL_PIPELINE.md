# Signal Generation Pipeline

Complete reference for the signal pipeline in `algo_scalper_api`. Covers every layer from market data ingestion through to order placement, what is fully built vs. optional, and how to configure each layer.

---

## Overview

The pipeline has five quality layers. Each layer is independently togglable. You can run with just Layer 1 (pure Supertrend) or stack all five for a professional-grade setup.

```
Market Ticks (DhanHQ WebSocket)
        │
        ▼
┌───────────────────┐
│  Layer 1          │  Direction Bias
│  SMC Scanner      │  Runs every 5 min, 60m→15m→5m analysis
│  DirectionGate    │  Blocks trades against regime
└────────┬──────────┘
         │
         ▼
┌───────────────────┐
│  Layer 2          │  Signal Generation
│  1m Supertrend    │  Primary trigger (flip = directional signal)
│  ADX Filter       │  Require momentum (ADX ≥ threshold)
│  5m Confirmation  │  Both timeframes must agree
└────────┬──────────┘
         │
         ▼
┌───────────────────┐
│  Layer 3          │  Entry Quality Gate
│  NoTradeEngine    │  16-factor scoring (VWAP, IV, spread, etc.)
│  AVRZ             │  Volume rejection zone timing
└────────┬──────────┘
         │
         ▼
┌───────────────────┐
│  Layer 4          │  Entry Structure
│  BOS State Machine│  Wait for structure → pullback → continuation
│  (or immediate)   │  Supertrend mode enters immediately
└────────┬──────────┘
         │
         ▼
┌───────────────────┐
│  Layer 5          │  Capital Permission
│  SMC+AVRZ Tiers  │  Maps structure quality → lot size
└────────┬──────────┘
         │
         ▼
┌───────────────────┐
│  EntryGuard       │  Final gate: cooldown, daily limits,
│                   │  circuit breaker, duplicate check
└────────┬──────────┘
         │
         ▼
  Options Chain Analysis → Capital Allocation → Order Execution
```

---

## Layer 1 — Direction Bias

### SMC Scanner

**File:** `app/services/smc/scanner.rb`, `smc/bias_engine.rb`
**Runs:** Every 5 minutes on NIFTY, BANKNIFTY, SENSEX
**Output:** `call / put / no_trade` per index, cached between runs

The BiasEngine validates a 3-timeframe cascade before producing a signal:

| Timeframe | Role        | Candles analysed |
|-----------|-------------|-----------------|
| 60m (HTF) | Trend bias  | 60              |
| 15m (MTF) | Structure   | 100             |
| 5m (LTF)  | Entry signal| 150             |

HTF bias must hold before MTF structure is checked. MTF must confirm before LTF entry signal is accepted.

**Detectors used by BiasEngine:**

| Detector | What it finds |
|---|---|
| `StructureDetector` | Trend (bullish/bearish/range), BOS/CHOCH status |
| `InternalStructure` | Liquidity sweeps, order block detection |
| `OrderBlocks` | Premium/discount zones, block clustering |
| `LiquidityDetector` | Liquidity pools, trap detection |
| `SwingStructure` | Multi-swing analysis |
| `FvgDetector` | Fair Value Gaps |
| `PremiumDiscountDetector` | Zone mapping |

**Config:**
```yaml
signals:
  enable_smc_avrz_permission: true      # enables the scanner
  enable_smc_decision_alignment: true   # signal direction must match SMC output
```

### DirectionGate

**File:** `app/services/trading/direction_gate.rb`

Hard-blocks entries that go against the market regime. No overrides.

| Regime   | CE entry | PE entry |
|----------|----------|----------|
| Bullish  | ✅ Allow  | ❌ Block  |
| Bearish  | ❌ Block  | ✅ Allow  |
| Neutral  | ❌ Block  | ❌ Block  |

**Config:**
```yaml
signals:
  enable_direction_gate: true
```

---

## Layer 2 — Signal Generation

### 1m Supertrend (Primary Trigger)

**File:** `app/services/signal/engine.rb`
**Default params:** `period: 10, base_multiplier: 1.5`

A Supertrend flip on the 1-minute candle is the primary entry trigger. Direction: flip below band → bearish (PE), flip above band → bullish (CE).

**Config:**
```yaml
signals:
  enable_supertrend_signal: true
  primary_timeframe: "1m"
  supertrend:
    period: 10
    base_multiplier: 1.5
  use_optimized_params: false   # true = load best params from BestIndicatorParam DB table
```

### ADX Filter

**File:** `app/services/indicators/adx.rb`

Skips signals when ADX is below threshold — avoids entering during low-momentum, choppy price action.

**Default thresholds:**

| Index     | Min ADX (primary 1m) | Min ADX (confirmation 5m) |
|-----------|----------------------|--------------------------|
| NIFTY     | 18                   | 18                       |
| BANKNIFTY | 18                   | 18                       |
| SENSEX    | 18                   | 18                       |

**Config:**
```yaml
signals:
  enable_adx_filter: true
  adx:
    min_strength: 18
    confirmation_min_strength: 18
```

Per-index overrides can be set under each index's `adx_thresholds:` block.

### 5m Confirmation Timeframe

**File:** `app/services/signal/engine.rb`

Both 1m and 5m Supertrend must agree on direction before the signal is valid. Reduces false signals at the cost of slightly later entries.

**Config:**
```yaml
signals:
  enable_confirmation_timeframe: true
  confirmation_timeframe: "5m"
```

---

## Layer 3 — Entry Quality Gate

### NoTradeEngine

**File:** `app/services/entries/no_trade_engine.rb`

Scores 16 factors. If total score ≥ 3.0, the trade is blocked. Each factor is weighted and index-specific.

| Factor | Weight | NIFTY threshold | SENSEX threshold | BANKNIFTY threshold |
|---|---|---|---|---|
| ADX Weakness (hard) | 1.0 | < 14 | < 12 | < 16 |
| ADX Weakness (soft) | 0.5 | 14–16 | 12–14 | 16–18 |
| DI Overlap (hard) | 1.0 | < 2.0 | < 1.5 | < 2.5 |
| DI Overlap (soft) | 0.5 | 2.0–3.0 | 1.5–2.5 | 2.5–3.5 |
| No BOS last 10m | 1.0 | — | — | — |
| Inside opposite OB | 1.0 | — | — | — |
| Inside opposing FVG | 1.0 | — | — | — |
| VWAP chop | 1.0 | ±0.08% for 3+ candles | — | — |
| Near VWAP magnet | 0.5 | ±0.08% zone | — | — |
| Trapped between VWAP/AVWAP | 1.0 | — | — | — |
| Low candle range (hard) | 1.0 | < 0.06% | < 0.04% | < 0.08% |
| Low candle range (soft) | 0.5 | 0.06–0.09% | 0.04–0.07% | 0.08–0.12% |
| ATR downtrend | 1.0 | ≥ 5 bars | ≥ 3 bars | ≥ 5 bars |
| OI trap (CE↑ PE↑ range low) | 1.0 | — | — | — |
| Low IV (hard) | 1.0 | < 9 | < 11 | < 13 |
| Low IV (soft) | 0.5 | 9–11 | 11–13 | 13–15 |
| IV falling | 0.5 | declining | — | — |
| Wide spread | 1.0 | > ₹3 | > ₹5 | > ₹4 |
| High wick ratio (hard) | 1.0 | > 2.2 | > 2.5 | > 2.3 |
| High wick ratio (soft) | 0.5 | 2.0–2.2 | 2.2–2.5 | 2.1–2.3 |
| Restricted time window | 1.0 | 09:15–09:18, 11:20–13:30, 15:05+ | — | — |

**Config:**
```yaml
signals:
  enable_no_trade_engine: true
```

### AVRZ — Absorption Volume Rejection Zone

**File:** `app/services/avrz/detector.rb`

LTF timing confirmation. Detects when price has genuinely rejected from a level (wick + volume) before entering. Used only for timing, never for HTF/MTF bias.

Conditions checked:
- Upper/lower wick ratio ≥ 1.8× body
- Relative volume ≥ 1.5× 20-candle average
- Close must be away from the wick extreme (rejection confirmed)

**Config:**
```yaml
signals:
  enable_smc_avrz_permission: true   # AVRZ is part of the permission system
```

---

## Layer 4 — Entry Structure

### Mode A: Immediate (current default)

```yaml
signals:
  entry_strategy:
    primary: supertrend
```

Enters as soon as the Supertrend flips and all upstream layers pass. No waiting for pullback.

### Mode B: BOS Pullback State Machine

```yaml
signals:
  entry_strategy:
    primary: bos_pullback
```

**File:** `app/services/entries/bos_entry_engine.rb`, `entries/bos_extractor.rb`

Waits for a proper structural setup before entering. Three states must complete in sequence:

```
State 1: BOS_CONFIRMED
  - Swing high/low broken by a close (lookback: 5 candles)
  - BOS must be ≤ 8 candles old (BOS_MAX_AGE_CANDLES)
  - Creates BOS ID, stores to Redis (2-hour TTL)
        │
        ▼
State 2: PULLBACK
  - Price retraces ≥ 35% back toward BOS origin
  - Opposite candle close required
  - BOS origin level must not be broken
  - Pullback must complete within 5 candles
        │
        ▼
State 3: CONTINUATION_TRIGGERED
  - Close breaks pullback high (for bearish: breaks pullback low)
  - Candle body position ≥ 60% above pullback level
  - HTF BOS must align (≤ 20 candles old)
  - → EntryGuard called
```

State is stored per-index in Redis. If BOS goes stale (> 8 candles), state resets and waits for a fresh BOS.

**BosExtractor** (`entries/bos_extractor.rb`) handles the structural detection:
- Identifies confirmed swing highs and lows
- Confirms BOS when price closes beyond the swing level
- Returns: `direction`, `broken_swing`, `origin_swing`, `confirmed_index`, `confirmed_at`

---

## Layer 5 — Capital Permission

### SMC + AVRZ Permission Tiers

**File:** `app/services/smc/smc_permission_resolver.rb`

Maps the quality of the current SMC structure + AVRZ state to a capital deployment tier. EntryGuard uses the tier to determine lot size.

| Permission | Trigger conditions | Capital |
|---|---|---|
| `:blocked` | SMC neutral, range without displacement, trend without BOS | 0 — no entry |
| `:execution_only` | AVRZ compressed + trend valid but no displacement/liquidity resolved | 1 lot max |
| `:scale_ready` | AVRZ expanding_early + BOS + displacement + no active trap | 2+ lots |
| `:full_deploy` | AVRZ expanding + trap resolved + clean BOS follow-through + displacement | Full allocation |

**Permission modes:**

| Mode | Behaviour |
|---|---|
| `strict` | All conditions required. Maximum capital protection. |
| `lenient` | Allows range/trend without BOS if displacement is present. |
| `bypass` | Permission always returns `:scale_ready`. Testing only. |

**Config:**
```yaml
signals:
  enable_smc_avrz_permission: true
  permission_mode: strict            # strict | lenient | bypass
```

---

## EntryGuard (Final Gate)

**File:** `app/services/entries/entry_guard.rb`

Runs after all signal layers pass. Checks in order:

1. **Circuit breaker** — if tripped, all entries blocked globally
2. **Duplicate detection** — same index + same direction already has an active position
3. **Cooldown** — minimum time since last entry per index (default 180s)
4. **Daily limits** — max trades per index per day
5. **Feed health** — last tick must be < 30s old
6. **Capital sizing** — lot count from `capital/` allocator, must be ≥ 1
7. **Premium band** — LTP must be within configured ATM band
8. **Time regime** — if time regimes enabled, session-specific rules apply

---

## Time Regimes (Session-Aware Rules)

**File:** `config/algo.yml` → `time_regimes:`
**Status:** Disabled by default (`enabled: false`)

Divides the trading day into four sessions, each with different SL/TP multipliers and entry rules:

| Session | Time | Character | Allow entries |
|---|---|---|---|
| S1 Open Expansion | 09:15–09:45 | Delta explodes, fake breakouts, IV spikes | Yes, with wide SL |
| S2 Trend Continuation | 09:45–11:30 | Best zone. Stable delta, steady IV | Yes — primary zone |
| S3 Chop/Decay | 11:30–13:45 | Lunch. Theta accelerates, VWAP chop | Mostly blocked |
| S4 Close/Gamma | 13:45–15:15 | Gamma crush. Scalp exits only | Restricted |

**Config:**
```yaml
time_regimes:
  enabled: true
```

---

## Recommended Configurations

### Minimal filter (conservative testing)
Keep immediate entries but block the worst conditions:

```yaml
signals:
  entry_strategy:
    primary: supertrend
  enable_adx_filter: true           # no low-momentum entries
  enable_direction_gate: true       # no PE in bull, no CE in bear
  enable_no_trade_engine: true      # block chop, low IV, lunch window
```

### Standard (balanced)
Add structural entry and SMC bias:

```yaml
signals:
  entry_strategy:
    primary: supertrend             # immediate entry after structure check
  enable_adx_filter: true
  enable_direction_gate: true
  enable_no_trade_engine: true
  enable_smc_avrz_permission: true
  enable_smc_decision_alignment: true
  permission_mode: lenient          # start lenient, tighten when comfortable
```

### Full professional pipeline
All layers active. BOS pullback mode for structural entries:

```yaml
signals:
  entry_strategy:
    primary: bos_pullback
  enable_adx_filter: true
  enable_confirmation_timeframe: true
  enable_direction_gate: true
  enable_no_trade_engine: true
  enable_smc_avrz_permission: true
  enable_smc_decision_alignment: true
  permission_mode: strict
time_regimes:
  enabled: true
```

---

## Running Paper Mode

Start the daemon (can be started before market open):

```bash
ENABLE_TRADING_SERVICES=true FORCE_MARKET_OPEN=true bundle exec rake trading:daemon >> /tmp/trading_daemon.log 2>&1 &
```

`FORCE_MARKET_OPEN=true` makes the daemon start all services regardless of current time. The signal engine still respects real market hours (9:15–15:30 IST) and will not fire signals outside those windows.

Monitor:

```bash
tail -f log/development.log | grep -E "\[Signal\]|\[EntryGuard\]|\[GatewayPaper\]|\[ExitEngine\]|\[SMC\]|\[NoTrade\]"
```

Check positions:

```bash
bundle exec rails runner "PositionTracker.active.each { |t| puts \"#{t.symbol} | entry: #{t.entry_price} | pnl: #{t.last_pnl_rupees}\" }"
```

Stop:

```bash
pkill -TERM -f "rake trading"
```

---

## Key Source Files

| File | Purpose |
|---|---|
| `config/algo.yml` | All feature flags and thresholds |
| `app/services/signal/engine.rb` | Main signal orchestrator |
| `app/services/signal/scheduler.rb` | Per-minute signal loop |
| `app/services/smc/scanner.rb` | SMC background scanner |
| `app/services/smc/bias_engine.rb` | 3-TF SMC analysis |
| `app/services/smc/smc_permission_resolver.rb` | Capital tier mapping |
| `app/services/entries/bos_entry_engine.rb` | BOS pullback state machine |
| `app/services/entries/bos_extractor.rb` | Swing/BOS detection |
| `app/services/entries/no_trade_engine.rb` | 16-factor quality gate |
| `app/services/entries/entry_guard.rb` | Final entry gate |
| `app/services/avrz/detector.rb` | Volume rejection zone |
| `app/services/trading/direction_gate.rb` | Regime filter |
| `app/services/risk/rules/time_stop_rule.rb` | Time-based exit |
| `app/services/live/risk_manager_service/` | Exit enforcement |
| `app/services/live/exit_engine.rb` | Exit execution |
