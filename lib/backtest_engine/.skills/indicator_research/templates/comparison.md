# Feature Correlation & Comparison Report
**Asset**: {{symbol}}
**Timeframe**: {{timeframe}}

---

## 1. Top-Line Redundancy Check
* **Total Features Tested**: {{total_features}}
* **Identified Collinear Pairs ($r > 0.70$)**: {{collinear_count}}
* **Action Status**: Excluded {{excluded_count}} redundant features from active generation pipeline.

---

## 2. Feature Correlation Matrix
| Feature A | Feature B | Correlation ($r$) | Redundancy Status |
| :--- | :--- | :--- | :--- |
| {{feat_a_1}} | {{feat_b_1}} | {{corr_val_1}} | {{status_1}} |
| {{feat_a_2}} | {{feat_b_2}} | {{corr_val_2}} | {{status_2}} |

---

## 3. Mutual Information Rankings
| Feature Name | Category | Mutual Information Score | Recommendation |
| :--- | :--- | :--- | :--- |
| {{feature_rank_1}} | {{cat_1}} | {{mi_score_1}} | {{rec_1}} |
| {{feature_rank_2}} | {{cat_2}} | {{mi_score_2}} | {{rec_2}} |
