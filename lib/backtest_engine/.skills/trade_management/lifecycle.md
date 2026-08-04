# Trade Lifecycle State Machine

An open position shifts through these states during its lifecycle:

```text
[Waiting Entry] ──(Order Filled)──> [Fresh Entry]
                                         │
                                         ▼
                                 [Initial Risk]
                                         │
                                  (PnL > Trigger)
                                         ▼
                                 [Break Even SL]
                                         │
                                   (Trend Aligns)
                                         ▼
                               [Trend Following]
                                         │
                                  (MFE Expansion)
                                         ▼
                              [Profit Protection]
                                         │
                                   (Exit Trigger)
                                         ▼
                                  [Completed]
```

## State Descriptions
* **Fresh Entry / Initial Risk**: Focus is strictly on capital preservation. Hard SL is active; no scaling is permitted.
* **Break Even SL**: The trade has moved in our favor. Stop is adjusted to `entry_price + fees` to eliminate loss risk.
* **Trend Following**: Stop is trailed dynamically using volatility (ATR) or market structure swing points.
* **Profit Protection**: The trade has reached high R-multiples. Trailing stops are tightened to lock in profits.
