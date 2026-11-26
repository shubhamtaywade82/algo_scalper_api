# ADR-003: 30-Minute Max Hold Time-Stop on Option Longs

## Status
Accepted

## Context
Unlike equity shares or futures contracts, long option contracts are rapidly depreciating assets with negative theta. If an index underlying moves sideways for 30 minutes after entry:
- The delta gain is zero.
- The vega and theta decay cause the option premium to bleed continuously.
- Replay studies on 1-year of tick-level NIFTY, BANKNIFTY, and SENSEX data showed that option longs held past 30 minutes without hitting target had a win-rate drop from 48% to under 22%.

Holding a stagnant option trade in hope of a delayed bounce is mathematically unprofitable.

## Decision
We enforce a mandatory **`TIME_STOP` invariant of 30 minutes** on all option long scalps (`max_hold_minutes: 30`):
1. When a position is opened, a 30-minute timer starts.
2. If neither the profit target (1R) nor the stop-loss is triggered within 30 minutes, the agent automatically executes a market exit with reason `TIME_STOP`.
3. Following an exit, a 15-minute cooldown (`cooldown_seconds: 900`) is enforced per underlying to prevent immediately re-entering the same consolidation.

## Consequences
- **Positive**: Eliminates slow bleed from consolidating markets; frees capital for fresh setups.
- **Positive**: Directly verified on live paper trading (e.g. NIFTY PE exiting at 14:06 IST with +₹1,827 profit rather than decaying into negative territory).
- **Negative**: Occasionally cuts a trade right before a delayed breakout occurs after 35–40 minutes.
