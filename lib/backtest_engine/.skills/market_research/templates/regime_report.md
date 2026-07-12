# Market Regime Analysis Report
**Underlying**: {{symbol}}
**Time Window**: {{start_time}} to {{end_time}}

---

## 1. Regime Transitions
| Period | Prior Regime | New Detected Regime | Transition Event / Cause |
| :--- | :--- | :--- | :--- |
| {{period_1}} | {{prior_regime_1}} | {{detected_regime_1}} | {{transition_cause_1}} |
| {{period_2}} | {{prior_regime_2}} | {{detected_regime_2}} | {{transition_cause_2}} |

---

## 2. Statistical Profile of Detected Regime: {{current_regime}}
* **Mean Intraday Range (ATR %)**: {{avg_atr_pct}}%
* **Mean Premium Expansion Rate**: {{avg_premium_expansion}}%
* **Win Expectancy Baseline**: {{win_expectancy_baseline}}
* **Transition Matrix Probabilities**:
  - Probability of remaining in this regime: {{prob_stay}}%
  - Probability of transition to Range-Bound: {{prob_to_range}}%
  - Probability of transition to High Volatility: {{prob_to_vol}}%

---

## 3. Deployment Guidance
* **Position Sizing Modifier**: {{sizing_modifier}} (e.g. 0.5x for volatile range)
* **Exit Tightness Modifier**: {{exit_modifier}} (e.g. tighten trail triggers)
* **Execution Strategy**: {{execution_strategy}} (e.g. limit order post-pullback only)
