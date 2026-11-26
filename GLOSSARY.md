# Ubiquitous Domain Glossary (`GLOSSARY.md`)
*The authoritative ubiquitous language for the `algo-scalper` algorithmic options trading platform.*

---

## Underlyings
The primary index cash/spot assets traded on Indian exchanges (NSE & BSE).
- **`NIFTY`**: NIFTY 50 index (NSE). Weekly expiry contracts, high liquidity, primary scalping index.
- **`BANKNIFTY`**: NIFTY Bank index (NSE). Higher beta, wider intraday ATR swings.
- **`SENSEX`**: BSE SENSEX 30 index (BSE). Thursday weekly expiries, high-gamma weekly options.
- **`Spot Price`**: Real-time cash index LTP fed via DhanHQ WebSocket feed.

---

## Regimes
Macro market conditions classified by multi-timeframe ATR, ADX, efficiency ratio (ER), and Smart Money Concepts.
- **`TRENDING`**: Directional momentum with high Efficiency Ratio ($ER > 0.40$) and SuperTrend alignment. Suitable for ATM options buying.
- **`RANGING / CHOPPY`**: Sideways market oscillating around VWAP without follow-through. Options buying is strictly gated or penalized.
- **`GAMMA`**: Late afternoon session (post 13:30 IST) or expiry day session characterized by accelerating delta/gamma sensitivity.
- **`EXPIRY`**: Day of weekly contract settlement (0 DTE). High volatility, sharp theta decay curve.

---

## Postures
Agent execution aggressiveness and entry confirmation levels (`options-trading-agent`).
- **`SCOUT`**: Aggressive posture. Enters on opening range breakout (ORB), SuperTrend flip, or momentum break without requiring multi-indicator agreement.
- **`ALIGNED`**: Standard posture. Requires ORB breakout + SuperTrend + EMA fast/slow alignment on closed candle.
- **`CONFIRMED`**: Conservative/Protective posture. Requires price to hold beyond range, multi-indicator trend confluence, and a confirmation candle.

---

## Trade Intents
The contract boundary (`trade-intent/1`) communicating trade recommendations from Rails signal generation to the TypeScript execution agent.
- **`TradeIntent`**: Immutable directive containing `intent_id`, `underlying`, `direction` (`BULLISH` | `BEARISH`), `confidence`, and `expires_at` (default 20s TTL).
- **`Intent Outcome`**: Agent decision reporting whether intent was `accepted`, `dropped` (e.g. `SIDE_POSITION_LIMIT`, `NO_EXPIRY`), or `expired`.
- **`Agent Snapshot`**: Heartbeat published by the agent to Redis key `trading:agent:snapshot` every 2s, communicating feed age, open positions, day PnL, and entry window.

---

## Risk Stops
Capital protection rules and exit invariants enforced across active positions.
- **`STOP_LOSS`**: Initial protective stop loss pegged to underlying structure or option premium percentage (default 30%–50% of premium).
- **`TARGET (1R)`**: Standard profit-taking objective (default 1R: Risk-to-Reward 1:1 to 1:1.5).
- **`TRAILING_STOP`**: Dynamic staircase trailing stop stepped up as premium advances (locks in profit tighter, e.g. 8% jump).
- **`TIME_STOP`**: Forced time-based exit. If an option buying trade does not reach target within 30 minutes, it is closed to prevent fatal theta decay.
- **`BREAKEVEN_STOP`**: Moving stop-loss to entry price once the trade achieves a defined hurdle (e.g., $0.8R$).
- **`FLATTEN_BY`**: Mandatory intraday auto-square off time (15:15 IST) before market close.
