# AGENT RULES (MANDATORY)

## SYSTEM PRINCIPLES

- Deterministic system only (no randomness)
- Backtest == Live behavior (same code path)
- Candle source = Dhan OHLCV ONLY (no tick-built candles)
- Indicators use ONLY closed candles

---

## TRADING LOGIC RULES

- Decision = f(DayType, Session, Regime, Score, Stability)
- Chop market = NO TRADE
- Expiry ≠ Normal day (different strategies)
- Regime must be stable (min 3 candles)
- Cooldown after regime flip (3–5 min)

---

## ARCHITECTURE BOUNDARIES

### DO NOT MODIFY (LOCKED)

- app/services/orders/*
- app/services/positions/*
- app/services/exit/*
- app/services/live/*
- app/services/capital/*

### ALLOWED (STRATEGY SURFACE)

- app/services/strategy/*
- app/services/context/*
- app/services/market/*
- app/services/signal/*
- app/services/risk/rules/*

---

## IMPLEMENTATION RULES

- No pseudo code
- Complete, runnable code only
- Handle edge cases explicitly
- No duplicate engines (single Exit::Engine)

---

## DATA RULES

- OHLCV → Dhan historical API
- LTP → WebSocket only
- No mixed candle sources

---

## FAILURE PROTOCOL

If any requirement is unclear or missing:

→ STOP and ask
→ DO NOT assume

---

## OUTPUT REQUIREMENTS

Every task must include:

- File paths
- Integration points
- Test/validation steps

