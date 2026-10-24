Below is a **complete position-management, risk-management, strategy catalog, and trailing framework** for **naked options buying** on **NIFTY / SENSEX index options**, using the data available from **DhanHQ v2**.

This is for **long CE / long PE only**, not option selling/spreads.

---

# 1. The Core Problem: Naked Option Buying Needs a Different Risk Model

Naked option buying is not like buying stocks or futures.

You are fighting:

```text
Delta   → direction
Gamma   → acceleration
Theta   → time decay
Vega    → volatility change
Liquidity → bid-ask spread and slippage
OI flow → option writers hedging/unwinding
Time    → intraday decay accelerates
```

A naked option buyer does not need to be right only about direction.

You need to be right about:

```text
Direction + Timing + Volatility Expansion + Liquidity
```

If any one of these is wrong, the trade can lose money even if NIFTY/SENSEX eventually moves in your favor.

---

# 2. DhanHQ Data Available and How to Use It

## A. Historical expired options data

Endpoint:

```http
POST https://api.dhan.co/v2/charts/rollingoption
```

Available historical fields:

| Field | Use |
|---|---|
| open | Entry/exit simulation |
| high | Intraday target/SL check |
| low | Intraday SL check |
| close | Mark-to-market, signals |
| volume | Liquidity filter |
| oi | OI buildup/unwinding |
| iv | Vega/IV regime filter |
| spot | Underlying movement |
| strike | Actual strike identity |
| timestamp | Candle time |

Important:

```text
Rolling option data gives historical OHLC, IV, OI, volume, spot, strike.
It does NOT give historical Greeks or historical bid-ask spreads.
```

So for backtesting Greeks, you must approximate them using:

```text
spot + strike + IV + time to expiry + risk-free rate
```

---

## B. Live option chain

Endpoint:

```http
POST https://api.dhan.co/v2/optionchain
```

Available live fields:

| Field | Use |
|---|---|
| LTP | Current premium |
| best bid / best ask | Liquidity and slippage |
| OI | Option writer positioning |
| volume | Participation |
| IV | Vega risk |
| Greeks | Delta, gamma, theta, vega |
| strike | Strike selection |
| expiry | Expiry selection |

This is critical for live naked option buying because it gives:

```text
Delta, Gamma, Theta, Vega, IV, OI, Bid/Ask
```

Rate limit:

```text
Option Chain: 1 unique request every 3 seconds
```

So do not fetch option chain every second. Use WebSocket market feed for fast LTP/depth and fetch option chain every 3–15 seconds for Greeks/OI.

---

## C. Market quote / full quote

Endpoints:

```http
POST https://api.dhan.co/v2/marketfeed/ltp
POST https://api.dhan.co/v2/marketfeed/ohlc
POST https://api.dhan.co/v2/marketfeed/quote
```

Full quote gives:

| Field | Use |
|---|---|
| LTP | Latest price |
| LTQ | Last traded quantity |
| ATP | Average traded price |
| volume | Participation |
| total buy quantity | Demand pressure |
| total sell quantity | Supply pressure |
| OI | Open interest |
| OHLC | Intraday structure |
| 5-level market depth | Microstructure |

Useful for:

```text
Bid/ask imbalance
ATP divergence
Volume confirmation
Liquidity checks
```

---

## D. Live market feed WebSocket

Endpoint:

```text
wss://api-feed.dhan.co?version=2&token=ACCESS_TOKEN&clientId=CLIENT_ID&authType=2
```

Packet types:

| Packet | Use |
|---|---|
| Ticker | LTP, LTT |
| Quote | LTP, LTQ, ATP, volume, OHLC, OI |
| Full | Quote + 5-level depth |

Use this for real-time trailing and exit logic.

---

## E. Full market depth WebSocket

20-level:

```text
wss://depth-api-feed.dhan.co/twentydepth?token=...&clientId=...&authType=2
```

200-level:

```text
wss://full-depth-api.dhan.co/twohundreddepth?token=...&clientId=...&authType=2
```

Important from docs:

```text
Full Market Depth is enabled only for NSE Equity and Derivatives.
```

So for NIFTY options, 20/200-level depth may be useful.

For SENSEX/BSE_FNO, verify availability. You may only get standard quote depth.

Use depth for:

```text
Large bid walls
Large ask walls
Order book imbalance
Absorption
Spoofing caution
Liquidity quality
```

---

## F. Historical index data

Endpoints:

```http
POST https://api.dhan.co/v2/charts/intraday
POST https://api.dhan.co/v2/charts/historical
```

Use for:

```text
Spot/index candles
VWAP
ATR
EMA
CPR
Pivot
Volume profile approximation
Market structure
```

For index spot, exchange segment may be:

```text
IDX_I
```

For index options:

```text
NSE_FNO for NIFTY
BSE_FNO for SENSEX
```

---

## G. Trading and risk control APIs

Useful endpoints:

| Endpoint | Use |
|---|---|
| `POST /orders` | Place option order |
| `PUT /orders/{id}` | Modify order |
| `DELETE /orders/{id}` | Cancel order |
| `POST /super/orders` | Entry + target + SL + trailing jump |
| `PUT /super/orders/{id}` | Modify super order legs |
| `GET /positions` | Current positions |
| `GET /fundlimit` | Available margin |
| `POST /killswitch` | Disable trading |
| `POST /pnlExit` | Daily profit/loss exit |
| `DELETE /positions` | Exit all positions |
| `GET /trades` | Trade book |
| `GET /trades/{from}/{to}/{page}` | Historical trade charges |

Use historical trade history to calibrate real backtest costs:

```text
brokerage
STT
exchange transaction charges
stamp duty
SEBI tax
GST
slippage
```

---

# 3. Position Management Framework for Naked Option Buying

A professional naked option buying system should have **six layers**:

```text
1. Regime filter
2. Pre-trade option filter
3. Entry execution
4. Position sizing
5. Active position management
6. Daily/portfolio risk control
```

---

# 4. Layer 1: Regime Filter

Before taking any naked option trade, classify the market regime.

## Regimes

| Regime | Description | Best option-buying strategies |
|---|---|---|
| Strong trend | Spot trending with momentum | Breakouts, VWAP trend, gamma squeeze |
| Rangebound | Spot stuck between levels | Mean reversion, CPR/pivot rejection |
| Volatility contraction | Tight range, low ATR, low IV | VCP, Bollinger squeeze, IV expansion |
| Volatility expansion | Large candles, high ATR | Momentum continuation, breakout riding |
| Expiry pinning | Spot gravitating to OI wall | Max pain, OI wall strategies |
| Event/news | Sudden information shock | News momentum, avoid pre-event buying |
| Choppy whipsaw | Frequent fake breakouts | Reduce size or no trade |

## Useful regime indicators

| Indicator | Use |
|---|---|
| ATR | Volatility state |
| Choppiness Index | Trend vs chop |
| ADX | Trend strength |
| Bollinger Band width | Squeeze/expansion |
| CPR width | Wide CPR = range, narrow CPR = trend |
| IV percentile | Cheap/expensive options |
| OI distribution | Pinning or breakout potential |
| VWAP slope | Institutional trend |
| India VIX | Overall volatility regime |

---

# 5. Layer 2: Pre-Trade Option Filters

Before buying a specific CE/PE, check the option itself.

## A. Liquidity filter

Use option chain or quote:

```text
bid
ask
volume
OI
```

Rules:

```text
Reject trade if bid-ask spread is too wide.
Reject trade if volume is too low.
Reject trade if OI is too low.
```

Example:

```text
spread_pct = (ask - bid) / mid_price * 100

Reject if spread_pct > 5% to 10%
```

For NIFTY ATM options, spread is usually tight.

For SENSEX or OTM strikes, spread can be dangerous.

---

## B. Delta filter

For naked option buying, avoid extremes.

| Delta | Meaning | Use |
|---:|---|---|
| 0.05–0.20 | Far OTM | Lottery ticket, high theta decay |
| 0.25–0.40 | OTM | Aggressive, needs strong momentum |
| 0.40–0.65 | ATM/near ITM | Best balance for intraday option buying |
| 0.70–0.95 | Deep ITM | Moves like spot, less leverage |

Recommended intraday naked buying zone:

```text
Delta: 0.35 to 0.70
```

For strong momentum strategies:

```text
Delta: 0.25 to 0.50
```

For safer directional exposure:

```text
Delta: 0.50 to 0.70
```

---

## C. Theta filter

Theta is your enemy.

Before buying, estimate:

```text
expected_holding_period_theta_cost = theta_per_minute * expected_minutes
```

Your expected profit must be much larger than theta cost.

Rule:

```text
Target profit > 2 × expected theta cost + expected slippage + charges
```

If not, skip trade.

---

## D. Vega / IV filter

Do not buy naked options when IV is extremely high unless you expect an even larger volatility expansion.

Use:

```text
IV rank
IV percentile
```

Example:

```text
IV_rank = (current_iv - 30_day_low_iv) / (30_day_high_iv - 30_day_low_iv)
```

Rules:

```text
Avoid long options if IV_rank > 75%
Prefer long options if IV_rank < 40% and breakout expected
```

Exception:

```text
Event-driven volatility expansion may justify high IV entry.
```

---

## E. OI filter

Use OI to understand option writer positioning.

For CE buying:

```text
Large Call OI above spot = resistance
If spot breaks that Call OI wall, short covering may fuel rally
```

For PE buying:

```text
Large Put OI below spot = support
If spot breaks that Put OI wall, put writers may panic and fuel fall
```

Useful signals:

| Condition | Meaning |
|---|---|
| Price up + Call OI down | Short covering |
| Price up + Call OI up | Fresh call writing, resistance |
| Price down + Put OI down | Put unwinding |
| Price down + Put OI up | Fresh put writing, support |
| Price up + Put OI up | Bullish support building |
| Price down + Call OI up | Bearish resistance building |

---

## F. Bid/ask and depth filter

For live trading:

```text
bid_qty
ask_qty
best_bid
best_ask
depth_20
```

Useful rules:

```text
Do not buy if ask side is thin and spread wide.
Do not buy if large ask wall is sitting just above.
Prefer entry when bid support is building.
```

Depth imbalance:

```text
depth_imbalance = bid_qty / (bid_qty + ask_qty)
```

Interpretation:

```text
depth_imbalance > 0.60 → buying pressure
depth_imbalance < 0.40 → selling pressure
```

But be careful: depth can be spoofed.

---

# 6. Layer 3: Entry Execution

For naked option buying, execution matters enormously.

## A. Use LIMIT orders by default

Avoid MARKET orders in options unless liquidity is excellent.

Dhan order types:

```text
LIMIT
MARKET
STOP_LOSS
STOP_LOSS_MARKET
```

Recommended:

```text
Use LIMIT near ask or slightly above ask for urgent entry.
```

---

## B. Enter on confirmed candle, not prediction

Use:

```text
Signal candle close → pending entry → next candle open
```

This avoids look-ahead bias in backtesting and reduces false entries in live trading.

---

## C. Slippage model

For backtest, use:

```text
entry_price = signal_open + slippage
exit_price = exit_level - slippage
```

Suggested slippage:

| Option type | Slippage assumption |
|---|---:|
| NIFTY ATM | 0.05%–0.15% |
| NIFTY OTM | 0.15%–0.50% |
| SENSEX ATM | 0.10%–0.30% |
| SENSEX OTM | 0.30%–1.00% |

Calibrate using your real trade history.

---

# 7. Layer 4: Position Sizing

Naked option buying has frequent small losses. Position sizing must be small.

## A. Fixed fractional risk

Risk per trade:

```text
0.25% to 1% of capital
```

Example:

```text
capital = 1,000,000
risk_per_trade = 0.5% = 5,000
option_entry = 100
option_stop = 75
risk_per_unit = 25
lot_size = 25

risk_per_lot = 25 × 25 = 625
lots = floor(5000 / 625) = 8 lots
```

But check margin and liquidity.

---

## B. Premium-based sizing

Alternative:

```text
max_premium_deployed = capital × 2% to 5%
```

Example:

```text
capital = 1,000,000
max_premium = 3% = 30,000
option_premium = 120
lot_size = 25
premium_per_lot = 120 × 25 = 3,000
lots = floor(30,000 / 3,000) = 10 lots
```

This is simpler but less precise than risk-based sizing.

---

## C. Volatility-adjusted sizing

Reduce size when ATR/IV is high.

```text
position_size = base_size / volatility_multiplier
```

Example:

```text
If ATR is 1.5× normal, reduce size by 33%.
If IV is 2× normal, reduce size by 50%.
```

---

# 8. Layer 5: Active Position Management

Once inside a naked option trade, monitor all dimensions.

You should track:

```text
option premium
spot price
delta
gamma
theta
vega
IV
OI
volume
bid/ask
depth
VWAP
ATR
time elapsed
moneyness
```

---

## A. Premium behavior

| Observation | Meaning | Action |
|---|---|---|
| Spot moves in favor, premium does not | IV crush or low delta | Exit or reduce |
| Spot stalls, premium decays | Theta bleeding | Time stop |
| Premium spikes without spot move | IV spike/news | Take partial profit |
| Premium falls despite spot move | Vega crush or wrong strike | Exit |
| Premium lags ATP | Weak demand | Avoid/exit |
| Premium breaks above ATP with volume | Strength | Hold/trail |

---

## B. Spot behavior

For CE:

```text
Bullish if spot above VWAP, making higher highs and higher lows.
Bearish if spot loses VWAP or breaks market structure.
```

For PE:

```text
Bullish for PE if spot below VWAP, making lower lows and lower highs.
Bearish for PE if spot reclaims VWAP.
```

---

## C. IV behavior

For long options:

```text
IV rising = helpful
IV falling = harmful
```

Rules:

```text
If IV falls 10%–15% from entry and trade is not working, exit.
If IV falls sharply even while spot moves in favor, consider exit.
```

---

## D. OI behavior

For long CE:

```text
Spot rising + Call OI falling = short covering, bullish
Spot rising + Call OI rising = fresh call writing, possible resistance
Spot rising + Put OI rising = put writers confident support, bullish
Spot rising + Put OI falling = put unwinding, weak bullish
```

For long PE:

```text
Spot falling + Put OI falling = put unwinding, bearish
Spot falling + Put OI rising = fresh put writing, possible support
Spot falling + Call OI falling = call unwinding/short covering, bearish
Spot falling + Call OI rising = fresh call writing, resistance, bearish
```

---

## E. Greeks behavior

### Delta

For CE:

```text
Delta increases as spot rises.
Delta decreases as spot falls.
```

For PE:

```text
Delta becomes more negative as spot falls.
Delta moves toward zero as spot rises.
```

Use delta for trailing:

```text
As delta increases, option becomes more sensitive to spot.
Tighten spot-based trailing.
```

---

### Gamma

Gamma is highest near ATM and near expiry.

High gamma means:

```text
Premium accelerates fast in your favor.
Premium also collapses fast against you.
```

Near expiry:

```text
Reduce holding time.
Use tighter time stops.
Take partial profits faster.
```

---

### Theta

Theta accelerates as expiry approaches.

Rules:

```text
Do not hold naked long options through consolidation.
Use time stops.
Exit if expected move does not happen quickly.
```

---

### Vega

Vega matters more for:

```text
weekly options before expiry
event days
low IV contraction breakouts
```

Rules:

```text
Buy when IV is low and expected to expand.
Avoid buying when IV is already elevated.
Exit if IV crush begins.
```

---

# 9. Exit Hierarchy for Naked Option Buying

When multiple exit signals occur, use strict priority.

Recommended priority:

```text
1. Hard stop loss
2. Liquidity failure
3. Time stop
4. Vega crush
5. OI unwinding / adverse OI divergence
6. Spot structure break
7. Trailing stop
8. Target/profit booking
9. End-of-day exit
```

---

## 1. Hard stop loss

Protect capital.

Example:

```text
Exit if option premium falls 25%–35% from entry.
```

Or spot-based:

```text
Exit if spot breaks entry candle low for CE.
Exit if spot breaks entry candle high for PE.
```

---

## 2. Liquidity failure

Exit if:

```text
bid-ask spread widens beyond threshold
bid quantity disappears
ask quantity overwhelms bid
option becomes illiquid
```

---

## 3. Time stop

Naked options need immediate movement.

Example:

```text
If trade does not reach 20% profit within 20–45 minutes, exit.
```

For expiry day:

```text
Time stop should be shorter: 10–20 minutes.
```

---

## 4. Vega crush

Exit if:

```text
current_iv < entry_iv × 0.85
```

Meaning IV fell 15%.

---

## 5. OI unwinding

For CE:

```text
If spot is rising but Call OI at your strike or ATM falls sharply, exit.
```

For PE:

```text
If spot is falling but Put OI at your strike or ATM falls sharply, exit.
```

Example:

```text
current_oi < entry_oi × 0.80
```

---

## 6. Spot structure break

For CE:

```text
Exit if spot closes below VWAP after being above.
Exit if spot breaks previous 5-min swing low.
Exit if spot loses broken OI wall.
```

For PE:

```text
Exit if spot closes above VWAP after being below.
Exit if spot breaks previous 5-min swing high.
Exit if spot reclaims broken OI wall.
```

---

## 7. Trailing stop

Use trailing only after trade reaches profit.

Examples:

```text
Activate trail after 30%–50% profit.
Move SL to breakeven after 1R profit.
Use delta-adjusted ATR trail.
```

---

## 8. Target/profit booking

Use partial booking:

```text
Book 50% at 1:1.5 or 1:2 reward.
Trail remaining portion.
```

---

## 9. End-of-day exit

For intraday naked option buying:

```text
Exit all by 15:10–15:15 IST.
```

For expiry day:

```text
Exit earlier, e.g. 14:45–15:00, unless strategy specifically trades expiry gamma.
```

---

# 10. Daily and Portfolio Risk Controls

Use Dhan Trader’s Control APIs.

## A. Daily loss limit

Use:

```http
POST https://api.dhan.co/v2/pnlExit
```

Example:

```json
{
  "profitValue": 10000,
  "lossValue": 5000,
  "productType": ["INTRADAY"],
  "enableKillSwitch": true
}
```

This can automatically stop trading after daily loss.

---

## B. Kill switch

Use:

```http
POST https://api.dhan.co/v2/killswitch?killSwitchStatus=ACTIVATE
```

Activate when:

```text
daily loss limit hit
system malfunction
abnormal market
data feed failure
order execution failure
```

---

## C. Exit all positions

Use:

```http
DELETE https://api.dhan.co/v2/positions
```

For emergency flatten.

---

## D. Max trades per day

Example:

```text
Max 2–4 naked option trades per day.
```

Overtrading destroys option buyers.

---

## E. Max concurrent risk

Example:

```text
Max open option premium risk: 2%–4% of capital.
```

Do not buy multiple OTM options simultaneously unless they are part of a defined strategy.

---

# 11. Naked Option Buying Strategy Catalog for NIFTY / SENSEX

There is no finite “complete list” of all strategies, but below is a practical exhaustive catalog of commonly used and custom naked option buying strategies.

They are grouped by edge type.

---

## Category A: Opening and Time-Based Strategies

| # | Strategy | Edge | Entry | Exit/Trail | Dhan Data Needed |
|---:|---|---|---|---|---|
| 1 | 5-minute Opening Range Breakout | Early momentum | Buy CE/PE when 5-min OR breaks | SL opposite OR, trail VWAP | Index OHLC, option OHLC |
| 2 | 15-minute Opening Range Breakout | Institutional opening flow | Buy CE above 15-min high, PE below low | SL mid-range, target 1:2 | Index OHLC, option volume |
| 3 | 30-minute Opening Range Breakout | More stable breakout | Buy break of first 30-min range | Trail 20 EMA | Index OHLC |
| 4 | First Candle Reversal | Rejection of opening extreme | Buy CE if first candle low holds and price reclaims high | SL below first candle low | Index OHLC |
| 5 | 9:15–9:30 Fake Breakout Reversal | Trap traders | Fade fake ORB with confirmation | SL beyond trap wick | Index OHLC, volume |
| 6 | 9:45 Momentum Continuation | Early trend confirmation | Buy continuation after first pullback | Trail VWAP | Index OHLC, VWAP |
| 7 | 10:15 Reversal | Morning exhaustion | Buy reversal at VWAP/pivot | Target VWAP/POC | VWAP, CPR |
| 8 | Pre-Lunch Breakout | Position squaring before lunch | Buy breakout before 11:30 | Exit by 12:30 if no move | Index OHLC |
| 9 | Afternoon Breakout | European market/open interest shift | Buy breakout after 13:30 | Trail ATR | Index OHLC, OI |
| 10 | Last Hour Momentum | Institutional closing flows | Buy momentum after 14:15 | Exit by 15:10 | Index OHLC, volume |
| 11 | Expiry Zero-Hero | Gamma explosion near expiry | Buy ATM/OTM on expiry breakout | Very tight time stop | Option chain, gamma |
| 12 | 2 PM Expiry Move | OI unwinding/pinning | Buy direction away from OI wall | Exit by 15:00 | OI, max pain |

---

## Category B: Trend and Momentum Breakout Strategies

| # | Strategy | Edge | Entry | Exit/Trail | Dhan Data Needed |
|---:|---|---|---|---|---|
| 13 | VWAP Breakout | Institutional trend | Buy CE when price breaks above VWAP with volume | SL below VWAP | VWAP, volume |
| 14 | VWAP Reclaim | Failed breakdown reversal | Buy CE when price reclaims VWAP | SL below reclaim candle | VWAP |
| 15 | CPR Breakout | Pivot-based expansion | Buy break of TC/BC | SL inside CPR | CPR |
| 16 | Narrow CPR Trend Day | Narrow CPR often trends | Buy first pullback in trend | Trail 20 EMA | CPR, EMA |
| 17 | Previous Day High Breakout | Break of prior resistance | Buy CE above PDH | SL below breakout candle | Daily OHLC |
| 18 | Previous Day Low Breakdown | Break of prior support | Buy PE below PDL | SL above breakdown candle | Daily OHLC |
| 19 | Previous Week High/Low Breakout | Larger structural breakout | Buy CE/PE on break | Trail weekly structure | Daily OHLC |
| 20 | ATR Expansion Breakout | Volatility expansion | Buy when candle range > 1.5× ATR | Trail ATR | ATR |
| 21 | Bollinger Band Squeeze Breakout | Volatility contraction | Buy break after BB width contraction | Trail middle band | Bollinger Bands |
| 22 | Keltner Channel Squeeze | TTM squeeze style | Buy when volatility expands | Trail EMA | Keltner/EMA |
| 23 | VCP Breakout | Tightening consolidation | Buy break of tight pattern | SL below pattern | Price structure |
| 24 | ADX Momentum | Trend strength filter | Buy only if ADX > 20–25 | Trail Supertrend | ADX |
| 25 | Supertrend Breakout | Simple trend following | Buy CE/PE on Supertrend flip | Trail Supertrend | Supertrend |
| 26 | EMA Pullback | Trend continuation | Buy pullback to 9/20 EMA | SL below pullback low | EMA |
| 27 | Vortex Crossover | Directional momentum | Buy CE when VI+ crosses VI- | Trail VI | Vortex |
| 28 | MACD Momentum | Momentum confirmation | Buy when MACD histogram expands | Trail EMA | MACD |
| 29 | RSI Breakout | Momentum threshold | Buy when RSI crosses 60 for CE | SL below swing low | RSI |
| 30 | Momentum Burst | Sudden large displacement | Buy large candle with volume | Tight time stop | Volume, OHLC |

---

## Category C: Mean Reversion Strategies

| # | Strategy | Edge | Entry | Exit/Trail | Dhan Data Needed |
|---:|---|---|---|---|---|
| 31 | VWAP Mean Reversion | Price returns to VWAP | Buy CE when oversold below VWAP and rejects | Target VWAP | VWAP |
| 32 | CPR Pivot Rejection | Structural reversal | Buy CE at BC rejection, PE at TC rejection | SL beyond wick | CPR |
| 33 | Camarilla Reversal | Intraday pivot reversal | Buy at H3/L3 rejection | Target H4/L4 | Camarilla |
| 34 | Volume Profile HVN Rejection | High volume node acts as magnet/wall | Buy rejection at HVN | Target POC | Volume profile |
| 35 | Volume Profile LVN Break | Low volume node fast move | Buy break through LVN | Trail POC | Volume profile |
| 36 | Bollinger Band Reversion | Extreme deviation reversal | Buy CE at lower band rejection | Target middle band | Bollinger |
| 37 | RSI Divergence | Momentum exhaustion | Buy CE when spot makes lower low but RSI higher | SL below low | RSI |
| 38 | OI Extreme Reversal | Overwritten strike reverses | Buy opposite direction when OI wall fails | SL beyond wall | OI |
| 39 | PCR Extreme Reversal | Sentiment extreme | Buy CE when PCR extremely low and spot stabilizes | SL below low | PCR/OI |
| 40 | Gap Fill Strategy | Gaps often fill | Buy direction toward gap fill | Target gap edge | Daily OHLC |

---

## Category D: Options Flow / OI Strategies

| # | Strategy | Edge | Entry | Exit/Trail | Dhan Data Needed |
|---:|---|---|---|---|---|
| 41 | Call OI Wall Break | Call writers trapped | Buy CE when spot breaks highest Call OI strike | Trail broken wall | Option chain OI |
| 42 | Put OI Wall Break | Put writers trapped | Buy PE when spot breaks highest Put OI strike | Trail broken wall | Option chain OI |
| 43 | Short Covering Rally | Call writers buying back | Buy CE when price up + Call OI down | Trail spot | OI, price |
| 44 | Put Unwinding Fall | Put writers exiting | Buy PE when price down + Put OI down | Trail spot | OI, price |
| 45 | Fresh Call Writing Fade | Resistance building | Buy PE when Call OI rises strongly at resistance | SL above resistance | OI |
| 46 | Fresh Put Writing Support | Support building | Buy CE when Put OI rises strongly at support | SL below support | OI |
| 47 | Max Pain Reversal | Expiry pinning | Buy option toward max pain | Exit near max pain | OI, max pain |
| 48 | Max Pain Divergence | Spot too far from pain | Buy direction toward max pain after 13:30 | SL beyond recent extreme | OI |
| 49 | PCR Trend | Sentiment shift | Buy CE when PCR rises from low | Trail spot | PCR |
| 50 | OI Divergence | Price/OI disagreement | Exit or fade weak moves | Use structure | OI |
| 51 | Gamma Squeeze | ATM gamma explosion | Buy ATM when OI wall breaks near expiry | Trail loosely | Gamma, OI |
| 52 | Strike Migration | Spot moving through strikes | Roll/trail with new ATM | Use actual entered strike for P&L | Rolling option panel |

---

## Category E: Volatility / IV Strategies

| # | Strategy | Edge | Entry | Exit/Trail | Dhan Data Needed |
|---:|---|---|---|---|---|
| 53 | IV Contraction Breakout | Cheap options before expansion | Buy when IV low and range breaks | Trail ATR | IV, ATR |
| 54 | IV Percentile Low | Options cheap historically | Buy ATM when IV percentile < 30 | Time stop | IV history |
| 55 | IV Expansion Confirmation | Volatility confirming move | Buy only if IV rises with breakout | Trail spot | IV |
| 56 | Avoid IV Crush | Prevent overpaying | Skip if IV rank > 75 | N/A | IV rank |
| 57 | Event Volatility Expansion | News-driven expansion | Buy after confirmed event move | Tight trail | IV, news |
| 58 | India VIX Breakout | Market-wide volatility expansion | Buy index options when VIX spikes and spot breaks | Trail spot | India VIX external |
| 59 | Theta Budget Entry | Only take trades with enough expected move | Enter if expected move > 2× theta cost | Time stop | Greeks |
| 60 | Vega Trail | Exit when volatility dies | Exit if IV drops 10%–15% | N/A | IV |

---

## Category F: Expiry-Day Specific Strategies

| # | Strategy | Edge | Entry | Exit/Trail | Dhan Data Needed |
|---:|---|---|---|---|---|
| 61 | Expiry Morning Breakout | Gamma burst | Buy first 15-min break | Tight SL | OHLC |
| 62 | Expiry OI Wall Break | Writers trapped late | Buy break of biggest OI strike | Trail broken strike | OI |
| 63 | Expiry Max Pain Pin | Spot pinned to pain | Buy option toward max pain | Exit near pain | Max pain |
| 64 | Expiry Afternoon Gamma | Late volatility | Buy breakout after 13:30 | Time stop | Gamma, OI |
| 65 | Zero-Hero Momentum | OTM/ATM explosive move | Buy ATM/OTM on strong breakout | Very tight stop | Gamma, volume |
| 66 | Expiry Reversal from OI Wall | Wall holds | Buy reversal at OI wall | SL beyond wall | OI |
| 67 | Expiry Short Covering | Writers square off | Buy direction of OI unwind | Trail spot | OI change |
| 68 | Expiry Theta Fade Avoidance | Avoid decay traps | Skip if no move in 10 min | Time stop | Time, premium |

---

## Category G: Gap and Global Cue Strategies

| # | Strategy | Edge | Entry | Exit/Trail | Dhan Data Needed |
|---:|---|---|---|---|---|
| 69 | Gap and Go | Strong global cue continuation | Buy first pullback after gap up/down | Trail VWAP | OHLC, global cues external |
| 70 | Gap Fill | Gap exhaustion | Buy direction toward gap fill | Target gap edge | OHLC |
| 71 | Gap Fade | Overreaction reversal | Buy reversal after failed gap move | SL beyond extreme | OHLC |
| 72 | Global Cue Momentum | NIFTY follows global markets | Buy if global + spot confirms | Trail spot | External global data |
| 73 | BankNifty Confirmation | Financials lead index | Buy NIFTY CE if BANKNIFTY confirms | Trail spot | BANKNIFTY data |
| 74 | NIFTY-BANKNIFTY Divergence | Relative strength | Buy stronger index | Trail relative strength | Index data |

---

## Category H: Microstructure / Depth Strategies

| # | Strategy | Edge | Entry | Exit/Trail | Dhan Data Needed |
|---:|---|---|---|---|---|
| 75 | Bid Wall Absorption | Large bids absorbing sells | Buy CE when bid wall holds and price ticks up | SL below bid wall | Depth |
| 76 | Ask Wall Break | Large ask wall consumed | Buy CE when ask wall breaks | Trail broken wall | Depth |
| 77 | Depth Imbalance Momentum | Order book pressure | Buy when bid/ask imbalance > threshold | Trail spot | Depth |
| 78 | ATP Strength | Price above average traded price | Buy CE when LTP > ATP and volume rises | SL below ATP | ATP |
| 79 | LTQ Spike | Sudden large trades | Buy on large LTQ with price movement | Tight time stop | LTQ |
| 80 | Total Buy/Sell Quantity Shift | Demand/supply shift | Buy when total buy qty rises sharply | Trail spot | Quote data |

---

## Category I: Composite / Custom Strategies

These are often the best because they combine filters.

| # | Composite Strategy | Components |
|---:|---|---|
| 81 | ORB + OI Wall Break | 15-min breakout + highest Call/Put OI break |
| 82 | VWAP + CPR + Volume | VWAP reclaim + CPR breakout + volume spike |
| 83 | VCP + IV Percentile | Tight consolidation + low IV + breakout |
| 84 | Gamma Squeeze + OI Unwind | ATM OI wall break + Call OI falling |
| 85 | Expiry Max Pain + OI Wall | Max pain distance + OI wall break |
| 86 | Delta-ATR Momentum | Delta > 0.4 + ATR expansion + VWAP trend |
| 87 | IV Expansion + ADX | IV rising + ADX > 25 + breakout |
| 88 | Depth + VWAP | Bid wall + VWAP reclaim |
| 89 | PCR Extreme + CPR Rejection | PCR extreme + pivot rejection |
| 90 | Time + Theta Budget | Only trade if expected move > theta cost before 11:00 |

---

# 12. Trailing Strategies for Naked Option Buying

This is the most important part.

The golden rule:

```text
Do not trail only the option premium.
Trail the underlying spot or market structure, adjusted for option Greeks.
```

Why?

Because option premium is noisy due to:

```text
bid-ask spread
IV changes
theta decay
gamma acceleration
low liquidity
```

---

## Trail 1: Fixed Premium Percent Trail

Example:

```text
Trail SL 20% below highest premium since entry.
```

Pros:

```text
Simple
```

Cons:

```text
Ignores spot structure
Gets stopped by noise
Bad for options
```

Use only as secondary hard protection.

---

## Trail 2: Breakeven Trail

Example:

```text
Move SL to entry after 1R profit or 30% premium profit.
```

Pros:

```text
Protects capital
```

Cons:

```text
May exit too early in volatile trend
```

Recommended:

```text
Use breakeven after meaningful profit, not immediately.
```

---

## Trail 3: Spot Swing Structure Trail

For CE:

```text
Trail SL below latest 5-min swing low.
```

For PE:

```text
Trail SL above latest 5-min swing high.
```

Pros:

```text
Uses market structure
More stable than premium trail
```

Cons:

```text
Lagging
```

Good for:

```text
trend following
VWAP strategies
breakouts
```

---

## Trail 4: ATR Trail

For CE:

```text
trail_sl = max(previous_trail_sl, spot - ATR × multiplier)
```

For PE:

```text
trail_sl = min(previous_trail_sl, spot + ATR × multiplier)
```

Suggested multiplier:

```text
1.0 to 2.0
```

Pros:

```text
Adapts to volatility
```

Cons:

```text
Does not account for option delta
```

---

## Trail 5: Delta-Adjusted ATR Trail

This is one of the best for naked options.

Formula:

```text
trail_distance = ATR × multiplier × abs(delta)
```

For CE:

```text
trail_sl = max(previous_trail_sl, spot - trail_distance)
```

For PE:

```text
trail_sl = min(previous_trail_sl, spot + trail_distance)
```

Example:

```text
ATR = 15
multiplier = 1.5
delta = 0.50

trail_distance = 15 × 1.5 × 0.50 = 11.25 points
```

Later:

```text
delta = 0.85
trail_distance = 15 × 1.5 × 0.85 = 19.125 points
```

Interpretation:

```text
As delta increases, option premium becomes more sensitive.
You can trail using a wider spot distance but still protect premium.
```

Alternative:

```text
trail_distance = ATR × multiplier / delta
```

Use the version that backtests better for your strategy.

---

## Trail 6: Gamma-Adjusted Trail

Gamma is highest:

```text
near ATM
near expiry
```

High gamma means premium can explode or collapse.

Rule:

```text
When gamma is high, tighten trail and take partial profits.
When gamma is low, allow wider trail.
```

Example:

```text
if gamma > gamma_threshold:
    multiplier = 1.0
else:
    multiplier = 1.5
```

For expiry day:

```text
Use smaller multiplier.
Take partials faster.
```

---

## Trail 7: Theta/Time Trail

Naked options need speed.

Rule:

```text
If expected move does not happen within time limit, exit.
```

Example:

```text
If profit < 20% after 30 minutes, exit.
If profit < 10% after 15 minutes on expiry day, exit.
```

This is not a trailing stop but a critical exit rule.

---

## Trail 8: VWAP Trail

For CE:

```text
Hold only while spot is above VWAP.
Exit if 5-min candle closes below VWAP.
```

For PE:

```text
Hold only while spot is below VWAP.
Exit if 5-min candle closes above VWAP.
```

Pros:

```text
Institutional benchmark
Works well in trend
```

Cons:

```text
Whipsaw in range
```

---

## Trail 9: EMA Trail

Use:

```text
9 EMA for aggressive momentum
20 EMA for normal trend
50 EMA for slower trend
```

For CE:

```text
Exit if 5-min candle closes below 20 EMA.
```

For PE:

```text
Exit if 5-min candle closes above 20 EMA.
```

---

## Trail 10: Supertrend Trail

Use Supertrend on 5-min or 15-min spot.

For CE:

```text
Exit when Supertrend flips bearish.
```

For PE:

```text
Exit when Supertrend flips bullish.
```

Pros:

```text
Simple
Objective
```

Cons:

```text
Lagging
```

---

## Trail 11: CPR / Pivot Trail

For CE:

```text
After breaking TC, trail SL to TC or BC.
After breaking R1, trail SL to TC/R1.
```

For PE:

```text
After breaking BC, trail SL to BC or TC.
After breaking S1, trail SL to BC/S1.
```

Good for:

```text
pivot-based strategies
CPR breakout
mean reversion
```

---

## Trail 12: Volume Profile POC Trail

Use developing intraday volume profile.

For CE:

```text
Trail SL below developing POC or HVN.
```

For PE:

```text
Trail SL above developing POC or HVN.
```

Pros:

```text
Uses actual traded volume
Institutional reference
```

Cons:

```text
Requires volume profile calculation
```

---

## Trail 13: OI Wall Trail

For CE:

```text
When spot breaks a large Call OI strike, that strike becomes support.
Trail SL above broken Call OI strike + buffer.
```

Example:

```text
22000 Call OI wall broken.
Trail SL at 22000 + 10 points.
```

For PE:

```text
When spot breaks a large Put OI strike, that strike becomes resistance.
Trail SL below broken Put OI strike - buffer.
```

This is very useful for NIFTY/SENSEX expiry days.

---

## Trail 14: IV-Based Trail

For long options:

```text
If IV drops sharply, exit or tighten.
```

Rule:

```text
If current_iv < entry_iv × 0.85, exit.
```

Or:

```text
If IV drops 10%, tighten trail by 30%.
```

This protects against vega crush.

---

## Trail 15: Bid/Ask Trail

For live trading only.

Exit if:

```text
bid disappears
spread widens
ask size overwhelms bid size
```

Example:

```text
If bid_qty falls below 20% of entry-time bid_qty, exit.
If spread_pct > 10%, exit.
```

---

## Trail 16: Depth Imbalance Trail

Use 5/20/200-level depth.

For CE:

```text
Exit if depth_imbalance falls below 0.35.
```

For PE:

```text
Exit if depth_imbalance rises above 0.65.
```

Use with caution because depth can be spoofed.

---

## Trail 17: Partial Profit Scaling

This is one of the best for naked options.

Example:

```text
Buy 2 lots.
At 1:1.5 profit, sell 1 lot.
Move SL to breakeven for remaining lot.
Trail remaining lot loosely.
```

Pros:

```text
Books profit
Reduces theta risk
Allows gamma ride
```

---

## Trail 18: Moneyness-Based Trail

As option becomes ITM:

```text
Delta increases.
Premium behaves more like spot.
Tighten spot trail.
```

As option becomes OTM:

```text
Delta decreases.
Premium decays.
Exit faster.
```

Rule:

```text
If option delta falls below 0.25 after entry, exit.
```

For CE:

```text
Delta falling means spot is falling or IV collapsing.
```

For PE:

```text
Delta moving toward zero means spot is rising or IV collapsing.
```

---

## Trail 19: Time-of-Day Trail

Morning:

```text
Allow wider trail because volatility and momentum are higher.
```

Afternoon:

```text
Tighten trail because theta accelerates and liquidity may drop.
```

Expiry day:

```text
Very tight time and profit rules.
```

Example:

```text
Before 11:00: max hold 60 minutes
11:00–13:30: max hold 45 minutes
After 13:30: max hold 30 minutes
Expiry after 14:00: max hold 15 minutes
```

---

## Trail 20: Composite Trail Score

Create a score:

```text
trail_score =
    trend_strength_score
  + delta_score
  + iv_score
  + oi_score
  + volume_score
  + time_score
```

Example:

```text
If trail_score > 70 → wide trail
If trail_score 40–70 → normal trail
If trail_score < 40 → tight trail or exit
```

Components:

| Component | Positive | Negative |
|---|---|---|
| Trend | Spot above VWAP, higher highs | Spot below VWAP |
| Delta | Delta expanding | Delta shrinking |
| IV | IV rising/stable | IV falling |
| OI | Supportive OI buildup | Adverse OI unwinding |
| Volume | Volume expanding | Volume drying |
| Time | Early in session | Late in session |

---

# 13. Recommended Trailing Matrix

| Market Condition | Best Trailing Method |
|---|---|
| Strong trend day | Delta-adjusted ATR + VWAP + partial scaling |
| Morning breakout | VWAP trail + 5-min swing low/high |
| Choppy range | Tight target, no wide trail, CPR/pivot exits |
| Low IV contraction breakout | ATR trail + IV-based trail |
| Expiry day | Gamma-adjusted trail + OI wall trail + time stop |
| High IV event move | Partial booking + IV crush exit |
| OI-driven squeeze | OI wall trail + short-covering exit |
| Depth-driven move | Bid/ask imbalance trail |

---

# 14. Position Manager Pseudocode

Below is a Ruby-style pseudocode structure.

```ruby
class NakedOptionPositionManager
  HARD_SL_PCT          = 0.30
  TIME_STOP_SECONDS    = 30 * 60
  MIN_PROFIT_FOR_TIME  = 0.20
  VEGA_CRUSH_PCT       = 0.15
  OI_UNWIND_PCT        = 0.20
  TRAIL_ACTIVATE_PCT   = 0.35
  EOD_EXIT             = "15:15"

  def evaluate(position, mkt, index_state)
    # mkt contains option and underlying data
    #
    # mkt = {
    #   ts:
    #   option_close:
    #   option_bid:
    #   option_ask:
    #   option_volume:
    #   option_oi:
    #   iv:
    #   delta:
    #   gamma:
    #   theta:
    #   vega:
    #   spot:
    #   vwap:
    #   atr:
    #   swing_low:
    #   swing_high:
    #   broken_oi_wall:
    #   spread_pct:
    # }

    # 1. Hard stop loss
    if mkt[:option_close] <= position[:entry_price] * (1 - HARD_SL_PCT)
      return { exit: true, reason: "HARD_SL" }
    end

    # 2. Liquidity failure
    if mkt[:spread_pct] > 10.0
      return { exit: true, reason: "LIQUIDITY_FAILURE" }
    end

    # 3. Time stop
    elapsed = mkt[:ts] - position[:entry_time]
    profit_pct = (mkt[:option_close] - position[:entry_price]) / position[:entry_price]

    if elapsed >= TIME_STOP_SECONDS && profit_pct < MIN_PROFIT_FOR_TIME
      return { exit: true, reason: "TIME_STOP" }
    end

    # 4. Vega crush
    if position[:entry_iv] && mkt[:iv] < position[:entry_iv] * (1 - VEGA_CRUSH_PCT)
      return { exit: true, reason: "VEGA_CRUSH" }
    end

    # 5. OI unwinding
    if position[:entry_oi] && mkt[:option_oi] < position[:entry_oi] * (1 - OI_UNWIND_PCT)
      if position[:side] == "CE" && mkt[:spot] > position[:entry_spot]
        return { exit: true, reason: "OI_UNWINDING" }
      end

      if position[:side] == "PE" && mkt[:spot] < position[:entry_spot]
        return { exit: true, reason: "OI_UNWINDING" }
      end
    end

    # 6. Spot structure break
    if position[:side] == "CE" && mkt[:spot] < mkt[:vwap] && position[:was_above_vwap]
      return { exit: true, reason: "VWAP_LOSS" }
    end

    if position[:side] == "PE" && mkt[:spot] > mkt[:vwap] && position[:was_below_vwap]
      return { exit: true, reason: "VWAP_RECLAIM" }
    end

    # 7. Activate trailing
    if profit_pct >= TRAIL_ACTIVATE_PCT
      position[:trailing_active] = true
    end

    if position[:trailing_active]
      trail = calculate_delta_atr_trail(position, mkt)

      if position[:side] == "CE"
        position[:trail_sl] = [position[:trail_sl] || -Float::INFINITY, trail].max

        if mkt[:spot] <= position[:trail_sl]
          return { exit: true, reason: "DELTA_ATR_TRAIL" }
        end
      end

      if position[:side] == "PE"
        position[:trail_sl] = [position[:trail_sl] || Float::INFINITY, trail].min

        if mkt[:spot] >= position[:trail_sl]
          return { exit: true, reason: "DELTA_ATR_TRAIL" }
        end
      end
    end

    # 8. Target/profit booking
    if profit_pct >= 0.60
      return { exit: true, reason: "TARGET_HIT", partial: true }
    end

    # 9. EOD exit
    if mkt[:ts].strftime("%H:%M") >= EOD_EXIT
      return { exit: true, reason: "EOD_EXIT" }
    end

    { exit: false }
  end

  private

  def calculate_delta_atr_trail(position, mkt)
    multiplier = 1.5
    delta = mkt[:delta].abs
    delta = 0.5 if delta.nil? || delta.zero?

    distance = mkt[:atr] * multiplier * delta

    if position[:side] == "CE"
      mkt[:spot] - distance
    else
      mkt[:spot] + distance
    end
  end
end
```

---

# 15. Backtesting Limitations and How to Handle Them

## A. No historical Greeks

Dhan rolling option data does not provide historical Greeks.

Solution:

Compute approximate Greeks using Black-Scholes.

Inputs:

```text
spot
strike
IV
time to expiry
risk-free rate
option type
```

You can approximate:

```text
delta
gamma
theta
vega
```

For backtesting, approximate Greeks are better than no Greeks.

---

## B. No historical bid-ask spread

Dhan rolling option data does not provide historical bid/ask.

Solution:

Use slippage proxy.

Example:

```text
ATM NIFTY: 0.05%–0.15%
OTM NIFTY: 0.15%–0.50%
ATM SENSEX: 0.10%–0.30%
OTM SENSEX: 0.30%–1.00%
```

Better solution:

Start collecting live option chain snapshots now for future backtesting.

Store:

```text
timestamp
strike
expiry
bid
ask
ltp
oi
volume
iv
delta
gamma
theta
vega
spot
```

---

## C. No historical depth

20/200-level depth is live only.

Solution:

For backtest, ignore depth strategies or simulate with volume/OI proxy.

For live, collect depth snapshots.

---

## D. Rolling option data changes ATM

You already identified this correctly.

Solution:

```text
Freeze actual strike at entry.
Track actual strike panel.
Never follow ATM after entry.
```

Use:

```text
timestamp + actual_strike
```

as primary key.

---

# 16. How to Find Which Strategy Actually Has Edge

You cannot find edge by looking at one backtest result.

You need a validation process.

---

## Step 1: Segment by regime

Test each strategy separately in:

```text
trending days
rangebound days
low IV days
high IV days
expiry days
non-expiry days
gap days
event days
```

A strategy may have edge only in one regime.

---

## Step 2: Use realistic costs

Include:

```text
slippage
brokerage
STT
exchange charges
GST
stamp duty
SEBI tax
```

Use Dhan trade history to calibrate.

---

## Step 3: Check expectancy

Formula:

```text
expectancy =
(win_rate × average_win)
-
(loss_rate × average_loss)
-
average_cost_per_trade
```

If expectancy is negative after costs, no edge.

---

## Step 4: Check profit factor

```text
profit_factor = gross_profit / gross_loss
```

Minimum acceptable:

```text
> 1.25 to 1.5 after costs
```

For naked option buying, aim higher because live slippage may be worse.

---

## Step 5: Check drawdown

Metrics:

```text
max drawdown
average drawdown
recovery time
consecutive losses
```

Naked option buying can have many consecutive losses.

---

## Step 6: Parameter sensitivity

If strategy works only at one exact parameter, it may be curve-fit.

Example:

```text
Works only at 17 EMA but fails at 15, 18, 20 EMA.
```

That is suspicious.

Good strategy works across a parameter plateau.

---

## Step 7: Walk-forward testing

Split data:

```text
train → test → train → test
```

Do not optimize on full data.

---

## Step 8: Monte Carlo simulation

Randomize trade order and check:

```text
probability of ruin
worst drawdown
confidence interval of returns
```

---

# 17. Recommended Starting Strategy Stack

If you are unable to identify an edge, start simple.

Do not test 90 strategies at once.

Start with these three:

---

## Strategy 1: 15-Minute ORB + OI Wall Break

Rules:

```text
1. Mark first 15-min high/low of NIFTY/SENSEX.
2. Identify highest Call OI strike and highest Put OI strike.
3. Buy CE if:
   - 5-min candle closes above 15-min high
   - spot breaks or approaches Call OI wall
   - Call OI at wall starts falling
   - IV is not extremely high
4. Buy PE if:
   - 5-min candle closes below 15-min low
   - spot breaks or approaches Put OI wall
   - Put OI at wall starts falling
   - IV is not extremely high
5. Stop loss:
   - opposite side of breakout candle
   - or 25% premium loss
6. Time stop:
   - exit if no 20% profit in 30 minutes
7. Trail:
   - after 35% profit, use delta-adjusted ATR trail
8. Exit by 15:15.
```

---

## Strategy 2: VWAP Consolidation Breakout

Rules:

```text
1. Wait for at least 45–60 minutes of consolidation near VWAP.
2. Ensure ADX or CHOP shows compression.
3. Buy CE when 5-min candle breaks consolidation high and stays above VWAP.
4. Buy PE when 5-min candle breaks consolidation low and stays below VWAP.
5. Stop loss:
   - VWAP or consolidation opposite edge
6. Trail:
   - VWAP trail or 20 EMA trail
7. Exit if spot closes opposite VWAP.
```

---

## Strategy 3: IV Contraction / VCP Breakout

Rules:

```text
1. Find low IV percentile or low ATR contraction.
2. Wait for tight range for 60–90 minutes.
3. Buy ATM CE/PE on breakout with volume spike.
4. Require IV to expand slightly after breakout.
5. Stop loss:
   - middle of consolidation
6. Trail:
   - ATR trail + IV crush exit
7. Exit if IV drops 15% from entry.
```

---

# 18. Recommended Risk Settings for NIFTY/SENSEX Naked Buying

Use conservative defaults:

```text
Risk per trade: 0.25%–0.75% capital
Max trades per day: 2–4
Max daily loss: 1.5%–2.5%
Max open premium: 3%–5% capital
Hard premium SL: 25%–35%
Time stop: 20–45 minutes
Trail activation: 30%–50% profit
EOD exit: 15:10–15:15
Expiry time stop: 10–20 minutes
Spread filter: reject if spread > 5%–10%
Delta filter: 0.35–0.70
IV rank filter: avoid if > 75%
```

---

# 19. NIFTY vs SENSEX Practical Notes

## NIFTY

```text
Exchange segment: NSE_FNO
Instrument: OPTIDX
Usually better liquidity
Tighter spreads
Better depth availability
Better for intraday naked option buying
```

## SENSEX

```text
Exchange segment: BSE_FNO
Instrument: OPTIDX
Verify lot size from instrument master
Verify strike interval
Verify liquidity per strike
Spreads may be wider than NIFTY
Use stricter liquidity filters
```

Always verify from Dhan instrument master:

```text
lot size
tick size
strike price
option type
expiry
security ID
```

Instrument master:

```text
https://images.dhan.co/api-data/api-scrip-master.csv
https://images.dhan.co/api-data/api-scrip-master-detailed.csv
```

---

# 20. Final Practical Answer

For naked option buying on NIFTY/SENSEX, your position and risk management should include:

```text
1. Regime detection
2. Liquidity filter
3. Delta filter
4. Theta budget
5. IV rank / vega filter
6. OI confirmation
7. Bid-ask spread filter
8. Position sizing by risk
9. Hard stop loss
10. Time stop
11. Vega crush exit
12. OI unwinding exit
13. Spot structure exit
14. Delta-adjusted ATR trailing
15. VWAP/EMA/CPR/OI wall trailing
16. Partial profit booking
17. Daily loss limit
18. Kill switch
19. EOD square off
20. Trade log and cost calibration
```

The strategies most likely to have edge for naked index option buying are not simple directional indicators alone.

The best candidates are:

```text
Opening range breakout + OI wall
VWAP consolidation breakout
Volatility contraction breakout
Expiry OI wall break / gamma squeeze
Max pain reversal on expiry
Short-covering rallies
Put unwinding falls
IV expansion breakouts
```

The best trailing methods are:

```text
Delta-adjusted ATR trail
VWAP trail
OI wall trail
Spot swing structure trail
Partial profit scaling
IV-based exit
Time stop
Gamma-adjusted expiry trail
```

The most important rule:

```text
Naked option buying edge comes from fast moves, cheap volatility, supportive OI, and strict time/vega risk control.
If the trade does not move quickly, exit.
If volatility dies, exit.
If OI unwinds, exit.
If liquidity disappears, exit.
Only let winners run when spot structure, Greeks, OI, and volatility are all supporting the position.
```

Yes — what you are describing is the correct next evolution.

If your naked option buying backtests are ending in negative P&L even with ~50% winrate, the problem is usually not only the entry signal. The problem is usually:

```text
average winner <= average loser + theta + vega crush + slippage + charges
```

For naked option buying, you do not need a high winrate. You need asymmetric payoff:

```text
small losers + fast non-mover exits + occasional large trend runners
```

So your new design should be:

```text
Supertrend + ADX = signal generator / trend permission
Position Management Engine = real edge
Trailing Engine = payoff asymmetry
DhanHQ WebSocket + Option Chain = live context
REST Orders / Super Orders = execution
Risk Engine = survival
```

Below is a complete production-style design for your `algo_scalper_api` app, focused on **NIFTY and SENSEX naked option buying**, using DhanHQ v2 REST + WebSocket APIs.

---

# 1. Core Architecture

```text
┌──────────────────────────────────────────────────────────────┐
│                        SIGNAL LAYER                          │
│                                                              │
│  Index 1-min / 5-min candles                                 │
│  Adaptive Supertrend                                         │
│  Adaptive ADX                                                │
│  ATR / volatility regime                                     │
│  Market structure: swing high/low, VWAP                      │
└───────────────────────────┬──────────────────────────────────┘
                            │
                            ▼
┌──────────────────────────────────────────────────────────────┐
│                    CONTEXT / REGIME LAYER                    │
│                                                              │
│  ATR percentile                                              │
│  ADX strength                                                │
│  IV rank / IV percentile                                     │
│  OI walls                                                    │
│  PCR                                                         │
│  Bid/ask spread                                              │
│  Depth imbalance                                             │
│  NIFTY vs SENSEX liquidity profile                           │
└───────────────────────────┬──────────────────────────────────┘
                            │
                            ▼
┌──────────────────────────────────────────────────────────────┐
│                   POSITION MANAGEMENT ENGINE                 │
│                                                              │
│  Freeze entered strike                                       │
│  Track option premium + underlying spot                      │
│  Normalize risk using R-multiple and ATR                     │
│  Breakeven ladder                                            │
│  No-progress time stop                                       │
│  Vega crush exit                                             │
│  OI adverse exit                                             │
│  Delta decay exit                                            │
│  Liquidity exit                                              │
│  Partial profit                                              │
│  Runner trailing                                             │
└───────────────────────────┬──────────────────────────────────┘
                            │
                            ▼
┌──────────────────────────────────────────────────────────────┐
│                    EXECUTION / RISK LAYER                    │
│                                                              │
│  Dhan REST Orders                                            │
│  Dhan Super Orders                                           │
│  Dhan Order Update WebSocket                                 │
│  Dhan Market Feed WebSocket Full Packet                      │
│  Dhan Option Chain REST                                      │
│  Kill Switch                                                 │
│  P&L Exit                                                    │
│  Exit All Positions                                          │
└──────────────────────────────────────────────────────────────┘
```

---

# 2. DhanHQ APIs You Should Use

## A. Live market feed WebSocket — full packet

Endpoint:

```text
wss://api-feed.dhan.co?version=2&token=ACCESS_TOKEN&clientId=CLIENT_ID&authType=2
```

Subscribe using request code:

```json
{
  "RequestCode": 21,
  "InstrumentCount": 2,
  "InstrumentList": [
    {
      "ExchangeSegment": "IDX_I",
      "SecurityId": "NIFTY_INDEX_SECURITY_ID"
    },
    {
      "ExchangeSegment": "NSE_FNO",
      "SecurityId": "OPTION_SECURITY_ID"
    }
  ]
}
```

Full packet gives:

```text
LTP
LTQ
LTT
ATP
Volume
Total Sell Qty
Total Buy Qty
OI
Highest OI
Lowest OI
Open
High
Low
Close
5-level market depth
```

This is your primary real-time feed for:

```text
option premium
bid/ask
depth imbalance
OI
spot/index movement
```

Important:

```text
Full Market Depth 20/200 level is only enabled for NSE Equity and Derivatives.
```

So for NIFTY options, you can also use 20-level or 200-level depth.

For SENSEX/BSE_FNO, rely more on:

```text
Full packet 5-level depth
REST quote
Option chain
```

---

## B. Full market depth WebSocket — NIFTY only

20-level:

```text
wss://depth-api-feed.dhan.co/twentydepth?token=ACCESS_TOKEN&clientId=CLIENT_ID&authType=2
```

200-level:

```text
wss://full-depth-api.dhan.co/twohundreddepth?token=ACCESS_TOKEN&clientId=CLIENT_ID&authType=2
```

Subscribe:

```json
{
  "RequestCode": 23,
  "InstrumentCount": 1,
  "InstrumentList": [
    {
      "ExchangeSegment": "NSE_FNO",
      "SecurityId": "NIFTY_OPTION_SECURITY_ID"
    }
  ]
}
```

Use this for NIFTY scalping where microstructure matters.

---

## C. Order update WebSocket

Endpoint:

```text
wss://api-order-update.dhan.co
```

Authorize:

```json
{
  "LoginReq": {
    "MsgCode": 42,
    "ClientId": "YOUR_CLIENT_ID",
    "Token": "YOUR_ACCESS_TOKEN"
  },
  "UserType": "SELF"
}
```

Use this to track:

```text
order placed
pending
traded
part traded
rejected
cancelled
super order leg updates
```

Do not poll order status aggressively. Use this WebSocket.

---

## D. Option chain REST

Endpoint:

```http
POST https://api.dhan.co/v2/optionchain
```

Example:

```json
{
  "UnderlyingScrip": 13,
  "UnderlyingSeg": "IDX_I",
  "Expiry": "2026-07-30"
}
```

Use this for:

```text
Greeks
IV
OI
volume
best bid/ask
strike selection
OI walls
max pain
PCR
```

Rate limit:

```text
1 unique option chain request every 3 seconds
```

So do not fetch option chain every tick.

Recommended:

```text
NIFTY option chain: every 3–5 seconds
SENSEX option chain: staggered, every 5–10 seconds
```

---

## E. Market quote REST

Useful as fallback or snapshot:

```http
POST https://api.dhan.co/v2/marketfeed/ltp
POST https://api.dhan.co/v2/marketfeed/ohlc
POST https://api.dhan.co/v2/marketfeed/quote
```

Use REST quote only when:

```text
WebSocket disconnected
need snapshot before order
need validation
```

Do not use REST quote as your primary scalping feed.

---

## F. Orders REST

Place order:

```http
POST https://api.dhan.co/v2/orders
```

Modify order:

```http
PUT https://api.dhan.co/v2/orders/{order-id}
```

Cancel order:

```http
DELETE https://api.dhan.co/v2/orders/{order-id}
```

Important:

```text
Order placement, modification, cancellation require static IP whitelisting.
```

---

## G. Super Orders REST

Place super order:

```http
POST https://api.dhan.co/v2/super/orders
```

Modify super order:

```http
PUT https://api.dhan.co/v2/super/orders/{order-id}
```

Cancel super order leg:

```http
DELETE https://api.dhan.co/v2/super/orders/{order-id}/{order-leg}
```

Super order supports:

```text
entry leg
target leg
stop loss leg
trailing jump
```

But for advanced adaptive trailing, do not rely only on Super Order.

Use:

```text
Super Order = exchange-side hard protection
Local Position Manager = intelligent adaptive trailing
```

Important from docs:

```text
Order modifications are capped at 25 modifications per order.
```

So do not modify exchange SL every second.

Modify only on:

```text
stage change
breakeven reached
partial taken
large trail step
regime change
```

---

## H. Risk control APIs

Kill switch:

```http
POST https://api.dhan.co/v2/killswitch?killSwitchStatus=ACTIVATE
```

P&L based exit:

```http
POST https://api.dhan.co/v2/pnlExit
```

Exit all positions:

```http
DELETE https://api.dhan.co/v2/positions
```

Use these as account-level safety.

---

## I. Historical data for regime calibration

For backtesting and live regime detection:

```http
POST https://api.dhan.co/v2/charts/intraday
POST https://api.dhan.co/v2/charts/historical
```

For expired options backtesting:

```http
POST https://api.dhan.co/v2/charts/rollingoption
```

But remember:

```text
Rolling option data is for backtesting.
Live trading should use WebSocket + option chain.
```

Rolling option data does not give live Greeks, bid/ask, depth, or exact contract securityId.

---

# 3. The Real Problem With Your Previous Backtests

If you had:

```text
50% winrate
negative P&L
heavy drawdown
```

then likely:

```text
average win was too small
average loss was too large
non-movers were held too long
theta ate premium
IV crush killed premium
slippage was underestimated
exits were not asymmetric
```

For naked option buying, your target distribution should be something like:

```text
Winrate: 35%–50%
Avg win / avg loss: > 2.0
Max trade loss: small and stable
Winner holding time: longer than loser holding time
```

Example:

```text
Winrate = 45%
Avg win = ₹1800
Avg loss = ₹700

Expectancy = 0.45 × 1800 - 0.55 × 700
           = 810 - 385
           = +425 per trade
```

That works.

But this fails:

```text
Winrate = 50%
Avg win = ₹600
Avg loss = ₹800

Expectancy = 0.5 × 600 - 0.5 × 800
           = 300 - 400
           = -100 per trade
```

So your new position management system must force:

```text
cut losers fast
cut non-movers fast
protect breakeven early
let trend runners run
take partials but keep runners
```

---

# 4. Signal Layer: Adaptive Supertrend + ADX

You said you want simple trend identification and momentum:

```text
Supertrend = trend direction
ADX = trend strength
```

That is good.

But make parameters adaptive based on market context.

---

## A. Use two timeframes

Recommended:

```text
5-minute chart = regime / trend permission
1-minute chart = scalping trigger / execution timing
```

Example:

```text
5-min Supertrend bullish + 5-min ADX strong
→ allow CE scalps

5-min Supertrend bearish + 5-min ADX strong
→ allow PE scalps

5-min ADX weak
→ reduce size or no trade
```

---

## B. Adaptive Supertrend parameters

Use ATR percentile to adapt.

Example:

```ruby
def adaptive_signal_params(atr_percentile)
  if atr_percentile > 75
    {
      supertrend_period: 14,
      supertrend_multiplier: 3.0,
      adx_period: 14,
      adx_threshold: 30
    }
  elsif atr_percentile < 25
    {
      supertrend_period: 7,
      supertrend_multiplier: 1.8,
      adx_period: 10,
      adx_threshold: 20
    }
  else
    {
      supertrend_period: 10,
      supertrend_multiplier: 2.2,
      adx_period: 14,
      adx_threshold: 25
    }
  end
end
```

Interpretation:

| Market | Supertrend | ADX Threshold |
|---|---:|---:|
| High volatility | Longer period, wider multiplier | Higher ADX threshold |
| Normal volatility | Medium period, medium multiplier | Normal ADX threshold |
| Low volatility | Shorter period, tighter multiplier | Lower ADX threshold |

---

## C. Regime classification

```ruby
def classify_regime(adx, atr_percentile, supertrend_direction)
  trend_strength =
    if adx > 30
      :strong
    elsif adx >= 20
      :normal
    else
      :weak
    end

  volatility =
    if atr_percentile > 75
      :high
    elsif atr_percentile < 25
      :low
    else
      :normal
    end

  {
    trend_strength: trend_strength,
    volatility: volatility,
    supertrend_direction: supertrend_direction,
    adx: adx,
    atr_percentile: atr_percentile
  }
end
```

Use this regime to adjust:

```text
position size
initial stop
trail width
time stop
partial target
breakeven speed
```

---

# 5. NIFTY vs SENSEX: Use Different Operating Profiles

NIFTY and SENSEX should not use identical trailing logic.

NIFTY usually has:

```text
better liquidity
tighter spreads
deeper option chain
better depth
more reliable OI
```

SENSEX may have:

```text
wider spreads
thinner depth
different lot size
different strike interval
different liquidity by strike
```

So create separate profiles.

---

## Recommended profile structure

```ruby
PROFILES = {
  NIFTY: {
    exchange_segment: "NSE_FNO",
    instrument: "OPTIDX",

    # Verify from Dhan instrument master
    lot_size: nil,
    tick_size: 0.05,
    strike_step: 50,

    # Risk
    initial_risk_pct: 0.25,
    min_risk_ticks: 10,

    # Spot-based stops
    spot_initial_atr_mult: 1.5,
    spot_trail_atr_mult: 1.2,

    # Option-premium-based stops
    option_atr_mult: 1.5,
    trail_option_atr_mult: 1.2,

    # Normalized premium trail percentage
    trail_pct_of_max_premium: 0.18,

    # R-multiple based rules
    breakeven_trigger_R: 0.6,
    less_loss_trigger_R: 0.3,
    trail_activate_R: 0.8,
    partial_trigger_R: 1.0,
    partial_pct: 0.5,

    # Time/no-progress
    no_progress_minutes: 12,
    min_progress_R: 0.25,
    max_hold_minutes: 45,

    # Liquidity
    max_spread_pct: 0.8,
    min_bid_qty: 100,
    min_depth_imbalance: 0.35,

    # Option chain / Greeks
    iv_crush_pct: 0.12,
    oi_unwind_pct: 0.20,
    min_delta: 0.30,
    dead_delta: 0.12,

    # Exit time
    eod_time: "15:15"
  },

  SENSEX: {
    exchange_segment: "BSE_FNO",
    instrument: "OPTIDX",

    # Verify from Dhan instrument master
    lot_size: nil,
    tick_size: 0.05,
    strike_step: 100,

    # Risk: wider because liquidity can be thinner
    initial_risk_pct: 0.30,
    min_risk_ticks: 15,

    # Spot-based stops
    spot_initial_atr_mult: 2.0,
    spot_trail_atr_mult: 1.6,

    # Option-premium-based stops
    option_atr_mult: 2.0,
    trail_option_atr_mult: 1.6,

    # Normalized premium trail percentage
    trail_pct_of_max_premium: 0.22,

    # R-multiple based rules
    breakeven_trigger_R: 0.8,
    less_loss_trigger_R: 0.35,
    trail_activate_R: 1.0,
    partial_trigger_R: 1.25,
    partial_pct: 0.5,

    # Time/no-progress
    no_progress_minutes: 10,
    min_progress_R: 0.30,
    max_hold_minutes: 35,

    # Liquidity: stricter
    max_spread_pct: 1.5,
    min_bid_qty: 50,
    min_depth_imbalance: 0.30,

    # Option chain / Greeks
    iv_crush_pct: 0.10,
    oi_unwind_pct: 0.18,
    min_delta: 0.35,
    dead_delta: 0.15,

    # Exit time
    eod_time: "15:15"
  }
}.freeze
```

Important:

```text
Do not hardcode lot_size.
Fetch it from Dhan instrument master and keep it updated.
```

Instrument master:

```text
https://images.dhan.co/api-data/api-scrip-master.csv
https://images.dhan.co/api-data/api-scrip-master-detailed.csv
```

---

# 6. Normalized Trailing System

You asked for something like percentage that is normalized across assets.

Do not use only raw premium percentage.

Use three normalized layers:

```text
1. R-multiple normalization
2. ATR normalization
3. Basis-point index normalization
```

---

## A. R-multiple normalization

At entry:

```text
initial_risk = entry_premium - initial_stop_premium
```

Then:

```text
R = (current_premium - entry_premium) / initial_risk
```

Example:

```text
entry premium = ₹100
initial stop = ₹75
initial risk = ₹25

current premium = ₹125
R = (125 - 100) / 25 = 1.0
```

Now rules become asset-neutral:

```text
Move to breakeven at R = 0.6
Take partial at R = 1.0
Activate runner trail at R = 0.8
Exit no-progress if R < 0.25 after time limit
```

This works for NIFTY and SENSEX because it is based on the risk of that specific option trade.

---

## B. ATR normalization

Use:

```text
index ATR
option ATR
```

Index ATR is useful for spot-based trailing.

Option ATR is useful for premium-based trailing.

Example:

```text
initial_stop_distance = max(
  entry_premium × initial_risk_pct,
  option_ATR × option_atr_mult,
  tick_size × min_risk_ticks
)
```

Trail distance:

```text
trail_distance = max(
  max_premium × trail_pct,
  option_ATR × trail_option_atr_mult,
  delta × index_ATR × spot_trail_atr_mult
)
```

This adapts to volatility.

---

## C. Basis-point normalization for spot

For spot-based trailing:

```text
index_vol_bps = index_ATR / index_spot × 10000
```

Example:

```text
NIFTY spot = 24,000
NIFTY ATR = 30

index_vol_bps = 30 / 24000 × 10000 = 12.5 bps
```

This lets you compare volatility across NIFTY, SENSEX, BANKNIFTY, etc.

Use this to adjust time stops and trail width.

---

# 7. Position Management Engine

This is the heart of the system.

The position management engine should not care what entry strategy created the trade.

It receives:

```text
position
live option snapshot
live index snapshot
option chain data
regime
```

It outputs:

```text
hold
exit
partial
modify stop
```

---

## A. Position object

```ruby
class Position
  attr_accessor :id,
                :asset,
                :side,
                :strike,
                :expiry,
                :security_id,
                :qty,
                :entry_time,
                :entry_premium,
                :entry_spot,
                :entry_iv,
                :entry_oi,
                :entry_delta,
                :entry_atr,
                :option_atr,
                :initial_risk,
                :cost_per_unit,
                :stop_premium,
                :spot_stop,
                :max_premium,
                :min_premium,
                :max_spot,
                :min_spot,
                :r_multiple,
                :stage,
                :partial_taken,
                :last_progress_time,
                :correlation_id,
                :order_id,
                :super_order_id

  def initialize(attrs = {})
    attrs.each { |k, v| send("#{k}=", v) }

    self.stage ||= :initial
    self.partial_taken ||= false
    self.max_premium ||= entry_premium
    self.min_premium ||= entry_premium
    self.max_spot ||= entry_spot
    self.min_spot ||= entry_spot
    self.last_progress_time ||= entry_time
  end
end
```

---

## B. Market snapshot object

```ruby
class MarketSnapshot
  attr_accessor :ts,
                :spot,
                :spot_atr,
                :adx,
                :supertrend_direction,
                :atr_percentile,
                :iv_rank,
                :option_ltp,
                :option_bid,
                :option_ask,
                :option_mid,
                :option_volume,
                :option_oi,
                :option_iv,
                :option_delta,
                :option_gamma,
                :option_theta,
                :option_vega,
                :bid_qty,
                :ask_qty,
                :depth_imbalance,
                :spread_pct
end
```

---

# 8. Exit Priority Hierarchy

Use strict priority.

Recommended:

```text
1. Hard premium stop
2. Spot structure stop
3. Liquidity failure
4. Time stop / max hold
5. No-progress stop
6. Vega crush
7. Adverse OI / option chain deterioration
8. Delta death
9. Trend trail / runner trail
10. Partial profit
11. EOD exit
```

But for letting winners run, target is not a full exit. Target is partial.

---

# 9. Ruby Position Manager Skeleton

This is the core logic.

```ruby
class PositionManager
  def initialize(profile)
    @p = profile
  end

  def evaluate(pos, m, regime)
    update_extremes(pos, m)
    update_r_multiple(pos, m)

    factors = regime_factors(regime)

    # --------------------------------------------------
    # 1. Hard premium stop
    # --------------------------------------------------
    if m.option_bid <= pos.stop_premium
      return exit_action(pos, m, "PREMIUM_STOP")
    end

    # --------------------------------------------------
    # 2. Spot structure stop
    # --------------------------------------------------
    if spot_stop_hit?(pos, m)
      return exit_action(pos, m, "SPOT_STOP")
    end

    # --------------------------------------------------
    # 3. Liquidity failure
    # --------------------------------------------------
    if m.spread_pct > @p[:max_spread_pct]
      return exit_action(pos, m, "SPREAD_TOO_WIDE")
    end

    if m.bid_qty < @p[:min_bid_qty]
      return exit_action(pos, m, "BID_LIQUIDITY_LOW")
    end

    # --------------------------------------------------
    # 4. Max hold time stop
    # --------------------------------------------------
    if max_hold_exceeded?(pos, m, factors)
      return exit_action(pos, m, "MAX_HOLD_TIME")
    end

    # --------------------------------------------------
    # 5. No-progress stop
    # --------------------------------------------------
    if no_progress?(pos, m, factors)
      return exit_action(pos, m, "NO_PROGRESS")
    end

    # --------------------------------------------------
    # 6. Vega crush
    # --------------------------------------------------
    if vega_crush?(pos, m)
      return exit_action(pos, m, "VEGA_CRUSH")
    end

    # --------------------------------------------------
    # 7. Adverse OI
    # --------------------------------------------------
    if adverse_oi?(pos, m)
      return exit_action(pos, m, "ADVERSE_OI")
    end

    # --------------------------------------------------
    # 8. Delta death
    # --------------------------------------------------
    if delta_dead?(pos, m)
      return exit_action(pos, m, "DELTA_DEAD")
    end

    # --------------------------------------------------
    # 9. Update protective stops
    # --------------------------------------------------
    apply_less_loss_stop(pos, m)
    apply_breakeven_stop(pos, m)
    apply_premium_trail(pos, m, factors)
    apply_spot_trail(pos, m, factors)

    # --------------------------------------------------
    # 10. Partial profit
    # --------------------------------------------------
    if partial_due?(pos, m, factors)
      return partial_action(pos, m)
    end

    # --------------------------------------------------
    # 11. EOD exit
    # --------------------------------------------------
    if eod_exit?(m)
      return exit_action(pos, m, "EOD_EXIT")
    end

    {
      action: :hold,
      stage: pos.stage,
      stop_premium: pos.stop_premium,
      spot_stop: pos.spot_stop,
      r_multiple: pos.r_multiple
    }
  end

  private

  def update_extremes(pos, m)
    pos.max_premium = [pos.max_premium, m.option_mid].max
    pos.min_premium = [pos.min_premium, m.option_mid].min

    if pos.side == "CE"
      pos.max_spot = [pos.max_spot, m.spot].max
    else
      pos.min_spot = [pos.min_spot, m.spot].min
    end

    if m.option_mid > pos.max_premium - @p[:tick_size]
      pos.last_progress_time = m.ts
    end
  end

  def update_r_multiple(pos, m)
    return if pos.initial_risk.nil? || pos.initial_risk.zero?

    pos.r_multiple = (m.option_mid - pos.entry_premium) / pos.initial_risk.to_f
  end

  def regime_factors(regime)
    trend_factor =
      case regime[:trend_strength]
      when :strong then 1.25
      when :weak then 0.80
      else 1.0
      end

    vol_factor =
      case regime[:volatility]
      when :high then 1.30
      when :low then 0.85
      else 1.0
      end

    {
      trail: trend_factor * vol_factor,
      time: trend_factor,
      partial: trend_factor
    }
  end

  def spot_stop_hit?(pos, m)
    return false if pos.spot_stop.nil?

    if pos.side == "CE"
      m.spot <= pos.spot_stop
    else
      m.spot >= pos.spot_stop
    end
  end

  def max_hold_exceeded?(pos, m, factors)
    elapsed_minutes = (m.ts - pos.entry_time) / 60.0
    limit = @p[:max_hold_minutes] * factors[:time]

    elapsed_minutes > limit && pos.r_multiple < 0.5
  end

  def no_progress?(pos, m, factors)
    elapsed_minutes = (m.ts - pos.entry_time) / 60.0
    limit = @p[:no_progress_minutes] * factors[:time]

    elapsed_minutes > limit && pos.r_multiple < @p[:min_progress_R]
  end

  def vega_crush?(pos, m)
    return false if pos.entry_iv.nil? || m.option_iv.nil?
    return false if pos.entry_iv.zero?

    iv_drop_pct = (pos.entry_iv - m.option_iv) / pos.entry_iv.to_f

    iv_drop_pct >= @p[:iv_crush_pct] && pos.r_multiple < 0.5
  end

  def adverse_oi?(pos, m)
    return false if pos.entry_oi.nil? || m.option_oi.nil?
    return false if pos.entry_oi.zero?

    oi_drop_pct = (pos.entry_oi - m.option_oi) / pos.entry_oi.to_f

    return false unless oi_drop_pct >= @p[:oi_unwind_pct]

    # If trade is not progressing and OI is leaving, exit.
    if pos.side == "CE"
      m.spot > pos.entry_spot && pos.r_multiple < @p[:min_progress_R]
    else
      m.spot < pos.entry_spot && pos.r_multiple < @p[:min_progress_R]
    end
  end

  def delta_dead?(pos, m)
    return false if m.option_delta.nil?

    m.option_delta.abs < @p[:dead_delta] && pos.r_multiple < 0.2
  end

  def apply_less_loss_stop(pos, m)
    return unless pos.r_multiple >= @p[:less_loss_trigger_R]

    less_loss_stop = pos.entry_premium - (pos.initial_risk * 0.5)
    pos.stop_premium = [pos.stop_premium, less_loss_stop].max
    pos.stage = :less_loss
  end

  def apply_breakeven_stop(pos, m)
    return unless pos.r_multiple >= @p[:breakeven_trigger_R]

    breakeven_stop = pos.entry_premium + pos.cost_per_unit.to_f
    pos.stop_premium = [pos.stop_premium, breakeven_stop].max
    pos.stage = :breakeven
  end

  def apply_premium_trail(pos, m, factors)
    return unless pos.r_multiple >= @p[:trail_activate_R]

    trail_distance = [
      pos.max_premium * @p[:trail_pct_of_max_premium],
      pos.option_atr * @p[:trail_option_atr_mult] * factors[:trail],
      m.option_delta.abs * pos.entry_atr * @p[:spot_trail_atr_mult] * factors[:trail],
      @p[:tick_size] * @p[:min_risk_ticks]
    ].max

    premium_trail_stop = pos.max_premium - trail_distance
    pos.stop_premium = [pos.stop_premium, premium_trail_stop].max
    pos.stage = :trailing
  end

  def apply_spot_trail(pos, m, factors)
    spot_trail_distance = pos.entry_atr * @p[:spot_trail_atr_mult] * factors[:trail]

    if pos.side == "CE"
      spot_trail_stop = pos.max_spot - spot_trail_distance
      pos.spot_stop = [pos.spot_stop, spot_trail_stop].max
    else
      spot_trail_stop = pos.min_spot + spot_trail_distance
      pos.spot_stop = [pos.spot_stop, spot_trail_stop].min
    end
  end

  def partial_due?(pos, m, factors)
    return false if pos.partial_taken

    pos.r_multiple >= @p[:partial_trigger_R] * factors[:partial]
  end

  def eod_exit?(m)
    m.ts.strftime("%H:%M") >= @p[:eod_time]
  end

  def exit_action(pos, m, reason)
    {
      action: :exit,
      qty: pos.qty,
      reason: reason,
      price: m.option_bid,
      ltp: m.option_ltp,
      stop_premium: pos.stop_premium,
      r_multiple: pos.r_multiple
    }
  end

  def partial_action(pos, m)
    partial_qty = (pos.qty * @p[:partial_pct]).floor

    {
      action: :partial,
      qty: partial_qty,
      reason: "PARTIAL_PROFIT",
      price: m.option_bid,
      r_multiple: pos.r_multiple
    }
  end
end
```

---

# 10. Creating a New Position With Normalized Risk

When a Supertrend + ADX signal creates a trade, initialize it like this:

```ruby
def create_position(attrs, market_snapshot, profile)
  entry_premium = attrs[:entry_premium]
  option_atr = attrs[:option_atr]
  index_atr = market_snapshot.spot_atr

  initial_risk = [
    entry_premium * profile[:initial_risk_pct],
    option_atr * profile[:option_atr_mult],
    profile[:tick_size] * profile[:min_risk_ticks]
  ].max

  stop_premium = entry_premium - initial_risk

  spot_distance = index_atr * profile[:spot_initial_atr_mult]

  spot_stop =
    if attrs[:side] == "CE"
      market_snapshot.spot - spot_distance
    else
      market_snapshot.spot + spot_distance
    end

  Position.new(
    id: attrs[:id],
    asset: attrs[:asset],
    side: attrs[:side],
    strike: attrs[:strike],
    expiry: attrs[:expiry],
    security_id: attrs[:security_id],
    qty: attrs[:qty],
    entry_time: market_snapshot.ts,
    entry_premium: entry_premium,
    entry_spot: market_snapshot.spot,
    entry_iv: market_snapshot.option_iv,
    entry_oi: market_snapshot.option_oi,
    entry_delta: market_snapshot.option_delta,
    entry_atr: index_atr,
    option_atr: option_atr,
    initial_risk: initial_risk,
    cost_per_unit: attrs[:cost_per_unit],
    stop_premium: stop_premium,
    spot_stop: spot_stop,
    correlation_id: attrs[:correlation_id]
  )
end
```

---

# 11. Position Sizing

Use risk-based sizing, not fixed lot sizing.

```ruby
def calculate_quantity(capital:, risk_per_trade:, initial_risk_premium:, lot_size:, max_premium_per_trade: nil, entry_premium: nil)
  risk_amount = capital * risk_per_trade

  risk_per_lot = initial_risk_premium * lot_size
  lots_by_risk = (risk_amount / risk_per_lot).floor

  lots = lots_by_risk

  if max_premium_per_trade && entry_premium
    premium_per_lot = entry_premium * lot_size
    lots_by_premium = (max_premium_per_trade / premium_per_lot).floor
    lots = [lots, lots_by_premium].min
  end

  lots = [lots, 0].max
  lots * lot_size
end
```

Recommended starting risk:

```text
Risk per trade: 0.25% to 0.75% capital
Max daily loss: 1.5% to 2.0% capital
Max concurrent naked option positions: 1 or 2
```

For naked option buying, avoid large size.

---

# 12. Live DhanHQ WebSocket Full Packet Parser in Ruby

Dhan market feed is binary and little-endian.

Full packet structure from docs:

```text
Header: 8 bytes
Byte 0: feed response code
Bytes 1-2: message length
Byte 3: exchange segment
Bytes 4-7: security ID

Full packet payload:
LTP
LTQ
LTT
ATP
Volume
Total Sell Qty
Total Buy Qty
OI
Highest OI
Lowest OI
Open
Close
High
Low
5-level market depth
```

Ruby parser:

```ruby
module DhanPackets
  module_function

  def parse_all(data)
    data = data.dup.force_encoding("ASCII-8BIT")
    packets = []
    offset = 0

    while offset < data.bytesize
      break if offset + 8 > data.bytesize

      msg_len = data[offset + 1, 2].unpack1("v")
      break if msg_len.nil? || msg_len < 8
      break if offset + msg_len > data.bytesize

      packet = data[offset, msg_len]
      code = packet.getbyte(0)

      case code
      when 8
        packets << parse_full_packet(packet)
      when 2
        packets << parse_ticker_packet(packet)
      when 4
        packets << parse_quote_packet(packet)
      when 5
        packets << parse_oi_packet(packet)
      when 6
        packets << parse_prev_close_packet(packet)
      when 50
        packets << parse_disconnect_packet(packet)
      end

      offset += msg_len
    end

    packets
  end

  def parse_full_packet(b)
    security_id = b[4, 4].unpack1("l<")

    ltp = b[8, 4].unpack1("e")
    ltq = b[12, 2].unpack1("s<")
    ltt = b[14, 4].unpack1("l<")
    atp = b[18, 4].unpack1("e")
    volume = b[22, 4].unpack1("l<")
    total_sell_qty = b[26, 4].unpack1("l<")
    total_buy_qty = b[30, 4].unpack1("l<")
    oi = b[34, 4].unpack1("l<")
    highest_oi = b[38, 4].unpack1("l<")
    lowest_oi = b[42, 4].unpack1("l<")
    open = b[46, 4].unpack1("e")
    close = b[50, 4].unpack1("e")
    high = b[54, 4].unpack1("e")
    low = b[58, 4].unpack1("e")

    depth = []

    5.times do |i|
      offset = 62 + (i * 20)

      bid_qty = b[offset, 4].unpack1("l<")
      ask_qty = b[offset + 4, 4].unpack1("l<")
      bid_orders = b[offset + 8, 2].unpack1("s<")
      ask_orders = b[offset + 10, 2].unpack1("s<")
      bid_price = b[offset + 12, 4].unpack1("e")
      ask_price = b[offset + 16, 4].unpack1("e")

      depth << {
        bid_qty: bid_qty,
        ask_qty: ask_qty,
        bid_orders: bid_orders,
        ask_orders: ask_orders,
        bid_price: bid_price,
        ask_price: ask_price
      }
    end

    best_bid = depth.first
    spread_pct =
      if best_bid && best_bid[:bid_price].to_f > 0 && best_bid[:ask_price].to_f > 0
        mid = (best_bid[:bid_price] + best_bid[:ask_price]) / 2.0
        ((best_bid[:ask_price] - best_bid[:bid_price]) / mid) * 100.0
      else
        0.0
      end

    depth_imbalance =
      if best_bid && (best_bid[:bid_qty] + best_bid[:ask_qty]) > 0
        best_bid[:bid_qty].to_f / (best_bid[:bid_qty] + best_bid[:ask_qty])
      else
        0.5
      end

    {
      packet_type: :full,
      security_id: security_id,
      ltp: ltp,
      ltq: ltq,
      ltt: ltt,
      atp: atp,
      volume: volume,
      total_sell_qty: total_sell_qty,
      total_buy_qty: total_buy_qty,
      oi: oi,
      highest_oi: highest_oi,
      lowest_oi: lowest_oi,
      open: open,
      close: close,
      high: high,
      low: low,
      depth: depth,
      best_bid: best_bid&.dig(:bid_price),
      best_ask: best_bid&.dig(:ask_price),
      bid_qty: best_bid&.dig(:bid_qty),
      ask_qty: best_bid&.dig(:ask_qty),
      spread_pct: spread_pct,
      depth_imbalance: depth_imbalance
    }
  end

  def parse_ticker_packet(b)
    {
      packet_type: :ticker,
      security_id: b[4, 4].unpack1("l<"),
      ltp: b[8, 4].unpack1("e"),
      ltt: b[12, 4].unpack1("l<")
    }
  end

  def parse_quote_packet(b)
    {
      packet_type: :quote,
      security_id: b[4, 4].unpack1("l<"),
      ltp: b[8, 4].unpack1("e"),
      ltq: b[12, 2].unpack1("s<"),
      ltt: b[14, 4].unpack1("l<"),
      atp: b[18, 4].unpack1("e"),
      volume: b[22, 4].unpack1("l<"),
      total_sell_qty: b[26, 4].unpack1("l<"),
      total_buy_qty: b[30, 4].unpack1("l<"),
      open: b[34, 4].unpack1("e"),
      close: b[38, 4].unpack1("e"),
      high: b[42, 4].unpack1("e"),
      low: b[46, 4].unpack1("e")
    }
  end

  def parse_oi_packet(b)
    {
      packet_type: :oi,
      security_id: b[4, 4].unpack1("l<"),
      oi: b[8, 4].unpack1("l<")
    }
  end

  def parse_prev_close_packet(b)
    {
      packet_type: :prev_close,
      security_id: b[4, 4].unpack1("l<"),
      prev_close: b[8, 4].unpack1("e"),
      prev_oi: b[12, 4].unpack1("l<")
    }
  end

  def parse_disconnect_packet(b)
    {
      packet_type: :disconnect,
      code: b[8, 2].unpack1("v")
    }
  end
end
```

---

# 13. Dhan REST Client Skeleton in Ruby

```ruby
require "net/http"
require "json"
require "uri"

module Dhan
  class RestClient
    BASE = "https://api.dhan.co/v2".freeze

    def initialize(client_id:, access_token:)
      @client_id = client_id
      @access_token = access_token
    end

    def get(path)
      uri = URI.join(BASE, path)
      req = Net::HTTP::Get.new(uri)
      apply_headers(req)

      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
        http.request(req)
      end

      handle_response(res, "GET #{path}")
    end

    def post(path, payload = {})
      uri = URI.join(BASE, path)
      req = Net::HTTP::Post.new(uri)
      apply_headers(req)
      req.body = payload.to_json

      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
        http.request(req)
      end

      handle_response(res, "POST #{path}")
    end

    def put(path, payload = {})
      uri = URI.join(BASE, path)
      req = Net::HTTP::Put.new(uri)
      apply_headers(req)
      req.body = payload.to_json

      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
        http.request(req)
      end

      handle_response(res, "PUT #{path}")
    end

    def delete(path)
      uri = URI.join(BASE, path)
      req = Net::HTTP::Delete.new(uri)
      apply_headers(req)

      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
        http.request(req)
      end

      handle_response(res, "DELETE #{path}")
    end

    # ----------------------------
    # Data APIs
    # ----------------------------

    def option_chain(underlying_scrip:, underlying_seg:, expiry:)
      post("/optionchain", {
        UnderlyingScrip: underlying_scrip,
        UnderlyingSeg: underlying_seg,
        Expiry: expiry
      })
    end

    def expiry_list(underlying_scrip:, underlying_seg:)
      post("/optionchain/expirylist", {
        UnderlyingScrip: underlying_scrip,
        UnderlyingSeg: underlying_seg
      })
    end

    def quote(instruments)
      post("/marketfeed/quote", instruments)
    end

    def intraday(payload)
      post("/charts/intraday", payload)
    end

    def historical(payload)
      post("/charts/historical", payload)
    end

    # ----------------------------
    # Trading APIs
    # ----------------------------

    def place_order(attrs)
      post("/orders", { dhanClientId: @client_id }.merge(attrs))
    end

    def modify_order(order_id, attrs)
      put("/orders/#{order_id}", { dhanClientId: @client_id, orderId: order_id }.merge(attrs))
    end

    def cancel_order(order_id)
      delete("/orders/#{order_id}")
    end

    def place_super_order(attrs)
      post("/super/orders", { dhanClientId: @client_id }.merge(attrs))
    end

    def modify_super_order(order_id, attrs)
      put("/super/orders/#{order_id}", { dhanClientId: @client_id, orderId: order_id }.merge(attrs))
    end

    def cancel_super_order_leg(order_id, leg)
      delete("/super/orders/#{order_id}/#{leg}")
    end

    def super_orders
      get("/super/orders")
    end

    def orders
      get("/orders")
    end

    def trades
      get("/trades")
    end

    def positions
      get("/positions")
    end

    def fundlimit
      get("/fundlimit")
    end

    # ----------------------------
    # Risk controls
    # ----------------------------

    def pnl_exit(profit_value:, loss_value:, product_type: ["INTRADAY"], enable_kill_switch: true)
      post("/pnlExit", {
        dhanClientId: @client_id,
        profitValue: profit_value,
        lossValue: loss_value,
        productType: product_type,
        enableKillSwitch: enable_kill_switch
      })
    end

    def killswitch_activate
      post("/killswitch?killSwitchStatus=ACTIVATE", {})
    end

    def killswitch_deactivate
      post("/killswitch?killSwitchStatus=DEACTIVATE", {})
    end

    def exit_all_positions
      delete("/positions")
    end

    private

    def apply_headers(req)
      req["access-token"] = @access_token
      req["client-id"] = @client_id
      req["Content-Type"] = "application/json"
      req["Accept"] = "application/json"
    end

    def handle_response(res, label)
      unless res.is_a?(Net::HTTPSuccess)
        raise "Dhan API error #{label}: #{res.code} #{res.body}"
      end

      return {} if res.body.nil? || res.body.empty?

      JSON.parse(res.body)
    end
  end
end
```

---

# 14. Option Chain Fetcher With Rate Limit

```ruby
class OptionChainFetcher
  def initialize(dhan_client)
    @client = dhan_client
    @cache = {}
    @last_fetch_at = {}
  end

  def fetch(asset:, underlying_scrip:, underlying_seg:, expiry:, min_interval: 3.0)
    now = Time.now
    key = "#{asset}:#{expiry}"

    if @last_fetch_at[key] && (now - @last_fetch_at[key]) < min_interval
      return @cache[key]
    end

    data = @client.option_chain(
      underlying_scrip: underlying_scrip,
      underlying_seg: underlying_seg,
      expiry: expiry
    )

    @cache[key] = data
    @last_fetch_at[key] = now

    data
  rescue => e
    puts "Option chain fetch error: #{e.message}"
    @cache[key]
  end
end
```

Use this to get:

```text
Greeks
IV
OI
bid/ask
volume
```

For live position management, combine:

```text
WebSocket full packet = fast LTP/depth/OI
Option chain REST = Greeks/strike-wide OI/IV
```

---

# 15. Building a MarketSnapshot for a Position

```ruby
def build_market_snapshot(pos, ws_quote, option_chain_strike_data, index_context)
  m = MarketSnapshot.new

  m.ts = Time.now

  m.spot = index_context[:spot]
  m.spot_atr = index_context[:atr]
  m.adx = index_context[:adx]
  m.supertrend_direction = index_context[:supertrend_direction]
  m.atr_percentile = index_context[:atr_percentile]

  m.option_ltp = ws_quote&.dig(:ltp)
  m.option_bid = ws_quote&.dig(:best_bid)
  m.option_ask = ws_quote&.dig(:best_ask)
  m.option_volume = ws_quote&.dig(:volume)
  m.option_oi = ws_quote&.dig(:oi)
  m.bid_qty = ws_quote&.dig(:bid_qty)
  m.ask_qty = ws_quote&.dig(:ask_qty)
  m.spread_pct = ws_quote&.dig(:spread_pct)
  m.depth_imbalance = ws_quote&.dig(:depth_imbalance)

  m.option_mid =
    if m.option_bid && m.option_ask && m.option_bid > 0 && m.option_ask > 0
      (m.option_bid + m.option_ask) / 2.0
    else
      m.option_ltp
    end

  if option_chain_strike_data
    m.option_iv = option_chain_strike_data["iv"]
    m.option_delta = option_chain_strike_data["delta"]
    m.option_gamma = option_chain_strike_data["gamma"]
    m.option_theta = option_chain_strike_data["theta"]
    m.option_vega = option_chain_strike_data["vega"]

    # If WS bid/ask missing, use option chain bid/ask
    m.option_bid ||= option_chain_strike_data["bid"]
    m.option_ask ||= option_chain_strike_data["ask"]
  end

  m
end
```

---

# 16. Execution Engine

For scalping, use LIMIT orders with IOC where appropriate.

## A. Entry

For aggressive entry:

```text
Buy at ask or ask + small slippage ticks
Use LIMIT + IOC
```

Example:

```ruby
def enter_option_trade(dhan_client:, pos:, price:, qty:, exchange_segment:, correlation_id:)
  dhan_client.place_order(
    correlationId: correlation_id,
    transactionType: "BUY",
    exchangeSegment: exchange_segment,
    productType: "INTRADAY",
    orderType: "LIMIT",
    validity: "IOC",
    securityId: pos.security_id,
    quantity: qty,
    price: price,
    triggerPrice: 0
  )
end
```

## B. Exit

For urgent exit:

```text
Sell at bid or bid - small slippage ticks
Use LIMIT + IOC
If not filled quickly, replace or market in emergency
```

Example:

```ruby
def exit_option_trade(dhan_client:, pos:, price:, qty:, exchange_segment:, correlation_id:)
  dhan_client.place_order(
    correlationId: correlation_id,
    transactionType: "SELL",
    exchangeSegment: exchange_segment,
    productType: "INTRADAY",
    orderType: "LIMIT",
    validity: "IOC",
    securityId: pos.security_id,
    quantity: qty,
    price: price,
    triggerPrice: 0
  )
end
```

---

# 17. Super Order Usage

Use Super Order for exchange-side protection.

Example:

```ruby
def place_super_option_order(dhan_client:, pos:, entry_price:, target_price:, stop_loss_price:, exchange_segment:, correlation_id:)
  dhan_client.place_super_order(
    correlationId: correlation_id,
    transactionType: "BUY",
    exchangeSegment: exchange_segment,
    productType: "INTRADAY",
    orderType: "LIMIT",
    securityId: pos.security_id,
    quantity: pos.qty,
    price: entry_price,
    targetPrice: target_price,
    stopLossPrice: stop_loss_price,
    trailingJump: 0
  )
end
```

But your local trailing engine should still manage the position.

Modify only on meaningful changes:

```ruby
def move_super_stop_loss(dhan_client:, order_id:, new_stop_loss_price:)
  dhan_client.modify_super_order(
    order_id,
    legName: "STOP_LOSS_LEG",
    stopLossPrice: new_stop_loss_price,
    targetPrice: 0,
    trailingJump: 0
  )
end
```

Remember:

```text
Maximum 25 modifications per order.
```

So do not modify on every tick.

Recommended modification policy:

```text
Modify exchange SL only when:
1. Breakeven reached
2. Partial taken
3. Trail stage changes
4. Stop moves by at least X ticks or X% of premium
5. Regime changes materially
```

---

# 18. Main Live Loop Design

```ruby
class ScalperEngine
  def initialize(dhan_client:, profile:, asset:)
    @client = dhan_client
    @profile = profile
    @asset = asset
    @manager = PositionManager.new(profile)
    @positions = {}
    @quotes = {}
    @option_chain_cache = {}
    @index_context = {}
  end

  def on_market_packet(packet)
    @quotes[packet[:security_id]] = packet
  end

  def on_order_update(update)
    # Update fill status, average price, remaining quantity
    # Map using correlationId
  end

  def manage_positions
    @positions.each do |id, pos|
      ws_quote = @quotes[pos.security_id]
      option_chain_strike = get_strike_data_from_cache(pos)
      m = build_market_snapshot(pos, ws_quote, option_chain_strike, @index_context)

      decision = @manager.evaluate(pos, m, current_regime)

      case decision[:action]
      when :exit
        execute_exit(pos, decision)
        @positions.delete(id)

      when :partial
        execute_partial(pos, decision)
        pos.partial_taken = true
        pos.qty -= decision[:qty]
        move_stop_to_breakeven_if_possible(pos)

      when :hold
        maybe_modify_exchange_stop(pos, decision)
      end
    end
  end
end
```

Run position management frequently:

```text
Every 250ms to 1000ms for scalping
```

But modify exchange orders only when necessary.

---

# 19. Option Chain-Based Position Adjustments

Use option chain not just for entry, but for ongoing position management.

## A. Liquidity veto

Before entry and during trade:

```text
Reject/exit if spread too wide
Reject/exit if bid quantity too low
Reject/exit if depth imbalance strongly adverse
```

## B. IV veto

For long options:

```text
Avoid buying when IV rank is very high
Exit if IV crushes after entry
```

Example:

```text
If IV falls 10%–15% from entry and trade is not progressing, exit.
```

## C. Delta management

For naked option buying:

```text
Prefer delta 0.35 to 0.70
Exit if delta becomes too low
Tighten trail if delta becomes very high
```

## D. OI walls

Use option chain to detect large OI strikes.

For CE:

```text
Large Call OI above spot = resistance
If spot breaks that wall, short covering may help trend
If spot fails near that wall, take partial/tighten
```

For PE:

```text
Large Put OI below spot = support
If spot breaks that wall, put unwinding may help trend
If spot fails near that wall, take partial/tighten
```

---

# 20. Breakeven and Less-Loss Logic

This is critical for reducing drawdown.

Use a ladder:

```text
Stage 0: Initial risk
Stage 1: Less-loss stop
Stage 2: Breakeven stop
Stage 3: Trail activation
Stage 4: Runner trail
```

Example for NIFTY:

```text
Initial risk = ₹25

If R >= 0.3:
  move stop to entry - 50% initial risk

If R >= 0.6:
  move stop to entry + charges

If R >= 0.8:
  activate trailing

If R >= 1.0:
  take partial 50%
  keep runner with trail
```

This achieves your goal:

```text
Try to close breakeven if possible.
Otherwise reduce loss.
Do not let small profit become full loss.
```

---

# 21. No-Progress Exit Logic

This is one of the most important rules for naked option buying.

If the option does not move quickly, theta kills it.

Use:

```text
No-progress exit = time + R-multiple + volatility regime
```

Example:

```text
If after 12 minutes, R < 0.25, exit.
```

Adjust by regime:

```text
Strong trend: allow slightly more time
Weak trend/chop: exit faster
High volatility: allow slightly more room
Low volatility: exit faster
```

Ruby logic:

```ruby
def no_progress?(pos, m, factors)
  elapsed_minutes = (m.ts - pos.entry_time) / 60.0
  limit = @profile[:no_progress_minutes] * factors[:time]

  elapsed_minutes > limit && pos.r_multiple < @profile[:min_progress_R]
end
```

---

# 22. Letting Winners Run

Do not use a fixed full target.

Use:

```text
partial + runner
```

Example:

```text
At 1R:
  book 50%

Remaining 50%:
  trail using premium ATR + spot structure + Supertrend weakness
```

For runner exit, use softer trend weakness rules:

```text
Exit runner if:
- premium trail stop hits
- spot structure breaks
- Supertrend flips against trade and ADX weakens
- IV crushes
- liquidity disappears
- EOD reached
```

Do not exit runner just because it reached 1R or 1.5R.

That is how you capture the big trend days.

---

# 23. NIFTY-Specific Trailing Behavior

For NIFTY:

```text
Tighter trail
Faster partials
Can use 20-level depth
Can use more aggressive IOC entries/exits
Can rely more on OI walls
```

Recommended:

```text
Breakeven trigger: 0.6R
Partial trigger: 1.0R
Trail activate: 0.8R
No-progress: 12 minutes
Premium trail: 18% of max premium or option ATR-based
```

---

# 24. SENSEX-Specific Trailing Behavior

For SENSEX:

```text
Wider trail
Stricter liquidity filter
Smaller position size
Avoid deep OTM
Use more conservative entries
Do not over-modify orders
```

Recommended:

```text
Breakeven trigger: 0.8R
Partial trigger: 1.25R
Trail activate: 1.0R
No-progress: 10 minutes
Premium trail: 22% of max premium or option ATR-based
Max spread: higher than NIFTY but still strict
```

---

# 25. Risk Engine Rules

Your risk engine should be separate from strategy.

It should enforce:

```text
max risk per trade
max daily loss
max open positions
max premium deployed
max slippage
max spread
kill switch
```

Example:

```ruby
class RiskEngine
  def initialize(capital:, risk_per_trade: 0.005, max_daily_loss_pct: 0.02, max_positions: 1)
    @capital = capital
    @risk_per_trade = risk_per_trade
    @max_daily_loss_pct = max_daily_loss_pct
    @max_positions = max_positions
    @daily_pnl = 0.0
  end

  def can_trade?
    @daily_pnl > -(@capital * @max_daily_loss_pct)
  end

  def register_pnl(pnl)
    @daily_pnl += pnl
  end

  def risk_amount
    @capital * @risk_per_trade
  end
end
```

Use Dhan P&L exit as backup:

```ruby
dhan_client.pnl_exit(
  profit_value: 10_000,
  loss_value: 5_000,
  product_type: ["INTRADAY"],
  enable_kill_switch: true
)
```

Use kill switch if:

```text
daily loss hit
WebSocket disconnected for too long
option chain stale
order errors repeated
abnormal market behavior
```

---

# 26. Use Correlation IDs Properly

For every position, generate a unique correlation ID:

```ruby
correlation_id = "SCALP-#{asset}-#{strike}-#{Time.now.to_i}-#{rand(1000)}"
```

Use it in orders:

```ruby
dhan_client.place_order(
  correlationId: correlation_id,
  ...
)
```

Then map order update WebSocket messages back to positions:

```ruby
def on_order_update(update)
  correlation_id = update.dig("Data", "CorrelationId")
  status = update.dig("Data", "Status")
  traded_price = update.dig("Data", "TradedPrice")
  traded_qty = update.dig("Data", "TradedQty")

  position = find_position_by_correlation(correlation_id)
  return unless position

  # update position fill state
end
```

This is essential for live scalping.

---

# 27. Reconciliation Loop

Every few seconds, reconcile local state with Dhan:

```ruby
positions = dhan_client.positions
orders = dhan_client.orders
fund = dhan_client.fundlimit
```

Check:

```text
local open positions match Dhan positions
no orphan orders
no duplicate orders
margin available
daily P&L within limit
```

If mismatch:

```text
flatten or reduce risk
```

---

# 28. Handling WebSocket Disconnects

For scalping, stale data is dangerous.

Implement:

```text
heartbeat monitoring
auto reconnect
resubscribe instruments
stale quote detection
```

If market feed disconnects:

```text
Do not open new trades
Tighten exits or flatten if disconnect exceeds threshold
```

Example:

```text
If no market packet for 3 seconds:
  pause new entries

If no market packet for 10 seconds:
  exit open scalps or use REST quote fallback
```

---

# 29. Avoid Over-Modifying Exchange Orders

Because:

```text
Order modifications are capped at 25 per order.
```

Use this design:

```text
Exchange SL = hard catastrophic stop
Local engine = intelligent trailing stop
```

Example:

```text
Place exchange SL at initial hard stop.
Do not modify until breakeven stage.
At breakeven, modify exchange SL to breakeven.
After partial, modify again if needed.
Otherwise, local engine exits directly with a sell order.
```

This avoids hitting modification limits.

---

# 30. Recommended Starting Parameters

For NIFTY scalping:

```text
Timeframe:
  5-min regime
  1-min execution

Supertrend:
  period: 10
  multiplier: 2.2

ADX:
  period: 14
  threshold: 25

Risk per trade:
  0.25% to 0.50%

Initial stop:
  max(25% premium, 1.5 × option ATR, 10 ticks)

Breakeven:
  0.6R

Partial:
  1.0R, book 50%

Trail activation:
  0.8R

No-progress exit:
  12 minutes if R < 0.25

EOD exit:
  15:15
```

For SENSEX scalping:

```text
Risk per trade:
  0.20% to 0.40%

Initial stop:
  max(30% premium, 2.0 × option ATR, 15 ticks)

Breakeven:
  0.8R

Partial:
  1.25R, book 50%

Trail activation:
  1.0R

No-progress exit:
  10 minutes if R < 0.30

Spread filter:
  stricter than NIFTY

EOD exit:
  15:15
```

---

# 31. Metrics You Must Track

Do not judge only by winrate.

Track:

```text
Expectancy
Profit factor
Avg win / avg loss
Max drawdown
Max favorable excursion (MFE)
Max adverse excursion (MAE)
Time in trade
Winner holding time
Loser holding time
No-progress exit count
Vega crush exit count
Breakeven exit count
Partial fill quality
Slippage
Spread cost
Exchange charges
Trail efficiency
Runner contribution
```

Important:

```text
If your winners are not significantly bigger than losers,
naked option buying will fail even with 50% winrate.
```

---

# 32. What To Do in Live Market to Not Miss Opportunities

To avoid missing moves:

## A. Pre-subscribe likely strikes

Before market opens or before signal, subscribe:

```text
ATM-5 to ATM+5 for NIFTY
ATM-5 to ATM+5 for SENSEX
```

Then when signal fires, you already have live data.

---

## B. Use option chain to resolve security IDs

Use expiry list and option chain to get current security IDs.

```text
POST /optionchain/expirylist
POST /optionchain
```

Cache:

```text
expiry
strike
CE security ID
PE security ID
```

---

## C. Use aggressive but controlled entries

For scalping:

```text
Use LIMIT + IOC
Price = ask + 1 or 2 ticks for urgent entry
```

Do not chase too far.

If not filled quickly, skip.

---

## D. Use aggressive exits

For stop/no-progress:

```text
Use LIMIT + IOC
Price = bid - 1 or 2 ticks
```

If not filled, replace quickly.

Emergency:

```text
Use market order or exit all positions API
```

---

# 33. Suggested Production Flow

```text
1. Load instrument master
2. Resolve NIFTY/SENSEX underlying security IDs
3. Get expiry list
4. Build strike security ID map
5. Connect market feed WebSocket
6. Subscribe index + ATM±5 strikes
7. Connect order update WebSocket
8. Fetch option chain every 3–5 seconds
9. Compute 5-min regime and 1-min signals
10. When signal fires:
    - check liquidity
    - check IV
    - check spread
    - check daily risk
    - select strike
    - calculate R-based risk
    - place IOC limit entry
11. On fill:
    - create Position object
    - place exchange hard SL / super order
12. Every 250ms–1s:
    - update market snapshot
    - run PositionManager
    - execute hold/exit/partial/modify
13. Reconcile positions every 5 seconds
14. Enforce daily loss and kill switch
15. Exit all by EOD
```

---

# 34. Important DhanHQ-Specific Rules

Always remember:

```text
Access token validity: 24 hours
Static IP required for order placement, modification, cancellation
Data APIs require subscription
Option chain rate limit: 1 unique request every 3 seconds
Market quote rate limit: 1 request per second
Order APIs: 10 per second
Order modifications: max 25 per order
Full market depth 20/200: NSE only
WebSocket max connections: 5 per user
WebSocket instruments per connection: up to 5000
WebSocket instruments per JSON message: up to 100
```

---

# 35. Final Design Principle

Your system should behave like this:

```text
Entry:
  Supertrend gives direction
  ADX gives permission
  Liquidity/IV/depth give veto

After entry:
  Strike is frozen
  Risk is normalized
  Time is an enemy
  Non-movers are cut
  Breakeven is protected
  Winners are trailed
  Runners are allowed to work

Exit:
  Fast for losers
  Fast for non-movers
  Protective for breakeven trades
  Patient for trend runners

Risk:
  Small per trade
  Hard daily cap
  Kill switch enabled
  Reconciliation continuous
```

If you build this correctly, your goal becomes:

```text
Not high winrate.
Positive expectancy.
```

And that is how naked option buying can survive.
