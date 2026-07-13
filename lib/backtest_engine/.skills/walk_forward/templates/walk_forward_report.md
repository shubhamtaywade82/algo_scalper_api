# Walk-Forward Validation Report
**Strategy**: {{strategy_name}}
**Total Windows**: {{total_windows}}
**Verdict Status**: {{status}} (PASS / FAIL)

---

## 1. Overall Validation Summary
* **Validation Score**: {{overall_score}} / 100
* **Walk-Forward Efficiency (WFE)**: {{wfe}}
* **Performance Retention**: {{retention_pct}}%
* **Parameter Stability Score**: {{stability_score}}%
* **Overfitting Risk Classification**: {{overfitting_risk}}

---

## 2. Forward Window Statistics
| Window ID | Period | IS Profit Factor | OS Profit Factor | WFE | Parameter Set | Verdict |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| {{win_id_1}} | {{period_1}} | {{is_pf_1}} | {{os_pf_1}} | {{wfe_1}} | {{params_1}} | {{status_1}} |
| {{win_id_2}} | {{period_2}} | {{is_pf_2}} | {{os_pf_2}} | {{wfe_2}} | {{params_2}} | {{status_2}} |

---

## 3. Parameter Drift & Sensitivity
* **Drift Summary**: {{drift_summary}}
* **Stable Parameter Valley**: {{stable_valley}}
