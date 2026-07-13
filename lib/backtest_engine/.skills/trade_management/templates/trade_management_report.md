# Trade Management Report: Trade {{trade_id}}
**Status**: {{trade_status}}
**Current R-Multiple**: {{r_multiple}}

---

## 1. Position Status
* **Option Symbol**: `{{option_symbol}}`
* **Entry Price / Quantity**: {{entry_price}} / {{quantity}} lots
* **Current Premium Price**: {{current_price}}
* **Open P&L (Rupees / %)**: {{open_pnl_rupees}} / {{open_pnl_pct}}%

---

## 2. Exits & Boundaries
* **Initial Hard SL**: {{initial_sl}}
* **Active Stop-Loss**: {{active_sl}} (Type: {{sl_type}})
* **Target Price**: {{target_price}} (Type: {{target_type}})
* **Time in Trade**: {{time_held}} minutes (Limit: {{max_time}} mins)

---

## 3. Decisions & Recommendations
* **Trade State**: {{trade_state}} (e.g. Trend Following)
* **Recommended Action**: {{recommended_action}}
* **Action Confidence**: {{confidence_score}}%
