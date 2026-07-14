# Institutional Opening Auction Research Platform & Operating System (V4)

## 1. Executive Summary & Objective

The **Institutional Opening Auction Research Platform (V4)** has transitioned from a basic backtester into an advanced quantitative research platform designed to validate hypotheses, identify market regimes, analyze structural failure modes, and discover statistical truths about **NIFTY Opening Range Breakouts (ORB)** and ATM/OTM options premium lifecycles.

Instead of trying to force strategy fits, V4 acts as a knowledge generation machine that measures **market mechanics** (velocity, acceleration, elasticities, and decay) and filters noise through feature correlation and statistical walk-forward out-of-sample validation.

---

## 2. Platform Architecture (V4)

```
                       Raw Market Data (NIFTY & Options)
                                       │
                                       ▼
                       Data Quality & Market Hours Filter
                                       │
                                       ▼
                            Regime Classifier (V4)
               (ATR Volatility, Trend/Range, Expiry Proximity)
                                       │
                                       ▼
                          Opening Range Analyzer V4
                      (Extracts 15m IB Breakout Events)
                                       │
                                       ▼
                            Replay Engine (V4)
                   (Minute-by-Minute State Replay,
                     Strictly No Hindsight Leakage)
                                       │
                                       ▼
                        Option Lifecycle Tracker (V4)
               (Compression -> Auction -> Ignition -> Expansion
                 -> Momentum Decay -> Exhaustion -> Distribution)
                                       │
                                       ▼
                          Negative Research (V4)
                 (Categorizes Failed Breakout Reasons)
                                       │
                                       ▼
                         Statistical Validator (V4)
               (Walk-Forward IS/OOS, 1000x Bootstrap Resample)
                                       │
                                       ▼
                         Feature Importance (V4)
                    (Feature-to-Outcome Pearson Correlation)
                                       │
                                       ▼
                      CSV / JSON Report Generator V4
```

---

## 3. Key Quant Findings & Market Mechanics

### Feature Correlations (MFE Strength)
Using Pearson Correlation Coefficient ($r$) between pre-open/ignition features and the ultimate ATM option expansion MFE %:
* **Gap Magnitude ($r = -0.4939$)**: Strong negative correlation. Large opening gaps lead to smaller intraday option premium expansions (gap fill or immediate mean reversion).
* **ATR ($r = 0.4682$)**: Strong positive correlation. Broad daily ranges correlate with higher option premium expansions.
* **ADX ($r = 0.4382$)**: Higher ADX strongly aligns with expansion strength.
* **First Candle Body Ratio ($r = -0.4229$)**: Negative correlation. Large opening candles with little or no wicks often exhaust immediate buying power, leading to immediate reversals.
* **Ignition Velocity ($r = 0.0499$)**: Almost $0.0$. The velocity of the first 3 minutes of a breakout is **pure statistical noise** and does not predict future premium expansion.

### Negative Research: Failure Attribution
When breakouts fail to reach targets, V4 analyzes the underlying and premium mechanics to determine why:
* **VWAP Reclaimed ($81.8\%$)**: The overwhelming reason NIFTY breakouts fail is the underlying spot price crossing back across the daily VWAP anchor, confirming a fakeout.
* **Premium Divergence ($18.2\%$)**: The spot index makes a new high/low, but the option premium fails to follow, signaling heavy block selling or lack of option momentum.

### Option Lifecycle Phase Durations
Trades are tracked across 7 sequential phases:
1. **Compression**: Consolidation before the open.
2. **Auction**: Consolidation during the initial 15-minute range formation.
3. **Ignition**: The 3-minute post-breakout surge.
4. **Expansion**: The continuation phase to the option's peak price (averages $10.3$ minutes).
5. **Momentum Decay**: Initial velocity slowdown after the peak.
6. **Exhaustion**: Premium Exhaustion Score (PES) peaks or divergence triggers.
7. **Distribution**: Sideways premium range-bound behavior before close.

---

## 4. Rigorous Statistical Validation

To prevent overfitting, the system uses two mathematical layers:
1. **Chronological Walk-Forward Split**:
   - **In-Sample (IS - 60%)**: Used to evaluate initial strategy expectancy.
   - **Out-of-Sample (OOS - 40%)**: Chronologically later trades used to test performance decay.
   - *Example*: Hybrid Divergence exit strategy shows an average return of $-18.1\%$ in-sample, which stabilizes to $-0.3\%$ out-of-sample, indicating expected performance degradation.
2. **Bootstrap Resampling**:
   - Simulates 1,000 runs with replacement to construct **$95\%$ Confidence Intervals (CI)** for each exit strategy.
   - *Example*: Underlying EMA9 exit return $95\%$ CI is $[-7.8\%, +0.5\%]$, representing the true mathematical boundaries of the rule.

---

## 5. Exit Performance Matrix (ATM Strike)

| Exit Strategy | Win Rate | Avg Return | Sharpe | Profit Factor | Avg Holding Time | 95% Expected CI |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Underlying EMA9** | $41.67\%$ | $-3.70\%$ | $-0.470$ | $0.30$ | $7.9\text{ min}$ | $[-7.8\%, +0.5\%]$ |
| **Premium EMA5** | $8.33\%$ | $-8.70\%$ | $-1.109$ | $0.03$ | $3.0\text{ min}$ | $[-12.7\%, -4.7\%]$ |
| **Fixed 50% Target** | $33.33\%$ | $-9.57\%$ | $-0.232$ | $0.53$ | $274.9\text{ min}$ | $[-34.0\%, +13.3\%]$ |
| **Hybrid Divergence**| $33.33\%$ | $-10.69\%$ | $-0.586$ | $0.11$ | $10.3\text{ min}$ | $[-22.7\%, -2.2\%]$ |
| **Trailing 20% Stop**| $0.00\%$ | $-13.39\%$ | $-2.911$ | $0.00$ | $38.1\text{ min}$ | $[-15.6\%, -10.8\%]$ |

---

## 6. Validated Hypotheses Verdicts

| Hypothesis Rule | Sample Size | Success Rate | Expectancy | Verdict |
| :--- | :---: | :---: | :---: | :--- |
| **Gap-down + entry below VWAP $\rightarrow$ Bearish PE ATM MFE $\ge 30\%$** | $1$ | $100\%$ | $-0.61$ R | **REJECT** (expectancy negative) |
| **Inside Day + Narrow OR (<35 pts) + ADX > 20 $\rightarrow$ Sustained Breakout** | $0$ | $0\%$ | $0.00$ R | **REJECT** (insufficient sample) |
| **Wide OR (>50 pts) $\rightarrow$ Breakout Fails / Mean Reverts** | $10$ | $100\%$ | $-0.65$ R | **REJECT Option Buying** |
| **High Ignition Velocity (>3.0 pts/min) $\rightarrow$ Option MFE $\ge 30\%$** | $7$ | $28.6\%$ | $-0.27$ R | **REJECT** (low success & negative exp) |

---

## 7. Peak-Capture Exit Validation (V5)

**Run:** `Research::First15mEngine.run(symbol: "NIFTY", lookback_days: 90)`, strict mode. **90 of 90 trading days simulated, 0 skipped, 0 synthetic-fallback triggers** — every trade in this section is built from real DhanHQ underlying candles and real `ExpiredOptionsData` (rollingoption) option bars, none from the Black-Scholes premium simulator. Sample size: 119 trade opportunities (up from 11 in V4).

### Verdict rule (from the design spec, applied mechanically)

A strategy wins only if its OOS retention ratio beats the best pre-existing exit (best of the original 8: `fixed_30` at 0.15) **and** its bootstrap 95% CI lower bound on return is above 0%. Otherwise: no validated edge.

### 13-strategy exit-performance matrix (ATM strike)

| Strategy | Win Rate | Avg Return | Sharpe | Retention Ratio | Avg Pts Lost | 95% Return CI | IS / OOS Return | Verdict |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :--- |
| **`mfe_retrace_25`** | 100.0% | +2.65% | 0.753 | **0.19** | 19.9 | **[+2.1%, +3.4%]** | +2.6% / +2.7% | **WINS** |
| **`mfe_retrace_35`** | 100.0% | +2.30% | 0.753 | 0.17 | 20.4 | **[+1.8%, +2.9%]** | +2.3% / +2.3% | **WINS** |
| `mfe_retrace_50` | 100.0% | +1.77% | 0.753 | 0.13 | 21.0 | [+1.4%, +2.3%] | +1.8% / +1.8% | retention below `fixed_30` (0.15) — no |
| `velocity_ratchet` | 72.3% | +0.81% | 0.033 | **0.39** (best of all 13) | 22.3 | [-3.8%, +4.7%] | -1.2% / +3.8% | CI crosses zero — no |
| `und_ema9` | 42.0% | -2.57% | -0.204 | 0.13 | 25.0 | [-5.2%, -0.5%] | -1.2% / -4.6% | no |
| `momentum_decay` | 35.3% | -3.34% | -0.243 | 0.09 | 27.6 | [-5.8%, -0.7%] | -3.0% / -3.9% | no |
| `prem_ema5` | 21.0% | -5.21% | -0.492 | 0.03 | 29.5 | [-7.1%, -3.6%] | -4.2% / -6.7% | no |
| `hybrid_divergence` | 31.1% | -6.06% | -0.448 | 0.09 | 29.6 | [-8.4%, -3.6%] | -4.1% / -9.0% | no |
| `gamma_state` | 18.5% | -6.95% | -0.674 | 0.08 | 34.4 | [-8.7%, -5.0%] | -6.7% / -7.3% | no |
| `trail_20` | 12.6% | -8.54% | -0.821 | 0.03 | 37.3 | [-10.3%, -6.6%] | -8.9% / -8.0% | no |
| `fixed_30` | 27.7% | -11.47% | -0.360 | 0.15 | 38.5 | [-17.7%, -5.5%] | -12.9% / -9.3% | no (baseline) |
| `fixed_50` | 20.2% | -17.98% | -0.501 | 0.10 | 43.2 | [-24.4%, -11.5%] | -20.8% / -13.9% | no |
| `hold_to_close` | 17.7% | -21.80% | -0.623 | 0.07 | 45.0 | [-28.6%, -16.1%] | -22.9% / -20.2% | no |

### Verdict: `mfe_retrace_25` and `mfe_retrace_35` are validated peak-capture exits

Exiting at **peak − 25%×MFE** (tighter than live `Orders::MfeExitEngine`'s current 35% default) is the statistically strongest rule found: 100% win rate across 119 trades, entirely positive bootstrap CI, and OOS return (+2.7%) essentially matching IS (+2.6%) — no sign of the overfitting decay that sank V4's Hybrid Divergence exit. `mfe_retrace_35` (matching the live engine's exact current ratio) also passes, with a slightly wider CI and lower return. **This validates tightening the live `Orders::MfeExitEngine` retrace ratio from 0.35 toward 0.25** as a candidate follow-up — not applied here (design doc's non-goals: no live exit changes in this pass).

### `velocity_ratchet` did not validate, despite the best raw capture

`velocity_ratchet` — the exit purpose-built for this project's peak-capture problem — retains **more than double** the peak of any other strategy (0.39 vs. 0.19) and has a positive OOS return (+3.8%), but its bootstrap CI (`[-3.8%, +4.7%]`) crosses zero: the wider gap tolerance that lets it ride bigger winners also lets a minority of trades round-trip badly enough to make the strategy's overall edge statistically indistinguishable from zero at 119 trades. This is an honest negative result, not a bug — a good candidate for either (a) more samples (the CI narrows as $n$ grows) or (b) a tighter/asymmetric floor gap in a future revision, not for wiring into live as-is.

### Feature correlations remain unpopulated — a separate, still-open gap

ATR, ADX, RSI, gap%, VWAP distance, first-candle body ratio, and first-candle volume all correlate at **exactly 0.0000** with MFE strength — these features are not being computed/populated anywhere upstream of `ExitCaptureAnalyzer`/`OptionExpansionAnalyzer`, the same gap flagged in V4. Unlike V4, this is no longer masked by a fabricated-looking correlation (the constant-0.5/0.0 columns that produced V4's misleading $r=-0.49$ etc. are gone — strict mode confirmed they were fallback artifacts, not real signal). Only `ignition_velocity` (r=0.073) and `or_width` (r=-0.062) have any measured value, and both are too weak to act on. Feature-pipeline repair is out of scope for this pass (design doc non-goals) and remains the next real gap to close before any regime-conditional analysis (day-type, volatility-regime breakdowns) can be trusted.

### Hypothesis re-test at n=119 (up from n≤11 in V4)

| Hypothesis | Sample | Verdict (V4, n≤11) | Verdict (V5, n=119) |
| :--- | :---: | :--- | :--- |
| Wide OR (>50pts) → breakout fails | 117 | REJECT (n=10) | **NEEDS MORE SAMPLES** (min 250) |
| High ignition velocity → MFE≥30% | 78 | REJECT (n=7) | **NEEDS MORE SAMPLES** (min 250) |
| Gap-down + below-VWAP → bearish PE MFE≥30% | 0 | REJECT (n=1) | INSUFFICIENT EVIDENCE (no matching days in this window) |
| Inside Day + narrow OR + ADX>20 → sustained | 0 | REJECT (n=0) | INSUFFICIENT EVIDENCE (no matching days in this window) |

V4's "REJECT" verdicts on 7-10 samples were themselves statistical noise dressed as conclusions — the honest V5 verdict is "needs ~2x more data," not "rejected."
