# DOMAIN KNOWLEDGE — NSE Options Trading

This file is the ground truth for all market facts. Agents must treat
every value here as authoritative. Do not invent or override these values.

---

## Market Hours (IST = UTC+5:30)

| Session            | Time              | Notes                                 |
|--------------------|-------------------|---------------------------------------|
| Pre-open           | 09:00 – 09:15     | No trading; order collection only     |
| Normal market open | 09:15             | Trading starts                        |
| Avoid first 5 min  | 09:15 – 09:20     | High volatility; skip unless strategy specifies |
| Normal session     | 09:20 – 15:20     | Primary trading window                |
| Exit-only window   | 15:20 – 15:30     | Close all intraday positions; no new entries |
| Market close       | 15:30             | All FO positions auto-squared by broker |

Trading days: Monday–Friday, excluding NSE holidays.

---

## Index Lot Sizes

| Index      | Lot Size (units) | Notes                        |
|------------|------------------|------------------------------|
| NIFTY 50   | 75               | Revised to 75 in Nov 2024    |
| BANKNIFTY  | 30               | Revised to 30 in Nov 2024    |
| FINNIFTY   | 65               | Revised in 2024              |
| MIDCPNIFTY | 75               |                              |
| SENSEX     | 20               | BSE only                     |

> Always verify lot sizes at the start of each week — SEBI revises them periodically.

---

## Expiry Schedule

| Index      | Weekly Expiry Day | Monthly Expiry              |
|------------|-------------------|-----------------------------|
| NIFTY 50   | Thursday          | Last Thursday of the month  |
| BANKNIFTY  | Wednesday         | Last Wednesday of the month |
| FINNIFTY   | Tuesday           | Last Tuesday of the month   |
| MIDCPNIFTY | Monday            | Last Monday of the month    |

If the scheduled expiry day is a market holiday, expiry moves to the previous trading day.

---

## Option Contract Naming Convention (DhanHQ)

Format: `{SYMBOL}{YYMMDD}{STRIKE}{CE|PE}`

Examples:
- `NIFTY25JAN23C24000` — NIFTY Call, expiry 23 Jan 2025, strike 24000
- `BANKNIFTY25JAN29P51000` — BANKNIFTY Put, expiry 29 Jan 2025, strike 51000

---

## India VIX

- India VIX is the NSE volatility index, similar to CBOE VIX
- Range interpretation:
  - VIX < 12: Very low volatility — avoid buying options (premium is cheap but won't move)
  - VIX 12–16: Normal range — good for options buying
  - VIX 16–20: Elevated — good momentum setups; increase target multiples
  - VIX > 20: High fear — avoid new positions; manage existing with tight stops
  - VIX > 25: Extreme — exit all positions immediately

---

## Options Greeks (Reference)

| Greek | Symbol | What it measures                        | Typical range (ATM) |
|-------|--------|-----------------------------------------|----------------------|
| Delta | Δ      | Price sensitivity to underlying move    | 0.45–0.55 (ATM)     |
| Gamma | Γ      | Rate of change of delta                 | Peaks near expiry    |
| Theta | Θ      | Time decay per day                      | Negative for buyers  |
| Vega  | V      | Sensitivity to IV change                | Positive for buyers  |

For options buying strategies:
- Prefer delta > 0.40 (not too far OTM)
- Avoid buying on days with falling VIX (vega kills the trade)
- Theta decay accelerates in the last week before expiry

---

## Strike Selection Rules

For NIFTY options (ATM ≈ spot price):
- ATM strike: nearest 50-point multiple to spot
- 1 OTM: 1 strike away from ATM in the direction of trade
- 2 OTM: 2 strikes away — higher risk, higher reward

For BANKNIFTY options (ATM ≈ spot price):
- ATM strike: nearest 100-point multiple to spot

Default: buy ATM or 1-OTM only. Never buy more than 2-OTM.

---

## Margin Requirements (Approximate)

For options buying: only premium is required as margin.

Example: NIFTY ATM call at ₹150 premium, lot size 75
- Required margin = 150 × 75 = ₹11,250 per lot

---

## Brokerage & Charges (DhanHQ)

| Charge         | Rate                          |
|----------------|-------------------------------|
| Brokerage      | ₹0 (flat fee broker)          |
| STT (sell)     | 0.1% of premium on sell side  |
| Exchange levy  | 0.0495% of turnover           |
| SEBI fee       | ₹10 per crore turnover        |
| GST            | 18% on brokerage + exchange   |
| Stamp duty     | 0.003% on buy side            |

For backtesting, use a flat 0.05% per leg as a conservative all-in cost estimate.

---

## Key Economic Events (Trade Around These)

| Event                        | Frequency      | Typical Impact |
|------------------------------|----------------|----------------|
| RBI Monetary Policy (MPC)    | Every 2 months | Very High      |
| US FOMC Decision             | 8x per year    | High           |
| India CPI / WPI release      | Monthly        | Medium         |
| India GDP data               | Quarterly      | Medium         |
| Union Budget                 | Annual (Feb 1) | Extreme        |
| NSE F&O Expiry               | Weekly         | High on expiry day |

Avoid opening new positions within 30 minutes before or after these events.

---

## Common Patterns & Their Strike Behavior

| Market Condition      | Observation                                    |
|-----------------------|------------------------------------------------|
| Gap-up open           | Calls spike; puts crash — wait for confirmation |
| Gap-down open         | Puts spike; calls crash — wait for confirmation |
| Sideways (range-bound)| Both calls and puts lose value — avoid buying  |
| Trending day          | Momentum options buying works well             |
| VIX spike (>20)       | IV spike inflates premiums; if wrong, losses double |
