# ADR-002: Intraday Session Cutoffs and Entry Window Limits

## Status
Accepted

## Context
On Indian exchanges (NSE/BSE), regular trading hours are 09:15 to 15:30 IST. Intraday option buyers face a non-linear decay curve:
- In the morning (09:15 to 11:30 IST), directional breakouts have ample liquidity and time to run.
- Midday (11:30 to 13:30 IST) is historically choppy, characterized by mean-reverting ranges and low volume expansion.
- Late afternoon (after 14:00 IST), theta decay accelerates exponentially on weekly contracts (0 to 3 DTE). Broker auto-square-off occurs around 15:15 to 15:20 IST.

Opening fresh directional option buying trades after 14:00 IST leaves an insufficient time horizon for the underlying to reach a 1:1.5 Risk-to-Reward target before mandatory square-off, resulting in frequent losses due to theta erosion.

## Decision
We enforce strict intraday session boundaries:
1. **Entry Window**: `09:15` to `14:00` IST (`start_minute: 555, end_minute: 840`).
2. **Hard Cutoff**: At 14:00 IST, `TradeIntents::Forwarder` and `options-trading-agent` close the intake window and reject all fresh entry signals with reason `outside_agent_entry_window`.
3. **Mandatory Flatten**: All open intraday positions must be closed by `15:15` IST (`flatten_by: "15:15"`).

## Consequences
- **Positive**: Protects the account from late-session chop, theta decay, and broker-forced penalty square-offs.
- **Positive**: Empirical backtesting and live data confirm late entries yield negative expectancy on index option longs.
- **Negative**: The system will sit idle and refuse trades after 14:00 IST even if a late trend or gamma burst occurs.
