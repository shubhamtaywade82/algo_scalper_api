# Peak-Capture Exit Validation (Offline) — Design

**Date:** 2026-07-14
**Status:** Approved (design), pending implementation plan

## Problem

First-15m ORB option-buying research (V4, 11 trades over 10 days) shows the ATM premium peaked on every trade and then gave back 28–99.9% of the peak before any simulated exit fired. 8 of 11 trades retained 0% of peak profit; two trades round-tripped a +23% and +17% peak into −20% and −53% realized losses. Time-to-peak is unpredictable (1–285 min), so the fix is not better timing — it is a faster decay detector plus a ratchet floor so a peak can never fully round-trip.

The research simulated 7 exit strategies but never simulated the two live engines purpose-built for peak capture: `Orders::MfeExitEngine` (35% retrace-from-MFE) and `Orders::GammaTrailingEngine` (4-state velocity machine). Both are LOCKED production infra — this work validates their logic offline in the research sim; it does not modify them.

## Scope decisions (user-confirmed)

- **Offline validation only.** No live exit logic changes in this effort. Wiring a winner into the live alpha layer is a separate future phase, gated on the verdict rule below.
- **Edit research files directly** (`app/services/research/exit_capture_analyzer.rb` and friends), accepting collision risk with the concurrent session that authored them.
- **Extend the data window to max available** before comparing. No full feature-pipeline fix (ATR/ADX/gap columns) in this pass — exits only need the premium and underlying series, which exist.

## New exit strategies (added to `ExitCaptureAnalyzer` registry)

1. **`mfe_retrace_35`** — mirror of live `Orders::MfeExitEngine`: stop = peak − 0.35 × (peak − entry), active once MFE > 0. Variants `mfe_retrace_25` and `mfe_retrace_50` for the sensitivity curve.
2. **`gamma_state`** — mirror of live `Orders::GammaTrailingEngine`: survival (12% SL) → trend (20% gap from peak) → gamma-expansion (loosen to 35%) → exhaustion (tighten to 10%), state chosen from premium velocity and acceleration over a 3-candle window.
3. **`velocity_ratchet`** (new):
   - Arms at MFE ≥ 10%.
   - Floor = max(entry × 1.02, peak − gap); gap starts at 35% of MFE and tightens linearly toward 15% as 1-min premium velocity decays to ≤ 0.
   - Hard exit: premium velocity negative for 3 consecutive minutes AND premium below its EMA5.
   - Floor only ever rises (ratchet) — a captured peak cannot become a realized loss once armed.

**Deliberately skipped:** partial scale-out (50% at stall, trail rest) — requires partial-exit support in the simulator; add later only if all full-exit strategies disappoint.

## Data extension

- Extend `Research::MarketDataFetcher` from ~10 days to max available: persisted `candles` table first, then Dhan intraday API for underlying 1-min bars, and `ExpiredOptionsData` (rollingoption) for option bars on expired weeklies. Target 60–100+ trading days; use whatever exists.
- Days with missing option bars are skipped and counted; the report states "N of M days simulated". No silent truncation.
- **Synthetic-fallback guard:** if `market_data_fetcher.rb`'s synthetic-data fallback fires, abort the run with a loud error instead of producing results. (This fallback is the likely cause of the constant gap/ATR/body-ratio columns in the last run.)

## Comparison and validation

- **Primary metric: retention ratio** (realized gain ÷ peak MFE). Secondary: capture efficiency, expectancy, Sharpe, profit factor.
- Reuse `StatisticalValidator` as-is: chronological walk-forward IS (60%) / OOS (40%) split plus 1000× bootstrap 95% CIs, applied to the new strategies identically to the existing 7.
- **Verdict rule (stated up front):** a strategy wins only if its OOS retention ratio beats the best existing exit AND its bootstrap 95% CI lower bound on return is above 0%. Otherwise verdict = no edge; nothing gets wired into live.

## Output

Extended exit-performance matrix (10 strategies side by side) in the existing JSON/CSV reports plus the `docs/research/` markdown, with per-regime breakdown where the replay provides it.

## Testing

Extend the research spec with synthetic premium series shaped like the observed failures:

- Fast spike → full round-trip (the 06-30 / 07-07b shape): `velocity_ratchet` must exit within ~5 minutes of peak; `mfe_retrace_35` must exit at exactly peak − 0.35 × MFE.
- Slow grind → late peak (the 07-13 shape): ratchet floor must track the rising peak without premature exit.
- Each new strategy asserted to fire at the expected candle index.

## Non-goals

- No changes to `Orders::MfeExitEngine`, `Orders::GammaTrailingEngine`, `UnifiedExitChecker`, or any LOCKED live exit path.
- No feature-pipeline repair (ATR/ADX/gap population) beyond the synthetic-fallback guard.
- No new live entry logic.
