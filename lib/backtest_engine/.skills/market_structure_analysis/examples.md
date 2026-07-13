# Market Structure Analysis Examples

Here are concrete examples showing how the researcher maps swing breakouts and liquidity sweeps.

## Example 1: Identifying a Change of Character (CHOCH)

### Price Log (5-minute Candles)
* Candle 1: High `24,200`, Low `24,150`, Close `24,180` (Up trend)
* Candle 2: High `24,230`, Low `24,170`, Close `24,220` (HH/HL)
* Candle 3: High `24,250`, Low `24,210`, Close `24,240` (HH/HL, swing low established at `24,170`)
* Candle 4: High `24,220`, Low `24,160`, Close `24,165` (Price closes below swing low of `24,170`)

### Analysis
* Since price closed below the prior Higher Low (HL) of `24,170`, a **Bearish CHOCH** is confirmed.
* The bullish regime ends; downstream strategies are alerted to stop taking Long Call (CE) positions.

---

## Example 2: Detecting a Liquidity Sweep

### Price Log (1-minute Candles)
* EQL established at `24,120` from double bottom swings.
* Candle A: Close `24,130`
* Candle B: High `24,128`, Low `24,110`, Close `24,125`

### Analysis
* The low of Candle B (`24,110`) broke the EQL of `24,120`, triggering stop-loss orders positioned below the double bottom.
* However, price closed the candle at `24,125` (back inside the range) on volume `2.5x` the baseline.
* Classified as a **Bullish Liquidity Sweep**. Strategy generator is alerted of a potential pullback bounce entry.
