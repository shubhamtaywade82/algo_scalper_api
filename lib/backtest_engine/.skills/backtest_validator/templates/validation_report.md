# Backtest Validation Report
**Strategy**: {{strategy_name}}
**Audited Period**: {{from_date}} to {{to_date}}
**Status**: {{status}} (PASS / FAIL)

---

## 1. Overall Scorecard
* **Validation Score**: {{overall_score}} / 100
* **Audit Confidence Rating**: {{confidence_rating}}%
* **Critical Failures Detected**: {{failures_count}}
* **Warnings Logged**: {{warnings_count}}

---

## 2. Validation Checks Breakdown
| Check Category | Status (PASS/FAIL) | Score | Key Findings |
| :--- | :--- | :--- | :--- |
| **Data Integrity** | {{data_status}} | {{data_score}} | {{data_findings}} |
| **Lookahead Bias** | {{lookahead_status}} | {{lookahead_score}} | {{lookahead_findings}} |
| **Execution Realism** | {{execution_status}} | {{execution_score}} | {{execution_findings}} |
| **Option Selection** | {{options_status}} | {{options_score}} | {{options_findings}} |
| **Broker Costing** | {{cost_status}} | {{cost_score}} | {{cost_findings}} |
| **Risk Bounds** | {{risk_status}} | {{risk_score}} | {{risk_findings}} |

---

## 3. Critical Failures & Warnings List
* **Critical Failures**:
  - {{critical_failure_1}}
* **Warnings**:
  - {{warning_1}}
  - {{warning_2}}

---

## 4. Final Verdict Recommendation
{{verdict_summary}}
