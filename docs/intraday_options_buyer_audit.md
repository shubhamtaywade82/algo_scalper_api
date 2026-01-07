# Intraday Options Buyer Minimal Layer Audit (Scalping API)

## Purpose

This is a brutally minimal audit of the current scalping API against the
"intraday options buyer only" execution model.

**Goal:** identify what is currently incorrect (extra noise) and what is missing
(mandatory gates) so the system answers only the required questions:

1. Is structure aligned (15m → 5m)?
2. Is expansion starting now?
3. Is this a trap resolution, not the trap?
4. Is the session favorable?
5. Will this strike respond fast enough?
6. Is expected move > theta decay?
7. Do I have a clean invalidation?

If any answer is "no" → **block the trade**.

---

## The Target Model (What The System Must Be)

### Priority 1 — Price & Structure (non-negotiable)

- **15m market context:** determine **trend vs range** using only:
  - HH–HL / LL–LH (trend)
  - Failed HH/LL (transition)
  - Overlapping candles (range/chop)
- **5m alignment:** 15m bias must be confirmed by 5m structure:
  - Bullish bias → 5m higher lows + BOS/CHOCH alignment
  - Bearish bias → 5m lower highs + BOS/CHOCH alignment
- **1m:** entry trigger + stop placement + fake move detection only.
  - No "trend scoring" or indicator analysis on 1m.

### Priority 2 — Expansion & Momentum (options-specific)

- Candle quality and follow-through.
- ATR/range expansion vs session median.
  - Direction without momentum → theta bleed.
  - Momentum without structure → trap.

### Priority 3 — Time (edge layer)

- Favourable session windows and explicit avoid windows.
- No trading randomly all day.

### Priority 4 — Options chain (filter, not signal)

- Strike selection:
  - **ATM or ±1 strike only**
  - Tight spread (non-negotiable)
  - Liquidity filter
- OI is context only (crowded/ignored), never an entry trigger.

### Priority 5 — Greeks (filters only)

- Delta target band for intraday buying:
  - Preferred: **0.40–0.55**
  - Avoid: < 0.30 (theta dominates) and > 0.65 (slow/expensive)
- Theta:
  - Must compare expected move vs decay, especially post 13:30 and on expiry.

### Priority 6 — Traps & Liquidity

- Explicit fake breakout/breakdown detection:
  - "Never trade the first move; trade the failure."

### Priority 7 — Payoff & Risk

- Expected move vs premium sensitivity must justify at least ~1.5–2× risk.
- Exit logic must exist and be enforced:
  - Hard SL (% premium)
  - Profit lock (₹-based)
  - Trailing (structure/ATR)
  - Time stop

---

## Current Implementation Audit (What Is Not Correct)

This section maps each target layer to the current code, highlighting issues.

### 1) Priority 1 violation: regime/structure is not the primary gate

**Observed behavior**

- `Signal::Engine` is indicator-led (Supertrend + ADX + optional "Index TA").
- It does not explicitly decide "trend vs range" from 15m structure.
- 15m→5m structure alignment is not enforced as the primary gate.

**Where**

- `app/services/signal/engine.rb`
  - Index TA gate: lines ~23–62
  - Supertrend + ADX decision: lines ~100–119 and ~279–321
  - Direction decision method: lines ~763–795

**Why it is incorrect**

If "trend vs range" is unknown, an options buyer must not trade. Current logic
can still generate trades from indicator states even when structure is unclear.

---

### 2) Priority 3 issue: time-of-day edge is inconsistent (one check is broken)

**Observed behavior**

- `Signal::Engine#validate_market_timing` returns early and skips its own rules.
- Entry gating uses `Live::TimeRegimeService`, but it is not aligned to the
  required windows, and failures are fail-open.
- The system explicitly does not cap trade frequency (can overtrade chop).

**Where**

- `app/services/signal/engine.rb`
  - `validate_market_timing`: lines ~599–627 (early return makes later code dead)
- `app/services/live/time_regime_service.rb`
  - regime definitions and no-new-trades cutoff
- `app/services/entries/entry_guard.rb`
  - `time_regime_allows_entry?`: lines ~394–443 (fail-open on error)
  - daily limits ignoring trade frequency: lines ~453–487

**Why it is incorrect**

Time is an edge. The system should hard-block unfavourable windows and should
not fail-open when the time filter errors.

---

### 3) Priority 1 violation: 1m is used for "analysis" in scoring

**Observed behavior**

`Signal::TrendScorer` defaults to `primary_tf: '1m'` and includes RSI + MACD +
ADX + Supertrend in its scoring.

**Where**

- `app/services/signal/trend_scorer.rb`
  - defaults: lines ~14–16
  - indicator score: lines ~170–233

**Why it is incorrect**

1m is only for entry precision, not for multi-indicator analysis.

---

### 4) Priority 4 + 5 violations: strike selection is too permissive

**Observed behavior**

- Strike selection can drift to **2 OTM** based on trend score.
- Delta thresholds allow **very low delta** (0.08–0.15), which is theta-heavy.

**Where**

- `app/services/options/strike_selector.rb`
  - allows 2OTM: lines ~12–16 and ~112–125
- `app/services/options/chain_analyzer.rb`
  - targets ATM+1/ATM+2: lines ~685–699
  - min delta now allows 0.08–0.15: lines ~937–946

**Why it is incorrect**

For intraday options buying, the option must respond immediately.
Low delta (< 0.30) options are theta-dominated; 2OTM selection is typically
too far and increases decay + slippage risk.

---

### 5) Priority 4 violation: OI is used as an entry trigger

**Observed behavior**

There is a signal engine that creates a signal purely from OI increasing plus
price up ("OI buildup").

**Where**

- `app/services/signal/engines/open_interest_buying_engine.rb`: lines ~5–29

**Why it is incorrect**

OI is context-only (crowding/avoid zones), not a direction or entry trigger.

---

### 6) Priority 5 missing: theta decay vs expected move is not implemented

**Observed behavior**

- The system has a "theta risk" check, but it is time-based only.
- There is no expected move vs theta decay computation using chain Greeks.

**Where**

- `app/services/signal/engine.rb`
  - `validate_theta_risk`: lines ~527–545

**Why it is incorrect**

Options buying requires verifying that expected move beats decay, especially
post 13:30 and on expiry days.

---

### 7) Priority 6 missing: trap-resolution logic is not enforced

**Observed behavior**

- `Entries::StructureDetector` can detect BOS as a boolean.
- There is no explicit "first breakout failure" gate that blocks first moves
  and only permits trap resolution entries.

**Where**

- `app/services/entries/structure_detector.rb`: BOS and pattern utilities

**Also incorrect/inconsistent**

`Signal::DirectionValidator` references methods that do not exist in
`StructureDetector` (`bos_direction`, `choch?`). That implies the validator is
not safely usable as-is even if wired into the engine.

- `app/services/signal/direction_validator.rb`: lines ~178–208
- `app/services/entries/structure_detector.rb`: no corresponding methods exist

---

### 8) Production hygiene issue: debug prints in trading path

**Observed behavior**

`pp` is used in the strategy analysis path, which is not acceptable in a live
trading loop.

**Where**

- `app/services/signal/engine.rb`: lines ~706–707

---

## Minimal Remediation Checklist (Noise Removal + Missing Gates)

This is the smallest set of changes needed to make the system match the
intraday options buyer model.

### A) Remove noise (disable or delete)

- **Disable OI as signal**
  - Stop using `Signal::Engines::OpenInterestBuyingEngine` for entries.
- **Avoid 1m indicator analysis**
  - Do not use `Signal::TrendScorer` on 1m as a decision engine.
  - If it stays, limit it to PA-only (structure + expansion) and keep 1m only
    for entry mechanics.
- **Stop 2OTM selection**
  - Restrict strike selection to ATM or ±1 only.
- **Raise delta minimum**
  - Replace 0.08–0.15 min-delta logic with a delta band gate that matches
    0.35–0.55 preferred range.

### B) Add missing mandatory gates

- **15m regime classifier**
  - Must output: `trend`, `range`, `transition`.
  - Block if not `trend` or a valid `transition` that supports expansion.
- **5m structure alignment**
  - Enforce BOS/CHOCH alignment with 15m bias.
- **Expansion gate**
  - Candle quality + follow-through check.
  - ATR / session-range expansion vs median.
- **Trap-resolution gate**
  - Detect breakout failure and only allow the "failure entry", not the first
    breakout candle.
- **Expected move vs theta**
  - Estimate expected move from 15m/5m ATR and compare to:
    - premium risk (planned SL)
    - theta decay over the expected holding window
  - Hard block if expected move does not clear decay + spread.

### C) Fix time layer

- Fix `Signal::Engine#validate_market_timing` (remove early return).
- Align regimes/windows to the desired session rules and block "dead zones".
- Change fail-open behavior on time regime errors to fail-closed (block entry)
  unless explicitly overridden for safety.

---

## What To Treat As Correct / Reusable

- `Live::TimeRegimeService` concept is correct (time-aware rule system), but
  needs window alignment and stricter failure behavior.
- `Live::UnifiedExitChecker` provides a single exit path with stop loss, take
  profit, trailing, and time-based exit.
  - This is aligned with "exit logic > entry logic", but the entry-side still
    needs expected-move validation before taking risk.

---

## Quick Summary (One Screen)

- **Indicator-led signals** still drive decisions → wrong priority order.
- **Market timing validation is broken** in signal generation.
- **1m analysis exists** via TrendScorer defaults → violates entry-only 1m rule.
- **Strike selection allows 2OTM** and **delta too low** → theta traps.
- **OI is used as entry trigger** → explicitly disallowed.
- **Theta vs expected move** is not implemented.
- **Trap resolution gate** is missing.
- **Debug prints (`pp`)** exist in trading path.

