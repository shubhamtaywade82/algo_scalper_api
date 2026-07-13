# Strike Quality Scorecard: {{strike}} {{option_type}}
**Active Expiry**: {{expiry}} (DTE: {{dte}})

---

## 1. Score Summary
* **Overall Quality Score**: {{overall_score}} / 100
* **Classification**: {{classification}}
* **Action Status**: {{status}} (e.g. Approved / Rejected)

---

## 2. Factor Breakdown
| Factor | Weight | Raw Metric | Scaled Score |
| :--- | :--- | :--- | :--- |
| **Liquidity** | 25% | Bid/Ask Depth: {{depth}} | {{liquidity_score}} |
| **Open Interest** | 20% | OI: {{oi_value}} | {{oi_score}} |
| **Volume** | 20% | Vol: {{volume_value}} | {{volume_score}} |
| **Implied Volatility** | 15% | IV: {{iv_value}}% | {{iv_score}} |
| **Bid-Ask Spread** | 10% | Spread: {{spread_pct}}% | {{spread_score}} |
| **Greeks** | 10% | Delta: {{delta}} | {{greek_score}} |

---

## 3. Risk Assessment
* **Spread Slippage Risk**: {{spread_risk}}
* **Theta Decay Risk**: {{theta_risk}}
* **IV Crush Potential**: {{iv_crush_risk}}
