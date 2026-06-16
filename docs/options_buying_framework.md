# Options Buying Framework

Single reference for **intraday scalper** (active default) and **positional Ep-92** (carry-gated reference).

Config: `options_buying.mode` in [`config/algo.yml`](../config/algo.yml).

---

## Mode Matrix

| Rule | Intraday Scalper (default) | Positional (Ep-92, carry only) |
| :--- | :--- | :--- |
| Product | Naked `INTRADAY` CE/PE | Vertical spreads (documented; not v1 code) |
| OI breakout timing | 1m close + volume spike + OI unwind | 15–20 min hold above high-OI strike |
| ATR exhaustion (≥80% range) | **Removed** — blocks outlier trend days | **Removed** |
| ATR compression (&lt;30% range) | Soft **arm** for breakout (Redis) | Hard **gate** when carry allowed |
| R:R | ~1:3 premium (15% SL / 45% TP) | 1:1 capped spread math (reference) |
| Overnight carry | Never | Only when `CarryPolicy.carry_allowed?` (DTE ≥ 1, not expiry day) |

> **Positional rules activate only when** `options_buying.mode: positional`, `positional.enabled: true`, and the series can be carried to the next session (not expiry day).

---

## Intraday Scalper Principles (Active)

* **Convexity:** Buy naked options; manage risk with premium stops, not short legs that cap gamma.
* **Fast squeeze capture:** 1-minute bar close above chain resistance + volume &gt; 2× average + negative OI delta (short-covering).
* **Compression arms setups:** Session range &lt; 30% of daily ATR sets `compression_arm` in Redis; does not block trend days.
* **Chain radar:** 09:16 + every 30m — liquid ATM-layer strikes (delta 0.45–0.55), max call-OI resistance.
* **Greeks & liquidity:** Filter wide bid-ask spreads (&gt; 1.5% of premium) before entry.
* **No averaging down:** Enforced by exit engine and guard pipeline.

### Services

| Component | Path |
| :--- | :--- |
| Chain radar | `app/services/options_buying/chain_radar.rb` |
| Breakout watcher | `app/services/options_buying/breakout_watcher.rb` |
| Breakout evaluator | `app/services/options_buying/breakout_evaluator.rb` |
| Entry guards | `CompressionSetupGuard`, `BreakoutReadyGuard`, `BidAskSpreadGuard`, `RsiBiasGuard` |

---

## Positional Reference (Ep-92 — Carry-Gated)

Source: Big Bull Series Ep-92 (Stock Pathshala). **Not the default execution path** for `algo_scalper_api`.

### Capital & Mindset

* Risk 2–3% per trade; survive 30–50 consecutive losses.
* Never average down losing option positions.

### Dual Confirmation

* **Charts:** RSI divergence (e.g. higher high in price, lower high in RSI).
* **Chain:** Highest call OI = resistance; highest put OI = support.
* **Trigger:** Spot holds above resistance for **15–20 minutes** before positional entry.

### Vertical Spreads (Multi-Day Holds)

Bull call spread: buy ATM call, sell OTM call. Caps loss and profit (~1:1 on spread width). Doubles friction for intraday — **not used** in scalper mode.

### When Positional Rules Apply in Code

* `CompressionSetupGuard` blocks entries until compressed **only** when positional + carry allowed.
* Spread orchestrator and 15–20 min OI timer: documented, deferred to v2.

---

## Shared Rules

* Kill zones: opening drive 09:15–10:30, closing repricing 14:00–15:15 (see workspace trading rules).
* Strike preference: ATM or slight ITM (delta ≈ 0.45–0.55).
* Expiry day: no fresh entries after 13:00 when `options_buying.expiry_day.lockout_after` is set.
* Earliest entry: 09:30 (`Live::TimeRegimeService`).

---

## Related Docs

* [`options_buying_implementation_plan.md`](options_buying_implementation_plan.md) — gap analysis and file map
* [`options_buying_automation_master_plan.md`](options_buying_automation_master_plan.md) — phases and architecture
