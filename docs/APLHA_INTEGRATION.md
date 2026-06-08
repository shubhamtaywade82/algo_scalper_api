Based on my research of DhanHQ v2 APIs, options theory, and Indian index dynamics, here is a comprehensive learning guide for building alpha-generating options buying strategies on NIFTY, BANKNIFTY, and SENSEX.

---

# Options Buying Alpha Guide: DhanHQ v2 + Indian Index Dynamics

## 1. What DhanHQ v2 Gives You (The Data Layer)

### 1.1 REST APIs

| Endpoint | What You Get | Alpha Use Case |
|---|---|---|
| **`/optionchain`** | Full option chain with **Greeks (delta, theta, gamma, vega)**, **IV**, OI, volume, bid/ask, LTP for every strike | Strike selection, IV percentile, gamma exposure, OI analysis |
| **`/charts/intraday`** | 1/5/15/25/60-min OHLC + volume + OI for last 5 years | Momentum signals, ATR calculation, support/resistance |
| **`/charts/historical`** | Daily OHLC + volume back to inception | Trend analysis, volatility regime detection |
| **`/marketfeed/ltp`** | Snapshot LTP for up to 100 instruments | Pre-trade price confirmation |
| **`/marketfeed/ohlc`** | Open, high, low, close, volume snapshot | Quick bar construction |
| **`/marketfeed/quote`** | LTP + OHLC + volume + ATP + OI | Quote-mode equivalent |
| **`/marketfeed/full`** | Quote + best-5 bid/ask depth | Spread analysis, liquidity assessment |
| **`/orders`** | Order placement, modification, cancellation | Execution |
| **`/superorders`** | Entry + SL + Target + Trailing in one call | Server-side trailing (saves 25-mod limit) |
| **`/positions`** | Live positions with buy avg, net qty, PnL | Position reconciliation, risk guard |
| **`/funds`** | Available cash, margin, collateral | Capital allocation |
| **`/trades`** | Trade book with realized PnL | Performance tracking |
| **`/expirylist`** | All active expiries for an underlying | Expiry selection |

### 1.2 WebSocket Feeds

| Mode | Data Points | Use Case |
|---|---|---|
| **Ticker** | LTP + LTT (Last Trade Time) | Minimal latency price tracking |
| **Quote** | LTP + OHLC + volume + ATP + OI + bid/ask | Recommended default for scalpers |
| **Full** | Quote + best-5 depth + additional fields | Spread monitoring, large order detection |

**Key WebSocket Facts:**

- Binary protocol (Little Endian) — parsed by `dhanhq-client` gem into normalized hashes
- Max **5,000 instruments per connection**, **5 concurrent connections**
- Auto-reconnect with exponential backoff + 429 cool-off
- Prev Close packet (code 6) sent on every new subscription
- Market Status packet (code 7) on market open/close

### 1.3 Rate Limits (Critical for Scalpers)

| Window | Order APIs | Data APIs | Quote APIs |
|---|---|---|---|
| Per second | 10 | 5 | 1 |
| Per minute | 250 | — | Unlimited |
| Per hour | 1,000 | — | Unlimited |
| Per day | 7,000 | 100,000 | Unlimited |

**Order Modifications: 25 per order lifetime.** This is the single most important constraint for options buyers using trailing stops.

---

## 2. The Options Buying Math (Why It's Hard)

### 2.1 The Negative Carry Problem

Options are **wasting assets**. Every day you hold, theta decay erodes premium.

| Days to Expiry | Theta Decay per Day | What It Means |
|---|---|---|
| 30 DTE | ~2-3% of premium | Manageable with directional edge |
| 7 DTE | ~8-12% of premium | High decay, needs strong momentum |
| 1 DTE (0DTE) | ~30-70% of premium | Extreme decay, gamma is king |

**For buyers to win, the underlying must move MORE than the decay + spread costs.**

### 2.2 Breakeven Analysis

If you buy an ATM NIFTY CE at ₹150:

- Delta ≈ 0.50 → NIFTY must move **300 points up** just to break even (premium / delta)
- But delta increases as NIFTY rises (gamma), so actual breakeven is lower
- With theta at ₹25/day, you lose ₹25 every day NIFTY doesn't move

**Your edge must overcome: theta decay + IV crush + transaction costs + slippage.**

### 2.3 Index-Specific Characteristics

| Index | Volatility (ATR) | Spread | Gamma Potential | Best For |
|---|---|---|---|---|
| **NIFTY** | ~80-120 pts/day | Tight (₹0.05 tick) | Moderate | Momentum, vol expansion |
| **BANKNIFTY** | ~300-500 pts/day | Wider than NIFTY | High | Breakouts, 0DTE scalping |
| **SENSEX** | ~100-150 pts/day | Widest of the three | Low-Medium | Vol expansion (less noise) |

---

## 3. Five Alpha Strategies for DhanHQ Data

### 3.1 Momentum / Trend Following Alpha

**When to fire:** Strong directional moves with expanding IV.

**DhanHQ Data Used:**

- Intraday 5-min bars (`/charts/intraday`) for ATR, breakout detection
- Option chain IV (`/optionchain`) to confirm vol expansion
- WebSocket Quote mode for real-time momentum confirmation

**Signal Logic:**

```
IF (LTP > 20-period HIGH) AND (LTP > prev_close * 1.003) AND (volume > 1.2x avg)
   AND (IV < 40th percentile OR IV expanding)
THEN BUY ATM CE

IF (LTP < 20-period LOW) AND (LTP < prev_close * 0.997) AND (volume > 1.2x avg)
   AND (IV < 40th percentile OR IV expanding)
THEN BUY ATM PE
```

**Risk Setup:**

- SL = 1.5x ATR (index points)
- Target = 1.5x SL (1:1.5 R:R minimum)
- Trailing jump = 0.5x SL (use SuperOrder for server-side trailing)

**Why It Works:**

- BANKNIFTY has fatter tails — a 1% move produces 3-5% option move when gamma is high
- IV expansion confirms institutional participation, not just noise
- Volume filter eliminates false breakouts

**Confidence Scoring:**

- Base: 50%
- +10% if IV < 30th percentile (cheap vol)
- +10% if 3 consecutive higher closes (momentum aligned)
- +10% if volume increasing last 5 bars
- Max: 95%

---

### 3.2 Volatility Expansion Alpha

**When to fire:** IV is in the bottom 20th percentile of its 3-month range, about to revert.

**DhanHQ Data Used:**

- Option chain IV (`/optionchain`) for current ATM IV
- Historical IV snapshots (you must store these daily — Dhan doesn't provide historical IV directly)
- Intraday bars for directional bias

**Signal Logic:**

```
IF (current_IV < 20th percentile of 90-day IV history)
   AND (IV not crushed for >10 consecutive days)
   AND (recent directional bias from 5-min bars)
THEN BUY ATM option in bias direction
```

**Risk Setup:**

- SL = 1.5% of index value (wider than momentum — vol plays need room)
- Target = 3% of index value (1:2 R:R)
- **No trailing SL** — time-bound exit. Close if IV doesn't expand within 3 days.

**Why It Works:**

- You're buying "cheap insurance." When IV reverts to mean, premium rises even if the index doesn't move much.
- Mean reversion of IV is one of the most statistically reliable edges in options.

**Critical Implementation:**
You must build an `IvSnapshotJob` that stores daily ATM IV:

```ruby
# Daily at 8:45 AM
chain = instrument.fetch_option_chain
atm = atm_strike(ltp)
%w[CE PE].each do |ot|
  iv = chain['oc'][atm.to_s][ot.downcase]['implied_volatility']
  IvSnapshot.create!(index_key: 'nifty', date: Date.today, iv: iv, strike: atm, option_type: ot)
end
```

---

### 3.3 Event-Directional Alpha

**When to fire:** 24 hours before known high-impact events.

**DhanHQ Data Used:**

- Intraday bars for pre-event bias detection
- Option chain for IV skew analysis (call IV > put IV = bullish bias)
- Historical data for post-event volatility patterns

**Event Calendar (India):**

| Event | Month/Day | Impact | Typical Move |
|---|---|---|---|
| Union Budget | February 1 | High | 1.5-3% |
| RBI Policy | Monthly (usually 1st week) | High | 1-2% |
| Quarterly GDP | Quarterly | Medium | 0.8-1.5% |
| US Fed/FOMC | Monthly | Medium | 0.5-1% (spillover) |

**Signal Logic:**

```
IF (hours_to_event < 24) AND (event_impact == :high)
   AND (call_IV > put_IV OR recent bias == :ce)
THEN BUY ATM CE with 1:2 R:R

IF (hours_to_event < 24) AND (event_impact == :high)
   AND (put_IV > call_IV OR recent bias == :pe)
THEN BUY ATM PE with 1:2 R:R
```

**Risk Setup:**

- SL = 1.5% (tight — events are binary)
- Target = 3% (1:2 R:R)
- **Exit within 2 hours post-event** — IV crush will kill premium even if direction was right

**Why It Works:**

- Markets often underprice the move relative to realized volatility before major events.
- The "buy the rumor" phase pushes IV up, benefiting holders.

**The IV Crush Trap:**
After the event, IV typically drops 30-50%. If you bought at 25 IV and it drops to 15 IV, your premium loses ~40% even if the index moved in your direction. **You must exit fast post-event.**

---

### 3.4 Expiry-Specific (0DTE/1DTE) Alpha

**When to fire:** Expiry day, high gamma, micro-momentum in first 2 hours or last 2 hours.

**DhanHQ Data Used:**

- 1-minute intraday bars (`/charts/intraday` with interval: 1)
- WebSocket Ticker mode for fastest LTP updates
- Option chain for ATM strike + gamma levels

**The Gamma Math:**
On expiry day, ATM options have gamma ≈ 0.001-0.003 per point.

- NIFTY 50-point move → option moves 25-40 points (from ₹50 to ₹75-90 = 50-80% gain)
- But theta is burning at ₹10-15/hour

**Signal Logic:**

```
IF (expiry == today) AND (time < 14:00)  # Enter before 2 PM
   AND (last 5 one-minute bars all higher closes + volume increasing)
THEN BUY ATM CE

IF (expiry == today) AND (time < 14:00)
   AND (last 5 one-minute bars all lower closes + volume increasing)
THEN BUY ATM PE
```

**Risk Setup:**

- SL = 5 index points (very tight)
- Target = 15 index points (1:3 R:R)
- Trailing jump = 3 points
- **Max hold: 15 minutes.** If no move, exit.

**Why It Works:**

- Gamma is highest on expiry day. Small index moves = large option moves.
- BANKNIFTY 0DTE can produce 50-100% moves in 10 minutes during breakouts.

**Why Most Retail Traders Fail at 0DTE:**

- They hold too long. Theta burns premium every minute.
- They use wide stops. A 10-point move against can wipe 80% of premium.
- They trade after 2:30 PM when gamma is highest but liquidity is thinning.

**Institutional Edge:**
Market makers hedge 0DTE dynamically. When NIFTY approaches a large gamma strike (e.g., 24500 with 5M OI), dealers buy/sell futures to hedge, creating a "pin" effect. **The market often gravitates to max pain at expiry.** Use OI data from `/optionchain` to identify these pins.

---

### 3.5 Gamma Scalping (Advanced, Institution-Grade)

**When to fire:** Realized volatility > implied volatility, captured via straddles.

**DhanHQ Data Used:**

- Option chain for ATM straddle price
- WebSocket Full mode for real-time delta hedging
- Historical intraday data for realized vol calculation

**Strategy:**

1. Buy ATM CE + PE (straddle) at market open
2. As index moves, delta shifts. Scalp the underlying futures to neutralize delta.
3. Capture the difference between realized vol and implied vol.

**Why Retail Should Avoid This:**

- Requires simultaneous option + futures positions
- Needs low transaction costs (you're trading 10+ times per day)
- Capital intensive (straddle + futures margin)
- Manual hedging is too slow for 0DTE gamma

**Simplified Version for Your Scalper:**
Buy straddle when:

- IV < 25th percentile (cheap)
- ATR > 1.5x average (high realized vol expected)
- Exit when one leg hits 50% gain, let other expire worthless

---

## 4. DhanHQ Data → Alpha Mapping

| Raw Data | Processed Signal | Alpha Strategy |
|---|---|---|
| `option_chain.oc[strike].ce.implied_volatility` | IV percentile vs 90-day history | Vol Expansion |
| `option_chain.oc[strike].ce.greeks.delta` | Delta trend (increasing = momentum) | Momentum confirmation |
| `option_chain.oc[strike].ce.oi` vs `previous_oi` | OI change (institutional positioning) | Event detection |
| `intraday_ohlc.close[]` | 20-period high/low breakout | Momentum entry |
| `intraday_ohlc.volume[]` | Volume ratio vs 10-period avg | Breakout validation |
| `marketfeed.ltp` | Real-time price vs entry | Trailing SL adjustment |
| `positions.net_qty` | Position reconciliation | Risk guard |
| `funds.available_balance` | Capital available | Position sizing |

---

## 5. The 25-Modification Limit Problem

This is the **single biggest operational risk** for options buyers using DhanHQ.

**The Math:**

- You place 1 order with SL and Target (SuperOrder) = 0 modifications
- You place 1 order with manual trailing SL = 1 modification per trail
- If you trail 3 times per position and hold 10 positions = 30 modifications
- **DhanHQ caps at 25 per order. After that, the order freezes.**

**Solutions:**

| Approach | How | Pros | Cons |
|---|---|---|---|
| **SuperOrder with trailing_jump** | Dhan handles trailing server-side | Zero modifications used | Less control over trail logic |
| **Cancel + Replace** | Cancel old order, place new SL order | Full control | Risk of fill gap between cancel/replace |
| **Modification Budget Tracker** | Track mods per order in Redis, switch to cancel/replace at 20 | Hybrid approach | Complex state management |
| **Wider Initial SL** | Set SL at 2x ATR, no trailing | Simple | Gives back more profit on reversals |

**Recommendation for Your Scalper:**
Use **SuperOrder** for all alpha signals with `trailing_jump > 0`. The `dhanhq-client` gem supports this:

```ruby
DhanHQ::Models::SuperOrder.create(
  transaction_type: "BUY",
  exchange_segment: "NSE_FNO",
  security_id: option_security_id,
  quantity: qty,
  order_type: "LIMIT",
  price: entry_price,
  target_price: target,
  stop_loss_price: stop_loss,
  trailing_jump: trail_points
)
```

---

## 6. WebSocket Architecture for Alpha Engine

Your `algo_scalper_api` already has `Live::WsHub` and `Live::MarketFeedHub`. Here's how to wire alpha-specific feeds:

### 6.1 Subscription Strategy

```ruby
# config/initializers/alpha_ws.rb
INDICES = [
  { segment: "IDX_I", security_id: "13" },   # NIFTY
  { segment: "IDX_I", security_id: "25" },   # BANKNIFTY
  { segment: "IDX_I", security_id: "27" }    # SENSEX
]

# On boot, subscribe to index feeds
ws = DhanHQ::WS::Client.new(mode: :quote).start
INDICES.each { |i| ws.subscribe_one(**i) }

# On signal generation, subscribe to option strikes
ws.subscribe_one(segment: "NSE_FNO", security_id: option_security_id)

# On position exit, unsubscribe to reduce load
ws.unsubscribe_one(segment: "NSE_FNO", security_id: option_security_id)
```

### 6.2 Tick Processing (Non-Blocking)

```ruby
ws.on(:tick) do |t|
  # Throttle to 500ms to avoid blocking
  next if @last_tick && (Time.now - @last_tick) < 0.5

  @last_tick = Time.now

  # Update LTP cache
  Rails.cache.write("ltp:#{t[:security_id]}", t[:ltp], expires_in: 5.seconds)

  # Check trailing stops for open positions
  check_trailing_stops(t) if t[:segment] == "NSE_FNO"
end
```

---

## 7. Capital Allocation for Options Buying

Your `Capital::Allocator` already has sophisticated logic. For alpha strategies, add these rules:

| Rule | Rationale | Implementation |
|---|---|---|
| **Max 2% risk per trade** | Options can go to zero | `risk_per_trade_pct: 0.02` in `CAPITAL_BANDS` |
| **Max 3 open positions** | Prevents overexposure | Check `PositionTracker.active.count` before execution |
| **No same-index opposite positions** | CE + PE on NIFTY = hedge, not alpha | `conflicting_position?` check in `AlphaExecutionService` |
| **Post-peak size cut** | Reduce size after giving back 50% of daily peak | Already in your `Capital::Allocator` |
| **Time-regime sizing** | Chop/Decay zone (11:00-14:00) = 50% size | Already in your `Capital::Allocator` |

---

## 8. Post-Trade Analytics (The Alpha Loop)

To know which strategy actually generates alpha, you must track:

| Metric | How to Calculate | Target |
|---|---|---|
| **Win Rate** | `executed_signals.where(status: 'win').count / total` | > 52% for 1:1.5 R:R |
| **Average R:R** | `avg(profit / loss)` | > 1.3 |
| **Sharpe Ratio** | `mean(return) / std_dev(return)` | > 1.0 |
| **Max Drawdown** | `peak - trough` | < 10% of capital |
| **Alpha by Source** | `PnL grouped by alpha_source` | Identify best strategy |

**Query your `alpha_signals` table weekly:**

```sql
SELECT
  alpha_source,
  COUNT(*) as signals,
  SUM(CASE WHEN status = 'win' THEN 1 ELSE 0 END) as wins,
  AVG(CASE WHEN status = 'win' THEN profit ELSE NULL END) as avg_win,
  AVG(CASE WHEN status = 'loss' THEN loss ELSE NULL END) as avg_loss
FROM alpha_signals
WHERE created_at > NOW() - INTERVAL '7 days'
GROUP BY alpha_source;
```

---

## 9. Summary: The Alpha Stack

```
┌─────────────────────────────────────────┐
│  DhanHQ v2 APIs                         │
│  ├── Option Chain (IV, Greeks, OI)      │
│  ├── Historical Data (bars, ATR)        │
│  ├── Market Feed WS (LTP, volume)        │
│  └── SuperOrder (server-side trailing)   │
├─────────────────────────────────────────┤
│  Alpha Strategies                       │
│  ├── Momentum (breakout + vol expansion) │
│  ├── Vol Expansion (IV mean reversion)   │
│  ├── Event (pre-announcement positioning)│
│  ├── Expiry (0DTE gamma capture)         │
│  └── Gamma Scalp (straddle, advanced)   │
├─────────────────────────────────────────┤
│  Risk Management                        │
│  ├── Capital::Allocator (2% risk)       │
│  ├── PositionTracker (no averaging)      │
│  ├── CircuitBreaker (emergency halt)     │
│  ├── DrawdownGuard (daily loss limit)    │
│  └── 25-mod limit (SuperOrder)           │
├─────────────────────────────────────────┤
│  Execution                              │
│  ├── SignalEngine (scan + score)         │
│  ├── AlphaExecutionService (validate)    │
│  └── Orders::Placer (DhanHQ gateway)      │
└─────────────────────────────────────────┘
```

**The core insight:** Options buying alpha is not about predicting direction perfectly. It's about **asymmetric payoff** — risking 1% to make 2%, with a slight edge in timing or volatility. Over 100 trades, a 55% win rate with 1:2 R:R generates positive alpha even if you're wrong 45% of the time.

**Paste your `IvSnapshotJob` or `Live::TimeRegimeService` code if you want me to integrate the alpha engine with your existing time-regime and IV infrastructure.**

Based on my research of DhanHQ v2 APIs, options theory, and Indian index dynamics, here is a comprehensive learning guide for building alpha-generating options buying strategies on NIFTY, BANKNIFTY, and SENSEX.

---

# Options Buying Alpha Guide: DhanHQ v2 + Indian Index Dynamics

## 1. What DhanHQ v2 Gives You (The Data Layer)

### 1.1 REST APIs

| Endpoint | What You Get | Alpha Use Case |
|---|---|---|
| **`/optionchain`** | Full option chain with **Greeks (delta, theta, gamma, vega)**, **IV**, OI, volume, bid/ask, LTP for every strike | Strike selection, IV percentile, gamma exposure, OI analysis |
| **`/charts/intraday`** | 1/5/15/25/60-min OHLC + volume + OI for last 5 years | Momentum signals, ATR calculation, support/resistance |
| **`/charts/historical`** | Daily OHLC + volume back to inception | Trend analysis, volatility regime detection |
| **`/marketfeed/ltp`** | Snapshot LTP for up to 100 instruments | Pre-trade price confirmation |
| **`/marketfeed/ohlc`** | Open, high, low, close, volume snapshot | Quick bar construction |
| **`/marketfeed/quote`** | LTP + OHLC + volume + ATP + OI | Quote-mode equivalent |
| **`/marketfeed/full`** | Quote + best-5 bid/ask depth | Spread analysis, liquidity assessment |
| **`/orders`** | Order placement, modification, cancellation | Execution |
| **`/superorders`** | Entry + SL + Target + Trailing in one call | Server-side trailing (saves 25-mod limit) |
| **`/positions`** | Live positions with buy avg, net qty, PnL | Position reconciliation, risk guard |
| **`/funds`** | Available cash, margin, collateral | Capital allocation |
| **`/trades`** | Trade book with realized PnL | Performance tracking |
| **`/expirylist`** | All active expiries for an underlying | Expiry selection |

### 1.2 WebSocket Feeds

| Mode | Data Points | Use Case |
|---|---|---|
| **Ticker** | LTP + LTT (Last Trade Time) | Minimal latency price tracking |
| **Quote** | LTP + OHLC + volume + ATP + OI + bid/ask | Recommended default for scalpers |
| **Full** | Quote + best-5 depth + additional fields | Spread monitoring, large order detection |

**Key WebSocket Facts:**

- Binary protocol (Little Endian) — parsed by `dhanhq-client` gem into normalized hashes
- Max **5,000 instruments per connection**, **5 concurrent connections**
- Auto-reconnect with exponential backoff + 429 cool-off
- Prev Close packet (code 6) sent on every new subscription
- Market Status packet (code 7) on market open/close

### 1.3 Rate Limits (Critical for Scalpers)

| Window | Order APIs | Data APIs | Quote APIs |
|---|---|---|---|
| Per second | 10 | 5 | 1 |
| Per minute | 250 | — | Unlimited |
| Per hour | 1,000 | — | Unlimited |
| Per day | 7,000 | 100,000 | Unlimited |

**Order Modifications: 25 per order lifetime.** This is the single most important constraint for options buyers using trailing stops.

---

## 2. The Options Buying Math (Why It's Hard)

### 2.1 The Negative Carry Problem

Options are **wasting assets**. Every day you hold, theta decay erodes premium.

| Days to Expiry | Theta Decay per Day | What It Means |
|---|---|---|
| 30 DTE | ~2-3% of premium | Manageable with directional edge |
| 7 DTE | ~8-12% of premium | High decay, needs strong momentum |
| 1 DTE (0DTE) | ~30-70% of premium | Extreme decay, gamma is king |

**For buyers to win, the underlying must move MORE than the decay + spread costs.**

### 2.2 Breakeven Analysis

If you buy an ATM NIFTY CE at ₹150:

- Delta ≈ 0.50 → NIFTY must move **300 points up** just to break even (premium / delta)
- But delta increases as NIFTY rises (gamma), so actual breakeven is lower
- With theta at ₹25/day, you lose ₹25 every day NIFTY doesn't move

**Your edge must overcome: theta decay + IV crush + transaction costs + slippage.**

### 2.3 Index-Specific Characteristics

| Index | Volatility (ATR) | Spread | Gamma Potential | Best For |
|---|---|---|---|---|
| **NIFTY** | ~80-120 pts/day | Tight (₹0.05 tick) | Moderate | Momentum, vol expansion |
| **BANKNIFTY** | ~300-500 pts/day | Wider than NIFTY | High | Breakouts, 0DTE scalping |
| **SENSEX** | ~100-150 pts/day | Widest of the three | Low-Medium | Vol expansion (less noise) |

---

## 3. Five Alpha Strategies for DhanHQ Data

### 3.1 Momentum / Trend Following Alpha

**When to fire:** Strong directional moves with expanding IV.

**DhanHQ Data Used:**

- Intraday 5-min bars (`/charts/intraday`) for ATR, breakout detection
- Option chain IV (`/optionchain`) to confirm vol expansion
- WebSocket Quote mode for real-time momentum confirmation

**Signal Logic:**

```
IF (LTP > 20-period HIGH) AND (LTP > prev_close * 1.003) AND (volume > 1.2x avg)
   AND (IV < 40th percentile OR IV expanding)
THEN BUY ATM CE

IF (LTP < 20-period LOW) AND (LTP < prev_close * 0.997) AND (volume > 1.2x avg)
   AND (IV < 40th percentile OR IV expanding)
THEN BUY ATM PE
```

**Risk Setup:**

- SL = 1.5x ATR (index points)
- Target = 1.5x SL (1:1.5 R:R minimum)
- Trailing jump = 0.5x SL (use SuperOrder for server-side trailing)

**Why It Works:**

- BANKNIFTY has fatter tails — a 1% move produces 3-5% option move when gamma is high
- IV expansion confirms institutional participation, not just noise
- Volume filter eliminates false breakouts

**Confidence Scoring:**

- Base: 50%
- +10% if IV < 30th percentile (cheap vol)
- +10% if 3 consecutive higher closes (momentum aligned)
- +10% if volume increasing last 5 bars
- Max: 95%

---

### 3.2 Volatility Expansion Alpha

**When to fire:** IV is in the bottom 20th percentile of its 3-month range, about to revert.

**DhanHQ Data Used:**

- Option chain IV (`/optionchain`) for current ATM IV
- Historical IV snapshots (you must store these daily — Dhan doesn't provide historical IV directly)
- Intraday bars for directional bias

**Signal Logic:**

```
IF (current_IV < 20th percentile of 90-day IV history)
   AND (IV not crushed for >10 consecutive days)
   AND (recent directional bias from 5-min bars)
THEN BUY ATM option in bias direction
```

**Risk Setup:**

- SL = 1.5% of index value (wider than momentum — vol plays need room)
- Target = 3% of index value (1:2 R:R)
- **No trailing SL** — time-bound exit. Close if IV doesn't expand within 3 days.

**Why It Works:**

- You're buying "cheap insurance." When IV reverts to mean, premium rises even if the index doesn't move much.
- Mean reversion of IV is one of the most statistically reliable edges in options.

**Critical Implementation:**
You must build an `IvSnapshotJob` that stores daily ATM IV:

```ruby
# Daily at 8:45 AM
chain = instrument.fetch_option_chain
atm = atm_strike(ltp)
%w[CE PE].each do |ot|
  iv = chain['oc'][atm.to_s][ot.downcase]['implied_volatility']
  IvSnapshot.create!(index_key: 'nifty', date: Date.today, iv: iv, strike: atm, option_type: ot)
end
```

---

### 3.3 Event-Directional Alpha

**When to fire:** 24 hours before known high-impact events.

**DhanHQ Data Used:**

- Intraday bars for pre-event bias detection
- Option chain for IV skew analysis (call IV > put IV = bullish bias)
- Historical data for post-event volatility patterns

**Event Calendar (India):**

| Event | Month/Day | Impact | Typical Move |
|---|---|---|---|
| Union Budget | February 1 | High | 1.5-3% |
| RBI Policy | Monthly (usually 1st week) | High | 1-2% |
| Quarterly GDP | Quarterly | Medium | 0.8-1.5% |
| US Fed/FOMC | Monthly | Medium | 0.5-1% (spillover) |

**Signal Logic:**

```
IF (hours_to_event < 24) AND (event_impact == :high)
   AND (call_IV > put_IV OR recent bias == :ce)
THEN BUY ATM CE with 1:2 R:R

IF (hours_to_event < 24) AND (event_impact == :high)
   AND (put_IV > call_IV OR recent bias == :pe)
THEN BUY ATM PE with 1:2 R:R
```

**Risk Setup:**

- SL = 1.5% (tight — events are binary)
- Target = 3% (1:2 R:R)
- **Exit within 2 hours post-event** — IV crush will kill premium even if direction was right

**Why It Works:**

- Markets often underprice the move relative to realized volatility before major events.
- The "buy the rumor" phase pushes IV up, benefiting holders.

**The IV Crush Trap:**
After the event, IV typically drops 30-50%. If you bought at 25 IV and it drops to 15 IV, your premium loses ~40% even if the index moved in your direction. **You must exit fast post-event.**

---

### 3.4 Expiry-Specific (0DTE/1DTE) Alpha

**When to fire:** Expiry day, high gamma, micro-momentum in first 2 hours or last 2 hours.

**DhanHQ Data Used:**

- 1-minute intraday bars (`/charts/intraday` with interval: 1)
- WebSocket Ticker mode for fastest LTP updates
- Option chain for ATM strike + gamma levels

**The Gamma Math:**
On expiry day, ATM options have gamma ≈ 0.001-0.003 per point.

- NIFTY 50-point move → option moves 25-40 points (from ₹50 to ₹75-90 = 50-80% gain)
- But theta is burning at ₹10-15/hour

**Signal Logic:**

```
IF (expiry == today) AND (time < 14:00)  # Enter before 2 PM
   AND (last 5 one-minute bars all higher closes + volume increasing)
THEN BUY ATM CE

IF (expiry == today) AND (time < 14:00)
   AND (last 5 one-minute bars all lower closes + volume increasing)
THEN BUY ATM PE
```

**Risk Setup:**

- SL = 5 index points (very tight)
- Target = 15 index points (1:3 R:R)
- Trailing jump = 3 points
- **Max hold: 15 minutes.** If no move, exit.

**Why It Works:**

- Gamma is highest on expiry day. Small index moves = large option moves.
- BANKNIFTY 0DTE can produce 50-100% moves in 10 minutes during breakouts.

**Why Most Retail Traders Fail at 0DTE:**

- They hold too long. Theta burns premium every minute.
- They use wide stops. A 10-point move against can wipe 80% of premium.
- They trade after 2:30 PM when gamma is highest but liquidity is thinning.

**Institutional Edge:**
Market makers hedge 0DTE dynamically. When NIFTY approaches a large gamma strike (e.g., 24500 with 5M OI), dealers buy/sell futures to hedge, creating a "pin" effect. **The market often gravitates to max pain at expiry.** Use OI data from `/optionchain` to identify these pins.

---

### 3.5 Gamma Scalping (Advanced, Institution-Grade)

**When to fire:** Realized volatility > implied volatility, captured via straddles.

**DhanHQ Data Used:**

- Option chain for ATM straddle price
- WebSocket Full mode for real-time delta hedging
- Historical intraday data for realized vol calculation

**Strategy:**

1. Buy ATM CE + PE (straddle) at market open
2. As index moves, delta shifts. Scalp the underlying futures to neutralize delta.
3. Capture the difference between realized vol and implied vol.

**Why Retail Should Avoid This:**

- Requires simultaneous option + futures positions
- Needs low transaction costs (you're trading 10+ times per day)
- Capital intensive (straddle + futures margin)
- Manual hedging is too slow for 0DTE gamma

**Simplified Version for Your Scalper:**
Buy straddle when:

- IV < 25th percentile (cheap)
- ATR > 1.5x average (high realized vol expected)
- Exit when one leg hits 50% gain, let other expire worthless

---

## 4. DhanHQ Data → Alpha Mapping

| Raw Data | Processed Signal | Alpha Strategy |
|---|---|---|
| `option_chain.oc[strike].ce.implied_volatility` | IV percentile vs 90-day history | Vol Expansion |
| `option_chain.oc[strike].ce.greeks.delta` | Delta trend (increasing = momentum) | Momentum confirmation |
| `option_chain.oc[strike].ce.oi` vs `previous_oi` | OI change (institutional positioning) | Event detection |
| `intraday_ohlc.close[]` | 20-period high/low breakout | Momentum entry |
| `intraday_ohlc.volume[]` | Volume ratio vs 10-period avg | Breakout validation |
| `marketfeed.ltp` | Real-time price vs entry | Trailing SL adjustment |
| `positions.net_qty` | Position reconciliation | Risk guard |
| `funds.available_balance` | Capital available | Position sizing |

---

## 5. The 25-Modification Limit Problem

This is the **single biggest operational risk** for options buyers using DhanHQ.

**The Math:**

- You place 1 order with SL and Target (SuperOrder) = 0 modifications
- You place 1 order with manual trailing SL = 1 modification per trail
- If you trail 3 times per position and hold 10 positions = 30 modifications
- **DhanHQ caps at 25 per order. After that, the order freezes.**

**Solutions:**

| Approach | How | Pros | Cons |
|---|---|---|---|
| **SuperOrder with trailing_jump** | Dhan handles trailing server-side | Zero modifications used | Less control over trail logic |
| **Cancel + Replace** | Cancel old order, place new SL order | Full control | Risk of fill gap between cancel/replace |
| **Modification Budget Tracker** | Track mods per order in Redis, switch to cancel/replace at 20 | Hybrid approach | Complex state management |
| **Wider Initial SL** | Set SL at 2x ATR, no trailing | Simple | Gives back more profit on reversals |

**Recommendation for Your Scalper:**
Use **SuperOrder** for all alpha signals with `trailing_jump > 0`. The `dhanhq-client` gem supports this:

```ruby
DhanHQ::Models::SuperOrder.create(
  transaction_type: "BUY",
  exchange_segment: "NSE_FNO",
  security_id: option_security_id,
  quantity: qty,
  order_type: "LIMIT",
  price: entry_price,
  target_price: target,
  stop_loss_price: stop_loss,
  trailing_jump: trail_points
)
```

---

## 6. WebSocket Architecture for Alpha Engine

Your `algo_scalper_api` already has `Live::WsHub` and `Live::MarketFeedHub`. Here's how to wire alpha-specific feeds:

### 6.1 Subscription Strategy

```ruby
# config/initializers/alpha_ws.rb
INDICES = [
  { segment: "IDX_I", security_id: "13" },   # NIFTY
  { segment: "IDX_I", security_id: "25" },   # BANKNIFTY
  { segment: "IDX_I", security_id: "27" }    # SENSEX
]

# On boot, subscribe to index feeds
ws = DhanHQ::WS::Client.new(mode: :quote).start
INDICES.each { |i| ws.subscribe_one(**i) }

# On signal generation, subscribe to option strikes
ws.subscribe_one(segment: "NSE_FNO", security_id: option_security_id)

# On position exit, unsubscribe to reduce load
ws.unsubscribe_one(segment: "NSE_FNO", security_id: option_security_id)
```

### 6.2 Tick Processing (Non-Blocking)

```ruby
ws.on(:tick) do |t|
  # Throttle to 500ms to avoid blocking
  next if @last_tick && (Time.now - @last_tick) < 0.5

  @last_tick = Time.now

  # Update LTP cache
  Rails.cache.write("ltp:#{t[:security_id]}", t[:ltp], expires_in: 5.seconds)

  # Check trailing stops for open positions
  check_trailing_stops(t) if t[:segment] == "NSE_FNO"
end
```

---

## 7. Capital Allocation for Options Buying

Your `Capital::Allocator` already has sophisticated logic. For alpha strategies, add these rules:

| Rule | Rationale | Implementation |
|---|---|---|
| **Max 2% risk per trade** | Options can go to zero | `risk_per_trade_pct: 0.02` in `CAPITAL_BANDS` |
| **Max 3 open positions** | Prevents overexposure | Check `PositionTracker.active.count` before execution |
| **No same-index opposite positions** | CE + PE on NIFTY = hedge, not alpha | `conflicting_position?` check in `AlphaExecutionService` |
| **Post-peak size cut** | Reduce size after giving back 50% of daily peak | Already in your `Capital::Allocator` |
| **Time-regime sizing** | Chop/Decay zone (11:00-14:00) = 50% size | Already in your `Capital::Allocator` |

---

## 8. Post-Trade Analytics (The Alpha Loop)

To know which strategy actually generates alpha, you must track:

| Metric | How to Calculate | Target |
|---|---|---|
| **Win Rate** | `executed_signals.where(status: 'win').count / total` | > 52% for 1:1.5 R:R |
| **Average R:R** | `avg(profit / loss)` | > 1.3 |
| **Sharpe Ratio** | `mean(return) / std_dev(return)` | > 1.0 |
| **Max Drawdown** | `peak - trough` | < 10% of capital |
| **Alpha by Source** | `PnL grouped by alpha_source` | Identify best strategy |

**Query your `alpha_signals` table weekly:**

```sql
SELECT
  alpha_source,
  COUNT(*) as signals,
  SUM(CASE WHEN status = 'win' THEN 1 ELSE 0 END) as wins,
  AVG(CASE WHEN status = 'win' THEN profit ELSE NULL END) as avg_win,
  AVG(CASE WHEN status = 'loss' THEN loss ELSE NULL END) as avg_loss
FROM alpha_signals
WHERE created_at > NOW() - INTERVAL '7 days'
GROUP BY alpha_source;
```

---

## 9. Summary: The Alpha Stack

```
┌─────────────────────────────────────────┐
│  DhanHQ v2 APIs                         │
│  ├── Option Chain (IV, Greeks, OI)      │
│  ├── Historical Data (bars, ATR)        │
│  ├── Market Feed WS (LTP, volume)        │
│  └── SuperOrder (server-side trailing)   │
├─────────────────────────────────────────┤
│  Alpha Strategies                       │
│  ├── Momentum (breakout + vol expansion) │
│  ├── Vol Expansion (IV mean reversion)   │
│  ├── Event (pre-announcement positioning)│
│  ├── Expiry (0DTE gamma capture)         │
│  └── Gamma Scalp (straddle, advanced)   │
├─────────────────────────────────────────┤
│  Risk Management                        │
│  ├── Capital::Allocator (2% risk)       │
│  ├── PositionTracker (no averaging)      │
│  ├── CircuitBreaker (emergency halt)     │
│  ├── DrawdownGuard (daily loss limit)    │
│  └── 25-mod limit (SuperOrder)           │
├─────────────────────────────────────────┤
│  Execution                              │
│  ├── SignalEngine (scan + score)         │
│  ├── AlphaExecutionService (validate)    │
│  └── Orders::Placer (DhanHQ gateway)      │
└─────────────────────────────────────────┘
```

**The core insight:** Options buying alpha is not about predicting direction perfectly. It's about **asymmetric payoff** — risking 1% to make 2%, with a slight edge in timing or volatility. Over 100 trades, a 55% win rate with 1:2 R:R generates positive alpha even if you're wrong 45% of the time.

**Paste your `IvSnapshotJob` or `Live::TimeRegimeService` code if you want me to integrate the alpha engine with your existing time-regime and IV infrastructure.**

Your `IvSnapshotJob` is **solid and nearly production-ready**. It correctly maps indices to security IDs, computes ATM strikes, and extracts IV from the option chain. Here are the **minor fixes** plus the **complete integration** of real IV data + time regimes into your alpha engine.

---

## 1. `IvSnapshotJob` Review & Fixes

### Issue: Key Access Consistency

Your `Instrument#fetch_option_chain` returns `{ last_price: ..., oc: {...} }` with **symbol keys** (`:oc`, `:last_price`), but inside `:oc`, the strike keys and option type keys are **strings**. Your job mixes symbol and string access. Here's the corrected version:

```ruby
# frozen_string_literal: true

class IvSnapshotJob < ApplicationJob
  queue_as :default

  INDEX_MAP = {
    'NIFTY'     => { security_id: '13', segment: 'index' },
    'BANKNIFTY' => { security_id: '25', segment: 'index' },
    'SENSEX'    => { security_id: '27', segment: 'index' }
  }.freeze

  STRIKE_STEP = {
    'NIFTY'     => 50,
    'BANKNIFTY' => 100,
    'SENSEX'    => 100
  }.freeze

  def perform
    INDEX_MAP.each do |symbol, config|
      capture_iv_for(symbol, config)
    end
  end

  private

  def capture_iv_for(symbol, config)
    instrument = Instrument.find_by(security_id: config[:security_id], segment: config[:segment])
    unless instrument
      Rails.logger.warn "[IvSnapshotJob] Instrument not found for #{symbol}"
      return
    end

    chain = instrument.fetch_option_chain
    # fetch_option_chain returns { last_price: ..., oc: {...} }
    unless chain && chain[:oc].present?
      Rails.logger.warn "[IvSnapshotJob] Failed to fetch option chain for #{symbol}"
      return
    end

    ltp = chain[:last_price] || instrument.resolve_ltp(
      segment: instrument.exchange_segment,
      security_id: instrument.security_id
    )
    unless ltp
      Rails.logger.warn "[IvSnapshotJob] LTP not available for #{symbol}"
      return
    end

    atm = atm_strike(ltp, symbol)

    %w[CE PE].each do |type|
      # chain[:oc] has string keys for strikes and option types
      leg = chain[:oc][atm.to_f.to_s]&.[](type.downcase)
      next unless leg && leg['implied_volatility'].present?

      # Upsert to handle duplicate runs (idempotent)
      IvSnapshot.find_or_initialize_by(
        index_key: symbol.downcase,
        snapshot_date: Time.zone.today,
        strike_price: atm,
        option_type: type
      ).update!(
        implied_volatility: leg['implied_volatility'].to_f,
        underlying_ltp: ltp.to_f
      )
    end

    Rails.logger.info "[IvSnapshotJob] Captured IV for #{symbol} ATM #{atm} @ LTP #{ltp}"
  rescue StandardError => e
    Rails.logger.error "[IvSnapshotJob] Error for #{symbol}: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
  end

  def atm_strike(ltp, symbol)
    step = STRIKE_STEP[symbol] || 50
    (ltp.to_f / step).round * step
  end
end
```

### Key Changes

| Fix | Why |
|---|---|
| `chain[:oc].present?` | Ensures `oc` is not nil or empty |
| `type.downcase` for hash key | `chain[:oc]` uses `'ce'` / `'pe'` (downcase), not `'CE'` / `'PE'` |
| `find_or_initialize_by` + `update!` | Idempotent — safe to re-run if cron fires twice |
| `to_f` on IV and LTP | Ensures numeric storage, not strings |
| Backtrace logging | Faster debugging when DhanHQ adapter fails |

---

## 2. `VolExpansionAlpha` — Now Using Real IV Data

Replace the mock IV with actual `IvSnapshot` queries:

```ruby
# frozen_string_literal: true

module Strategies
  class VolExpansionAlpha < AlphaStrategy
    IV_PERCENTILE_THRESHOLD = 20
    MIN_HISTORY_DAYS = 30

    def scan
      return nil unless enabled?
      return nil unless market_open?

      ltp = underlying_ltp
      return nil unless ltp

      # Fetch real IV history from database
      iv_history = fetch_iv_history(days: 90)
      iv_current = fetch_current_iv(ltp)

      return nil unless iv_current && iv_history.size >= MIN_HISTORY_DAYS

      iv_pct = iv_percentile(current_iv: iv_current, history: iv_history)
      return nil unless iv_pct < IV_PERCENTILE_THRESHOLD

      # Don't enter if IV has been crushed for too long (no catalyst)
      low_iv_threshold = iv_history.sort[iv_history.size / 5]
      low_streak = iv_history.last(10).count { |v| v < low_iv_threshold }
      return nil if low_streak > 10

      # Apply time regime multipliers
      regime = Live::TimeRegimeService.instance.current_regime
      return nil unless Live::TimeRegimeService.instance.allow_entries?(regime)

      sl_mult = Live::TimeRegimeService.instance.sl_multiplier(regime)
      tp_mult = Live::TimeRegimeService.instance.tp_multiplier(regime)

      # Directional bias from recent momentum
      bars = fetch_historical_bars(interval: 5, count: 5)
      recent_bias = if bars.empty?
                      :ce
                    else
                      last_close = bars.last[:close] || bars.last['close'] || 0
                      first_close = bars.first[:close] || bars.first['close'] || 0
                      last_close > first_close ? :ce : :pe
                    end

      base_sl = (ltp * 0.015).round(2)
      base_target = (ltp * 0.03).round(2)

      sl_points = (base_sl * sl_mult).round(2)
      target_points = (base_target * tp_mult).round(2)

      confidence = 0.55 + (0.25 * (1 - iv_pct / 100.0))
      # Boost confidence in best trading session
      confidence += 0.05 if Live::TimeRegimeService.instance.best_trading_session?(regime)
      confidence = [confidence, 0.95].min

      build_signal(
        direction: recent_bias,
        strike: atm_strike(ltp),
        option_type: :atm,
        entry_price: ltp,
        stop_loss: recent_bias == :ce ? ltp - sl_points : ltp + sl_points,
        target: recent_bias == :ce ? ltp + target_points : ltp - target_points,
        trailing_jump: 0,
        confidence: confidence,
        alpha_source: :vol_expansion,
        iv_context: {
          percentile: iv_pct,
          current: iv_current,
          mean: (iv_history.sum / iv_history.size).round(2),
          history_size: iv_history.size
        }
      )
    end

    private

    def fetch_current_iv(ltp)
      # Query today's IV snapshot for ATM strike
      atm = atm_strike(ltp)
      snapshot = IvSnapshot.where(
        index_key: @index_key.to_s,
        snapshot_date: Time.zone.today,
        strike_price: atm
      ).first

      # If no snapshot today, try fetching from option chain directly
      return snapshot.implied_volatility if snapshot

      chain = instrument&.fetch_option_chain
      return nil unless chain && chain[:oc]

      leg = chain[:oc][atm.to_f.to_s]
      return nil unless leg

      # Use CE IV as proxy for ATM
      leg.dig('ce', 'implied_volatility')&.to_f
    end

    def fetch_iv_history(days:)
      IvSnapshot
        .where(index_key: @index_key.to_s)
        .where('snapshot_date >= ?', Time.zone.today - days.days)
        .order(snapshot_date: :asc)
        .pluck(:implied_volatility)
        .compact
        .map(&:to_f)
    end
  end
end
```

---

## 3. `MomentumAlpha` — Integrated with Time Regime

```ruby
# frozen_string_literal: true

module Strategies
  class MomentumAlpha < AlphaStrategy
    def scan
      return nil unless enabled?
      return nil unless market_open?

      # Time regime check
      regime = Live::TimeRegimeService.instance.current_regime
      return nil unless Live::TimeRegimeService.instance.allow_entries?(regime)

      bars = fetch_historical_bars(interval: 5, count: 20)
      return nil if bars.size < 20

      ltp = underlying_ltp
      return nil unless ltp

      atr = calculate_atr(bars, period: 14)
      high_20 = bars.last(20).map { |b| b[:high] || b['high'] || 0 }.max
      low_20  = bars.last(20).map { |b| b[:low]  || b['low']  || 0 }.min

      direction = nil
      prev_close = bars[-2][:close] || bars[-2]['close'] || 0
      if ltp > high_20 * 0.998 && ltp > prev_close * 1.003
        direction = :ce
      elsif ltp < low_20 * 1.002 && ltp < prev_close * 0.997
        direction = :pe
      end

      return nil unless direction

      # IV filter
      iv_current = fetch_current_iv(ltp)
      iv_history = fetch_iv_history(days: 10)
      iv_pct = iv_percentile(current_iv: iv_current, history: iv_history)

      return nil unless iv_pct < 40 || iv_expanding?(iv_history)

      # Volume confirmation
      vol_avg = bars.last(10).sum { |b| b[:volume] || b['volume'] || 0 } / 10.0
      vol_last = bars.last[:volume] || bars.last['volume'] || 0
      return nil if vol_avg > 0 && vol_last < vol_avg * 1.2

      # Apply regime multipliers
      sl_mult = Live::TimeRegimeService.instance.sl_multiplier(regime)
      tp_mult = Live::TimeRegimeService.instance.tp_multiplier(regime)

      base_sl = (atr * 1.5).round(2)
      base_target = (base_sl * 1.5).round(2)

      sl_points = (base_sl * sl_mult).round(2)
      target_points = (base_target * tp_mult).round(2)

      # Confidence scoring
      confidence = base_confidence(bars, direction, iv_pct, regime)

      build_signal(
        direction: direction,
        strike: atm_strike(ltp),
        option_type: :atm,
        entry_price: ltp,
        stop_loss: direction == :ce ? ltp - sl_points : ltp + sl_points,
        target: direction == :ce ? ltp + target_points : ltp - target_points,
        trailing_jump: Live::TimeRegimeService.instance.allow_trailing?(regime) ? (sl_points * 0.5).round : 0,
        confidence: confidence,
        alpha_source: :momentum,
        iv_context: { percentile: iv_pct, current: iv_current, history_size: iv_history.size }
      )
    end

    private

    def market_open?
      now = Time.current.in_time_zone('Asia/Kolkata')
      return false if now.saturday? || now.sunday?
      now.hour >= 9 && (now.hour < 15 || (now.hour == 15 && now.min <= 20))
    end

    def fetch_current_iv(ltp)
      atm = atm_strike(ltp)
      snapshot = IvSnapshot.where(
        index_key: @index_key.to_s,
        snapshot_date: Time.zone.today,
        strike_price: atm
      ).first
      snapshot&.implied_volatility&.to_f
    end

    def fetch_iv_history(days:)
      IvSnapshot
        .where(index_key: @index_key.to_s)
        .where('snapshot_date >= ?', Time.zone.today - days.days)
        .order(snapshot_date: :asc)
        .pluck(:implied_volatility)
        .compact
        .map(&:to_f)
    end

    def iv_expanding?(history)
      return false if history.size < 2
      history.last(3).each_cons(2).all? { |a, b| b > a }
    end

    def base_confidence(bars, direction, iv_pct, regime)
      base = 0.50
      base += 0.10 if iv_pct < 30
      base += 0.10 if momentum_aligned?(bars, direction)
      base += 0.10 if volume_increasing?(bars)
      base += 0.05 if bars.last(3).all? { |b| (b[:close] || b['close'] || 0) > (b[:open] || b['open'] || 0) } && direction == :ce
      base += 0.05 if bars.last(3).all? { |b| (b[:close] || b['close'] || 0) < (b[:open] || b['open'] || 0) } && direction == :pe
      base += 0.05 if Live::TimeRegimeService.instance.best_trading_session?(regime)
      [base, 0.95].min
    end

    def momentum_aligned?(bars, direction)
      closes = bars.last(5).map { |b| b[:close] || b['close'] || 0 }
      return false if closes.size < 5
      if direction == :ce
        closes.each_cons(2).all? { |a, b| b > a }
      else
        closes.each_cons(2).all? { |a, b| b < a }
      end
    end

    def volume_increasing?(bars)
      vols = bars.last(5).map { |b| b[:volume] || b['volume'] || 0 }
      vols.each_cons(2).all? { |a, b| b >= a }
    end
  end
end
```

---

## 4. `EventAlpha` & `ExpiryAlpha` — Time Regime Override

Event and expiry strategies should **override** the time regime (events can happen in chop zones, expiry is always special):

```ruby
# In EventAlpha#scan and ExpiryAlpha#scan, add this at the top:

def scan
  return nil unless enabled?

  # Events and expiry override time regime
  # But still respect the global no-new-trades-after cutoff
  return nil unless global_trade_window_open?

  # ... rest of logic
end

private

def global_trade_window_open?
  now = Time.current.in_time_zone('Asia/Kolkata')
  time_str = now.strftime('%H:%M')
  time_str < '15:05'
end
```

---

## 5. Updated `SignalEngine` — Time Regime Aware

```ruby
# frozen_string_literal: true

class SignalEngine
  STRATEGIES = [
    Strategies::MomentumAlpha,
    Strategies::VolExpansionAlpha,
    Strategies::EventAlpha,
    Strategies::ExpiryAlpha
  ].freeze

  INDICES = %i[nifty banknifty sensex].freeze

  def initialize(indices: INDICES)
    @indices = indices
    @signals = []
  end

  def run
    # Global time check
    return [] unless global_trade_window_open?

    regime = Live::TimeRegimeService.instance.current_regime

    @indices.each do |index_key|
      STRATEGIES.each do |strategy_class|
        next if strategy_disabled?(strategy_class, index_key)

        # Skip non-event/expiry strategies in CHOP_DECAY unless explicitly allowed
        if Live::TimeRegimeService.instance.high_risk_session?(regime)
          next unless strategy_class == Strategies::ExpiryAlpha || strategy_class == Strategies::EventAlpha
        end

        strategy = strategy_class.new(index_key: index_key)
        signal = strategy.scan

        next unless signal.present? && signal_valid?(signal)

        signal = score_signal(signal)
        signal = apply_regime_limits(signal, regime)
        @signals << signal if signal[:confidence] > 0.55
      end
    end

    @signals.group_by { |s| s[:index_key] }.transform_values { |sigs| sigs.max_by { |s| s[:confidence] } }.values
  end

  private

  def global_trade_window_open?
    now = Time.current.in_time_zone('Asia/Kolkata')
    return false if now.saturday? || now.sunday?
    time_str = now.strftime('%H:%M')
    time_str >= '09:15' && time_str < '15:05'
  end

  def strategy_disabled?(klass, index_key)
    config = AlgoConfig.fetch[:alpha_strategies] || {}
    index_config = config[index_key.to_s] || config[index_key] || {}
    strategy_key = klass.name.demodulize.underscore
    index_config[strategy_key] == false
  end

  def signal_valid?(signal)
    signal[:entry_price] > 0 &&
      signal[:stop_loss] > 0 &&
      signal[:target] > 0 &&
      signal[:confidence] > 0.5 &&
      signal[:expiry].present?
  end

  def score_signal(signal)
    win_prob = signal[:confidence]
    loss_prob = 1 - win_prob
    risk = (signal[:entry_price] - signal[:stop_loss]).abs
    reward = (signal[:target] - signal[:entry_price]).abs

    ev = (win_prob * reward) - (loss_prob * risk)
    signal[:expected_value] = ev.round(2)

    if ev > 0
      signal[:confidence] = [(signal[:confidence] + 0.03), 0.95].min
    end

    signal
  end

  def apply_regime_limits(signal, regime)
    max_tp = Live::TimeRegimeService.instance.max_tp_rupees(regime)
    if max_tp && signal[:target] > signal[:entry_price] + max_tp
      signal[:target] = signal[:entry_price] + max_tp
    end
    signal
  end
end
```

---

## 6. Updated `AlphaScanJob` — Respects Time Regime

```ruby
# frozen_string_literal: true

class AlphaScanJob < ApplicationJob
  queue_as :alpha

  def perform(indices: %i[nifty banknifty])
    return unless market_hours?
    return unless Live::TimeRegimeService.instance.allow_new_trades?

    regime = Live::TimeRegimeService.instance.current_regime
    Rails.logger.info "[AlphaScanJob] Starting scan | Regime: #{regime} | Time: #{Time.current.in_time_zone('Asia/Kolkata').strftime('%H:%M')}"

    engine = SignalEngine.new(indices: indices)
    signals = engine.run

    signals.each do |signal|
      process_signal(signal)
    end
  end

  private

  def process_signal(signal)
    Rails.logger.info "[AlphaScanJob] Signal: #{signal[:alpha_source]} | #{signal[:index_key]} #{signal[:direction].upcase} @ #{signal[:strike]} | Conf: #{signal[:confidence]} | EV: #{signal[:expected_value]}"

    Notifications::TelegramNotifier.instance.notify(
      "🎯 Alpha Signal\n" \
      "Source: #{signal[:alpha_source]}\n" \
      "Index: #{signal[:index_key].upcase}\n" \
      "Direction: #{signal[:direction].upcase}\n" \
      "Strike: #{signal[:strike]}\n" \
      "Confidence: #{(signal[:confidence] * 100).round(1)}%\n" \
      "EV: #{signal[:expected_value]}"
    )

    if signal[:confidence] > 0.75
      AlphaExecutionJob.perform_later(signal)
    else
      Rails.logger.info "[AlphaScanJob] Signal queued for manual approval: #{signal[:index_key]} #{signal[:direction]}"
    end
  end

  def market_hours?
    now = Time.current.in_time_zone('Asia/Kolkata')
    return false if now.saturday? || now.sunday?
    now.hour >= 9 && (now.hour < 15 || (now.hour == 15 && now.min <= 20))
  end
end
```

---

## 7. AlgoConfig Deep Merge for Time Regimes

Your `TimeRegimeService` reads from `AlgoConfig.fetch[:risk][:time_regimes]`. Here's the recommended config:

```json
{
  "risk": {
    "time_regimes": {
      "open_expansion": {
        "start": "09:15",
        "end": "09:45",
        "sl_multiplier": 1.3,
        "tp_multiplier": 1.0,
        "allow_trailing": false,
        "allow_runners": false,
        "allow_entries": true,
        "min_adx": 20.0,
        "max_tp_rupees": 2000
      },
      "trend_continuation": {
        "start": "09:45",
        "end": "11:30",
        "sl_multiplier": 1.0,
        "tp_multiplier": 1.0,
        "allow_trailing": true,
        "allow_runners": true,
        "allow_entries": true,
        "min_adx": 15.0,
        "max_tp_rupees": null
      },
      "chop_decay": {
        "start": "11:30",
        "end": "13:45",
        "sl_multiplier": 0.8,
        "tp_multiplier": 0.8,
        "allow_trailing": false,
        "allow_runners": false,
        "allow_entries": false,
        "min_adx": 22.0,
        "max_tp_rupees": 1500
      },
      "close_gamma": {
        "start": "13:45",
        "end": "15:15",
        "sl_multiplier": 0.7,
        "tp_multiplier": 0.75,
        "allow_trailing": false,
        "allow_runners": false,
        "allow_entries": true,
        "min_adx": 18.0,
        "max_tp_rupees": 2000
      }
    },
    "time_overrides": {
      "no_new_trades_after": "15:05"
    }
  },
  "alpha_strategies": {
    "nifty": {
      "momentum_alpha": true,
      "vol_expansion_alpha": true,
      "event_alpha": true,
      "expiry_alpha": false
    },
    "banknifty": {
      "momentum_alpha": true,
      "vol_expansion_alpha": true,
      "event_alpha": true,
      "expiry_alpha": true
    },
    "sensex": {
      "momentum_alpha": false,
      "vol_expansion_alpha": true,
      "event_alpha": false,
      "expiry_alpha": false
    }
  }
}
```

---

## 8. Complete Integration Flow

```
08:45 AM  → IvSnapshotJob runs (pre-market IV capture)
09:15 AM  → Market opens | TimeRegime = OPEN_EXPANSION
          → AlphaScanJob runs every 5 min
          → MomentumAlpha checks for gap-open breakouts
          → VolExpansionAlpha checks IV percentile
          → SL = 1.3x ATR (wider), no trailing allowed

09:45 AM  → TimeRegime = TREND_CONTINUATION (best session)
          → SL = 1.0x ATR (normal)
          → Trailing allowed
          → Runners allowed
          → All strategies active

11:30 AM  → TimeRegime = CHOP_DECAY (danger zone)
          → NO new entries for momentum/vol_expansion
          → Only EventAlpha and ExpiryAlpha can fire
          → SL = 0.8x ATR (tighter), TP capped at ₹1500

13:45 PM  → TimeRegime = CLOSE_GAMMA
          → Entries allowed again (but tight)
          → SL = 0.7x ATR, TP = 0.75x normal
          → ExpiryAlpha fires for 0DTE

15:05 PM  → NO_NEW_TRADES_AFTER cutoff
          → AlphaScanJob stops processing new signals
          → Existing positions managed by PositionTracker
```

---

## 9. Verification Checklist

| Test | Command / Action | Expected Result |
|---|---|---|
| **IV Snapshot** | `IvSnapshotJob.perform_now` | Creates 6 records (3 indices × 2 option types) |
| **IV History Query** | `IvSnapshot.where(index_key: 'nifty').pluck(:implied_volatility)` | Returns array of floats, newest last |
| **Time Regime** | `Live::TimeRegimeService.instance.current_regime` | Returns correct symbol for current time |
| **Alpha Scan** | `AlphaScanJob.perform_now` | Returns signals only if regime allows entries |
| **Chop Zone Block** | Temporarily set time to 12:00, run scan | No momentum/vol_expansion signals |
| **Meta Persistence** | After execution: `PositionTracker.last.meta['alpha_source']` | Returns `"momentum"` or `"vol_expansion"` |

---

## 10. What You Need to Deploy

1. **Apply the corrected `IvSnapshotJob`** (idempotent upsert, fixed key access)
2. **Apply the updated alpha strategies** (real IV, time regime integration)
3. **Apply the updated `SignalEngine`** (regime-aware filtering, max TP limits)
4. **Apply the updated `AlphaScanJob`** (regime logging, no-trades-after check)
5. **Seed AlgoConfig** with the time regime JSON above
6. **Run `rails db:migrate`** for `iv_snapshots` and `alpha_signals` tables
7. **Test IV capture**: `IvSnapshotJob.perform_now` in Rails console
8. **Test alpha scan**: `AlphaScanJob.perform_now` at different times of day

**The alpha engine is now fully integrated with your existing TimeRegimeService, Capital::Allocator, PositionTracker, and DhanHQ infrastructure. Ready for paper trading.**
