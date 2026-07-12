# STRATEGY RULES SPECIFICATION

Formal specification of strategy behavior. Agents must implement strategies
to match these rules exactly.

---

## State Machine

Every strategy operates as a state machine:

```
IDLE → SIGNAL_PENDING → IN_TRADE → IDLE
```

- **IDLE**: no position, scanning for setup
- **SIGNAL_PENDING**: setup conditions met, waiting for confirmation candle close
- **IN_TRADE**: position open, monitoring for exit conditions

Transitions:
- `IDLE → SIGNAL_PENDING`: setup conditions first detected
- `SIGNAL_PENDING → IN_TRADE`: confirmation candle closes with signal intact
- `SIGNAL_PENDING → IDLE`: setup fails (signal disappears before confirmation)
- `IN_TRADE → IDLE`: position closed (stop-loss, target, time exit, or signal reversal)

---

## Candle Processing Pipeline

For each closed candle, strategies process in this order:

1. Update internal indicators (if strategy manages its own)
2. If `IN_TRADE`: check exit conditions first
   - If exit triggered → emit `strategy.signal` with `:sell` and close position
3. If `IDLE`: check entry setup conditions
   - If setup found → transition to `SIGNAL_PENDING`
4. If `SIGNAL_PENDING`: confirm setup on this candle's close
   - If confirmed → transition to `IN_TRADE`, emit `strategy.signal` with `:buy` or `:sell`
   - If not confirmed → transition back to `IDLE`

---

## EMA Crossover — State Transition Specification

```
IDLE:
  if ema9_crossed_above_ema21 AND rsi > 50 AND close > ema21 AND vix < 18:
    direction = :long
    → SIGNAL_PENDING

  if ema9_crossed_below_ema21 AND rsi < 50 AND close < ema21 AND vix < 18:
    direction = :short
    → SIGNAL_PENDING

SIGNAL_PENDING (confirmed immediately on same candle):
  → IN_TRADE
  entry_price = close
  stop_loss   = ema21_value
  target      = entry_price + 2 * atr14  (for long)
              = entry_price - 2 * atr14  (for short)
  emit signal

IN_TRADE:
  if direction == :long AND close < ema21:   EXIT (stop)
  if direction == :long AND close >= target: EXIT (target)
  if direction == :short AND close > ema21:  EXIT (stop)
  if direction == :short AND close <= target: EXIT (target)
  if time >= 15:00 IST:                      EXIT (time)
```

---

## ORB Strategy — State Transition Specification

```
Phase 1 — OR Formation (09:15–09:45):
  Aggregate all 5m candles into opening range.
  or_high = max(candle.high) over period
  or_low  = min(candle.low)  over period
  or_size = or_high - or_low

Phase 2 — Breakout Detection (after 09:45):
IDLE:
  if close > or_high AND volume > avg_volume * 1.5 AND vix < 20:
    direction = :long
    → SIGNAL_PENDING

  if close < or_low AND volume > avg_volume * 1.5 AND vix < 20:
    direction = :short
    → SIGNAL_PENDING

SIGNAL_PENDING → IN_TRADE (immediately):
  entry_price = close
  if direction == :long:
    stop_loss = or_low
    target    = entry_price + or_size
  if direction == :short:
    stop_loss = or_high
    target    = entry_price - or_size

IN_TRADE:
  if direction == :long  AND close < stop_loss:  EXIT (stop)
  if direction == :long  AND close >= target:    EXIT (target)
  if direction == :short AND close > stop_loss:  EXIT (stop)
  if direction == :short AND close <= target:    EXIT (target)
  if time >= 14:30 IST:                          EXIT (time)

Re-entry: NONE — once stopped out, no re-entry on same side.
```

---

## VIX Spike Reversal — State Transition Specification

```
Operates on 15-minute candles.

IDLE:
  Phase 1 — Fear spike:
  if vix > 18
    AND vix_change_pct_15min > 10%
    AND underlying_change_pct_15min < -0.5%
    AND rsi14 < 40:
      direction = :short (buy puts)
      → SIGNAL_PENDING

SIGNAL_PENDING → IN_TRADE:
  entry_price = close
  stop_loss   = calculated from vix reversal (vix closes < 16 on 15m candle)

IN_TRADE (Phase 1 — short/put position):
  if vix_15m_close < 16:  EXIT Phase 1 position
    → check Phase 2 conditions

Phase 2 — Mean reversion:
  if vix_dropped_pct_from_spike_high > 15%
    AND rsi14 > 50
    AND underlying_recovered_pct > 0.3%:
      direction = :long (buy calls)
      → new IN_TRADE entry

  if time >= 15:00 IST: EXIT all
```

---

## Shared Exit Rules

These apply to ALL strategies:

| Condition                   | Action                        |
|-----------------------------|-------------------------------|
| Stop-loss price hit         | Exit immediately (market order) |
| Target price hit            | Exit immediately (limit order)  |
| Time exit (strategy-specific)| Exit at market on next candle  |
| Daily loss limit breached   | Exit all positions, halt trading |
| VIX > 25                    | Exit all positions immediately  |
| 15:20 IST                   | Force-close ALL open positions  |
