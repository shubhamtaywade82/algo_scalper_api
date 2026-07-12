# Options Opportunity Alert: {{symbol}}
**Detected At**: {{timestamp}}
**Market Regime**: {{current_regime}}

---

## 1. Highlighted Opportunity
* **Opportunity Type**: {{opportunity_type}} (e.g. Volatility Contraction / Gamma Trigger)
* **Target Contract**: `{{target_contract}}`
* **Trigger Event**: {{trigger_event}}
* **Estimated Success Confidence**: {{confidence_score}}%

---

## 2. Quantitative Conditions Check
* **IV Percentile**: {{iv_percentile}}%
* **Bid-Ask Spread**: {{spread_pct}}%
* **OI Velocity (15m change)**: {{oi_velocity}}%
* **Gamma Concentration**: {{gamma_concentration}}

---

## 3. Playbook Action Checklist
- [ ] Verify underlying structure has confirmed breakout/pullback.
- [ ] Confirm bid-ask spread remains under 1.5% at order entry time.
- [ ] Size position using the {{sizing_model}} modifier (authorized quantity: {{qty}} lots).
- [ ] Deploy initial stop-loss at {{sl_price}} and select trailing type: {{trail_type}}.
