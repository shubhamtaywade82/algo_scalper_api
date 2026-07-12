# STRATEGY RULES

Universal rules that ALL strategies must follow, plus per-strategy specifications.

---

## Universal Rules (Non-Negotiable)

1. **Signal confirmation**: a signal is only valid if confirmed on candle close — never act mid-candle
2. **One signal per candle**: a strategy may produce at most one entry signal per candle
3. **Stop-loss mandatory**: every entry must come with an explicit stop-loss price
4. **Exit on signal reversal**: if a counter-signal triggers, exit the current position
5. **No pyramiding**: do not add to a winning position mid-session
6. **Time filter**: no new entries after 15:00 IST
7. **VIX filter**: do not enter if India VIX > 20
8. **Backtest/live parity**: strategy logic must be identical in both modes

---

## Strategy 1: EMA Crossover (`ema_crossover`)

**Concept**: Trend-following using 9-period and 21-period EMA on 5-minute candles.

### Entry Conditions

**Long (Buy Call)**:
- EMA(9) crosses above EMA(21) — crossover must be on the current candle's close
- RSI(14) > 50 at the time of signal
- Price (underlying) is above EMA(21)
- VIX < 18

**Short (Buy Put)**:
- EMA(9) crosses below EMA(21)
- RSI(14) < 50
- Price (underlying) is below EMA(21)
- VIX < 18

### Exit Conditions

- **Stop-loss**: candle closes below EMA(21) for longs; above EMA(21) for shorts
- **Target**: 2× the ATR(14) value at entry, added to entry price
- **Time exit**: 15:00 IST — close position regardless

### Parameters

```yaml
fast_ema_period: 9
slow_ema_period: 21
rsi_period: 14
rsi_bull_threshold: 50
atr_period: 14
target_atr_multiplier: 2.0
vix_max: 18
timeframe: "5m"
```

---

## Strategy 2: Opening Range Breakout (`orb_strategy`)

**Concept**: Trade the breakout of the first 30-minute candle range.

### Setup

- Define the Opening Range (OR): high and low of 09:15–09:45 candle aggregation
- Wait for breakout after 09:45

### Entry Conditions

**Long (Buy Call)**:
- Price closes above OR high on a 5-minute candle
- Volume on breakout candle > 1.5× average 5-minute volume (last 10 candles)
- VIX < 20

**Short (Buy Put)**:
- Price closes below OR low
- Volume filter same as above
- VIX < 20

### Exit Conditions

- **Stop-loss**: opposite end of the Opening Range (OR low for longs, OR high for shorts)
- **Target**: OR range size projected from breakout point (1:1 risk-reward minimum)
- **Time exit**: 14:30 IST — give trade enough time to play out
- **Re-entry**: if stopped out, no re-entry on the same side for the session

### Parameters

```yaml
or_duration_minutes: 30
volume_multiplier: 1.5
min_rr_ratio: 1.0
vix_max: 20
timeframe: "5m"
```

---

## Strategy 3: VIX Spike Reversal (`vix_spike_strategy`)

**Concept**: Buy puts when VIX spikes, then switch to calls on mean-reversion.

### Phase 1 — VIX Spike (Fear entry)

**Entry (Buy Put)**:
- VIX > 18 AND VIX increases by > 10% in the last 15 minutes
- NIFTY drops > 0.5% in the last 15 minutes
- RSI(14) < 40

**Stop-loss**: VIX closes back below 16 on 15-minute candle

### Phase 2 — Mean Reversion (After spike)

**Entry (Buy Call)**:
- VIX was above 20 in the last 60 minutes AND has now dropped > 15% from its recent high
- RSI(14) > 50 on a recovery
- NIFTY recovers > 0.3% from the spike low

**Stop-loss**: candle closes below the spike low

### Parameters

```yaml
vix_spike_threshold: 18
vix_spike_pct_increase: 10.0
underlying_drop_pct: 0.5
rsi_period: 14
rsi_bear_threshold: 40
rsi_bull_threshold: 50
reversion_vix_drop_pct: 15.0
recovery_underlying_pct: 0.3
timeframe: "15m"
```

---

## Strike Selection Logic (Shared Across All Strategies)

```
For NIFTY:
  atm_strike = (spot_price / 50).round * 50
  call_strike = atm_strike          # for bullish signals
  put_strike  = atm_strike          # for bearish signals

For BANKNIFTY:
  atm_strike = (spot_price / 100).round * 100

Default: always use ATM strike.
Use 1-OTM only if explicitly configured per strategy.
```

---

## Position Sizing Logic (Shared)

```
risk_amount   = capital × risk_per_trade_pct / 100
premium       = option LTP at time of entry
stop_distance = abs(entry_price - stop_loss_price)
lot_size      = DOMAIN_KNOWLEDGE lot size for the symbol

max_loss_per_lot = stop_distance × lot_size
lots = floor(risk_amount / max_loss_per_lot)
lots = [lots, 1].max          # minimum 1 lot
lots = [lots, max_lots].min   # cap at configured maximum
```
