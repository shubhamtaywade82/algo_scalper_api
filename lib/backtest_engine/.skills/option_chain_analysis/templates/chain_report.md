# Option Chain Analysis Report: {{symbol}}
**Timestamp**: {{timestamp}}
**Underlying Spot**: {{spot_price}}
**Active Expiry**: {{expiry_date}} (DTE: {{days_to_expiry}})

---

## 1. Market Profile
* **ATM Strike**: {{atm_strike}}
* **Max Pain Strike**: {{max_pain_strike}}
* **Put-Call Ratio (PCR)**: {{pcr}} (Volume: {{pcr_volume}} / OI: {{pcr_oi}})
* **Estimated Market Range**: {{expected_lower_range}} - {{expected_upper_range}}

---

## 2. Walls & Dealer Positioning
* **Call Wall (Major Resistance)**: {{call_wall}} strike (OI: {{call_wall_oi}})
* **Put Wall (Major Support)**: {{put_wall}} strike (OI: {{put_wall_oi}})
* **Net Gamma Exposure (GEX)**: {{net_gex}} (Dealer Bias: {{dealer_bias}})

---

## 3. Best Contract Recommendations
* **Best Call Option (CE)**:
  - Strike: {{best_ce_strike}} (Score: {{best_ce_score}})
  - Symbol: `{{best_ce_symbol}}`
  - Delta: {{best_ce_delta}} / Bid-Ask: {{best_ce_bid}} - {{best_ce_ask}}
* **Best Put Option (PE)**:
  - Strike: {{best_pe_strike}} (Score: {{best_pe_score}})
  - Symbol: `{{best_pe_symbol}}`
  - Delta: {{best_pe_delta}} / Bid-Ask: {{best_pe_bid}} - {{best_pe_ask}}
