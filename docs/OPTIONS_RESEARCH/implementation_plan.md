To build a robust, institutional-grade naked index options buying application using the DhanHQ v2 API, you must strategically separate your data requests. Naked option buying is highly sensitive to **slippage, timing, and volatility**. Therefore, you cannot rely on a single data feed; you need a hybrid architecture that uses REST APIs for broad market context (the "Brain") and WebSockets for micro-second execution and order book analysis (the "Nervous System").

Here is the exact blueprint of the Data REST APIs and WebSocket connections you must implement in your Ruby application.

---

### 1. REST APIs: For Strategy Context & Universe Definition

REST APIs should be used for bulk data retrieval, historical analysis, and periodic polling. They are too slow for real-time execution but are essential for setting up your daily trading parameters.

#### A. Option Chain API (`/v2/optionchain`)

* **Purpose:** The core engine for identifying "Gamma Walls" and filtering by Implied Volatility (IV).
* **How to use for Naked Buying:**
  * Fetch the chain for Nifty, Bank Nifty, or Sensex at market open (9:15 AM) and at key intervals.
  * Extract **Open Interest (OI)** to identify massive strike concentrations (Gamma Walls). *Rule: Avoid buying naked options directly into a massive Call/Put OI wall unless betting on a specific breakout.*
  * Extract **Implied Volatility (IV)** and **Greeks (Delta, Theta, Vega)**. Use IV Percentile to ensure you aren't overpaying for premium when VIX is artificially high.

#### B. Expiry List API (`/v2/optionchain/expirylist`)

* **Purpose:** To dynamically fetch the available expiry dates for a given underlying.
* **How to use for Naked Buying:** Crucial for your "Theta-Aware Positioning" rule. Your algorithm will use this to programmatically select the furthest monthly expiry (e.g., 30-45 days out) to minimize theta decay, avoiding the deadly 0DTE/1DTE weekly expiries.

#### C. Historical Data API (`/v2/charts/historical`)

* **Purpose:** Fetching historical OHLC (Open, High, Low, Close) data for the underlying indices.
* **How to use for Naked Buying:**
  * **Backtesting:** Validate your catalyst-based entry logic (e.g., "Buy Nifty Call when RSI crosses 30 on 15min chart AND India VIX > 15").
  * **Indicator Calculation:** Calculate moving averages, ATR (Average True Range) for dynamic stop-losses, and historical volatility benchmarks.

#### D. Instrument Master API (`/v2/instruments`)

* **Purpose:** Download the master CSV of all tradable instruments.
* **How to use for Naked Buying:** You must map the human-readable option symbol (e.g., `NIFTY 23 NOV 20000 CE`) to the DhanHQ `security_id` (token). Your WebSocket client requires these exact `security_id`s to subscribe to live feeds.

---

### 2. WebSocket Connections: For Real-Time Execution & Slippage Management

The DhanHQ Live Market Feed via WebSocket is where your actual trading logic lives. For naked buying, **execution quality is everything**. A bad fill due to wide bid-ask spreads can ruin the risk-reward ratio instantly.

#### A. Underlying Index & India VIX Streaming (Context Triggers)

* **Instruments to Subscribe:** Nifty 50, Bank Nifty, Sensex, and **India VIX** (Security ID for VIX is usually available in the master CSV).
* **Subscription Mode:** **Compact Quote** (LTP, OHLC, Volume).
* **Purpose:**
  * Monitor the spot price to calculate real-time moneyness (ATM/ITM/OTM).
  * **India VIX Monitoring:** If your strategy dictates "Do not buy options if VIX is dropping rapidly," the WebSocket provides the real-time VIX ticks to act as a hard filter, preventing entries during volatility crushes.

#### B. Target Option Contract Streaming (Execution & Slippage)

* **Instruments to Subscribe:** *Only* the specific 1 or 2 option strikes your strategy has identified for the day (e.g., Nifty 22500 CE). **Do not subscribe to the whole option chain via WebSocket.**
* **Subscription Mode:** **Full Market Depth (20-Level)**.
* **Purpose:** This is the most critical connection for a naked option buyer.
  * **Slippage Avoidance:** By analyzing the 20-level bid-ask spread, your Ruby app can calculate the exact liquidity available at the best bid/ask. If the spread is too wide (e.g., Bid 100 / Ask 110), the app can halt the limit order or adjust the price to avoid getting trapped.
  * **Order Book Imbalance:** Analyze the depth to see if there are massive sell orders stacked above the current price (resistance) or buy orders below (support).

#### C. Portfolio & Order Status Streaming (Optional but Recommended)

* **Purpose:** While DhanHQ provides REST endpoints for order history, streaming your own order updates ensures your app instantly knows when a limit order is filled, partially filled, or rejected, allowing the risk management module to react immediately.

---

### 3. Architectural Data Flow in your Ruby App

To make this work seamlessly using the `dhanhq-client` gem, structure your Ruby application's data flow like this:

1. **Initialization (08:30 AM - 09:15 AM):**
    * *REST:* Call `/v2/instruments` to load the token map into memory.
    * *REST:* Call `/v2/optionchain/expirylist` to determine the target monthly expiry.
    * *REST:* Call `/v2/charts/historical` to update technical indicators for the underlying index.
2. **Market Open & Context Building (09:15 AM - 09:20 AM):**
    * *REST:* Call `/v2/optionchain` to map out Open Interest (Gamma Walls) and IV.
    * *Logic:* The strategy engine processes this data and selects the exact `security_id` of the target option (e.g., an ITM call with favorable Delta and low IV).
3. **Live Trading Loop (09:20 AM onwards):**
    * *WebSocket:* Connect to `DhanHQ::WS`.
    * *WebSocket:* Subscribe to **Underlying Index** (Compact Quote) + **India VIX** (Compact Quote) + **Target Option** (Full Market Depth).
    * *Logic:* The app monitors the Index for the technical trigger. Once triggered, it checks the VIX. If VIX is stable/rising, it checks the Option's Full Market Depth. If the bid-ask spread is tight (e.g., < 0.5% of premium), it sends a LIMIT order via the REST Order API.
4. **Risk Management (Continuous):**
    * *WebSocket:* Continuously monitors the Full Market Depth of the open position. If the bid drops below your automated stop-loss level, it immediately triggers an exit order.

### Summary Checklist for your `dhanhq-client` Implementation

| Feature                    | DhanHQ v2 Component                 | Ruby Implementation Focus                                           |
| :------------------------- | :---------------------------------- | :------------------------------------------------------------------ |
| **Token Mapping**          | `/v2/instruments` (REST)            | Parse CSV, build a Hash map: `Symbol -> security_id`                |
| **Gamma Wall / IV Filter** | `/v2/optionchain` (REST)            | Poll at 9:15 AM. Extract `oi`, `iv`, `greeks` for strike selection. |
| **Expiry Selection**       | `/v2/optionchain/expirylist` (REST) | Select furthest expiry to minimize Theta decay.                     |
| **Spot & VIX Triggers**    | Live Market Feed (WebSocket)        | Subscribe to Index & VIX using **Quote Mode**.                      |
| **Slippage & Execution**   | Live Market Feed (WebSocket)        | Subscribe to Target Option using **Full Depth Mode (20-level)**.    |
| **Backtesting**            | `/v2/charts/historical` (REST)      | Fetch 1-min/5-min candles for underlying to test entry logic.       |

By strictly separating the heavy, broad data (REST Option Chain) from the lightweight, hyper-specific execution data (WebSocket Full Depth), your Ruby application will remain highly responsive, minimize API rate-limit hits, and execute naked option buys with institutional precision.

For a naked index options buying system, **you should absolutely NOT subscribe to ATM (At-The-Money) strikes continuously.**

Subscribing to all ATM strikes or keeping a broad watchlist active all day is a retail trap. It wastes system resources, risks hitting WebSocket rate limits, and most importantly, ATM strikes move as the underlying index moves. Chasing a moving ATM strike via dynamic subscriptions will introduce fatal latency into your execution.

Instead, your system must use an **Event-Driven "Sniper" Architecture**. You only subscribe to the specific option strike's Full Market Depth at the exact moment your strategy identifies a potential trade, and you unsubscribe the moment the trade is closed.

Here is the exact institutional-grade workflow for managing your WebSocket subscriptions in your Ruby app.

---

### The "Sniper" Subscription Workflow

#### Phase 1: The Radar (Always Subscribed)

* **What to subscribe:** The Underlying Index (Nifty/BankNifty/Sensex) and India VIX.
* **Mode:** Compact Quote (LTP, OHLC, Volume).
* **Why:** You need continuous, low-latency awareness of the spot price to calculate technical triggers and monitor the volatility environment. This requires very little bandwidth and should run from 09:15 AM to 03:30 PM.

#### Phase 2: Target Lock (Trigger-Based Subscription)

* **Trigger:** Your strategy logic (running on the Index/VIX data) identifies a setup. For example, BankNifty crosses a key moving average, and VIX is stable.
* **Action:** The system calculates the *exact* strike it wants to trade (e.g., 1 strike ITM Call). It extracts the `security_id` for that specific strike from your pre-loaded Instrument Master.
* **WebSocket Command:** Send a `subscribe` request to the DhanHQ WebSocket for that **single** `security_id` in **Full Market Depth (20-level)** mode.
* **Why not ATM?** You don't just blindly buy the ATM. You might want a slightly ITM strike for a higher Delta (e.g., 0.60) to mimic futures, or a specific strike identified by your REST Option Chain analysis as having favorable Open Interest dynamics. You subscribe to the *target*, not the theoretical ATM.

#### Phase 3: The Slippage Check (Pre-Entry Analysis)

* **Action:** Once subscribed to the Full Market Depth, **do not place the order immediately.** Wait for 1 to 3 seconds of tick data.
* **Logic:** Analyze the 20-level bid-ask spread.
  * *Is the spread tight?* (e.g., Bid 150.00 / Ask 150.50). -> **Proceed to execute.**
  * *Is the spread wide/illiquid?* (e.g., Bid 145.00 / Ask 155.00). -> **Abort or adjust limit price.**
* **Why this is critical for Naked Buyers:** Naked option buying is highly susceptible to slippage. If you use market orders or blindly send limit orders without checking the live order book depth, market makers will run you over. This 2-second depth check is your primary defense against bad fills.

#### Phase 4: Active Monitoring (Position Management)

* **Action:** The order is placed and filled. The WebSocket subscription to this specific `security_id` remains **active**.
* **Logic:** The Ruby app now uses the real-time LTP and Market Depth to manage the trade. It monitors for your automated trailing stop-loss, checks if the bid liquidity is drying up (a sign to exit early), or watches for the take-profit target to be hit.

#### Phase 5: Clean Up (Unsubscribe on Exit)

* **Trigger:** The position is squared off (via SL, Target, or Time-based exit).
* **Action:** Immediately send an `unsubscribe` request to the WebSocket for that `security_id`.
* **Why:** Free up the WebSocket channel. If you leave dead subscriptions active, your connection will eventually become bloated with irrelevant tick data, causing memory leaks in your Ruby process and increasing latency for your active trades.

---

### Summary of Subscription States

| System State                | Underlying Index (Nifty/BankNifty) | India VIX            | Target Option Strike (e.g., Nifty 22500 CE) |
| :-------------------------- | :--------------------------------- | :------------------- | :------------------------------------------ |
| **Pre-Market / Idle**       | Subscribed (Compact)               | Subscribed (Compact) | **Unsubscribed**                            |
| **Scanning / Waiting**      | Subscribed (Compact)               | Subscribed (Compact) | **Unsubscribed**                            |
| **Trigger Hit / Pre-Entry** | Subscribed (Compact)               | Subscribed (Compact) | **Subscribed (Full Depth)**                 |
| **Position Open**           | Subscribed (Compact)               | Subscribed (Compact) | **Subscribed (Full Depth)**                 |
| **Position Closed**         | Subscribed (Compact)               | Subscribed (Compact) | **Unsubscribed**                            |

### Ruby Implementation Tip (`dhanhq-client`)

In your Ruby code using the `dhanhq-client` gem, your WebSocket event loop should look conceptually like this:

```ruby
# Inside your WebSocket message handler
ws.on_message do |message|
  parsed_data = DhanHQ::WS.parse(message)

  if parsed_data.is_index_or_vix?
    strategy_engine.evaluate_trigger(parsed_data)

    if strategy_engine.trigger_hit?
      target_security_id = strategy_engine.get_target_strike_id

      # DYNAMIC SUBSCRIPTION: Only subscribe when ready to trade
      ws.subscribe([target_security_id], subscription_type: 'FullDepth')
      state_machine.transition_to(:pre_entry_analysis)
    end

  elsif parsed_data.security_id == current_open_position_id
    # Manage active position using Full Depth data
    risk_manager.check_trailing_stop(parsed_data)
    risk_manager.check_take_profit(parsed_data)

    if risk_manager.exit_triggered?
      execution_engine.place_exit_order(current_open_position_id)

      # DYNAMIC UNSUBSCRIPTION: Clean up immediately after exit
      ws.unsubscribe([current_open_position_id])
      state_machine.transition_to(:idle)
    end
  end
end
```

### The Bottom Line

Treat your WebSocket subscriptions like ammunition. **Do not spray and pray.** Keep your radar (Index/VIX) on at all times, but only load the weapon (subscribe to Full Depth) when you have a clear target, check the wind (analyze the spread), take the shot (execute), and holster the weapon (unsubscribe) the moment the trade is over. This is how institutional algorithms manage latency and ensure high-quality fills in naked option buying.

# Institutional Entry Strategies for Naked Index Options Buying

For naked option buying, your entry is everything. Unlike option selling where you can afford to be "roughly right" and let theta work in your favor, naked buying demands **precision timing**. A mediocre entry in a good direction can still lose money due to theta decay and IV crush. Therefore, every entry strategy must satisfy three criteria: (1) a clear catalyst for directional movement, (2) a defined market regime where it works, and (3) a programmable trigger that removes discretion.

Below are the battle-tested, automatable entry strategies used by professional prop desks for naked index option buying on Nifty, Bank Nifty, and Sensex.

---

## Category 1: Momentum & Breakout Strategies

*Best for: Trending markets, post-consolidation phases*

### Strategy 1: Opening Range Breakout (ORB)

The most classic, time-based, and programmable strategy for index options.

**Logic:** The first 15-30 minutes of the market establish a range. A decisive breakout from this range with volume often leads to a trending move for the rest of the session.

**Entry Rules (Programmable):**

```
1. Wait for 09:15 - 09:30 (15-min ORB) or 09:15 - 09:45 (30-min ORB)
2. Mark the High and Low of this range
3. Entry Trigger: Index closes a 5-min candle ABOVE the ORB High (for CE) or BELOW the ORB Low (for PE)
4. Confirmation: Breakout candle volume > 1.5x average volume of range candles
5. VIX Filter: India VIX must be > 12 (avoid dead markets)
```

**Strike Selection:** 1 strike ITM (Delta ~0.60) for momentum capture, or ATM (Delta ~0.50) for balanced risk-reward.

**Best Regime:** Trending days, days with news catalysts. **Avoid:** Range-bound days where VIX is < 11.

---

### Strategy 2: Volatility Contraction Pattern (VCP) / Inside Bar Breakout

Institutional favorite for catching explosive moves after consolidation.

**Logic:** After a period of tight consolidation (low volatility), the market "coils" like a spring. The breakout from this compression leads to an expansion move.

**Entry Rules:**

```
1. Identify a 5-min or 15-min Inside Bar (current bar's high < previous bar's high AND low > previous bar's low)
2. OR: Bollinger Band Width contracts to lowest level in last 20 bars
3. Entry Trigger: Price breaks the inside bar's high (CE) or low (PE)
4. Confirmation: ATR(14) on 15-min chart is at 20-period low
5. OI Filter: Massive Put OI buildup below (for CE) or Call OI buildup above (for PE)
```

**Strike Selection:** ATM or slightly ITM. Avoid OTM — the initial move from VCP is often sharp but needs delta to capture it fully.

**Best Regime:** Mid-day consolidations (11:00 AM - 1:30 PM), post-event lulls.

---

## Category 2: Volatility Regime Strategies

*Best for: Capturing volatility expansion from compressed states*

### Strategy 3: VIX Mean Reversion Expansion

A pure volatility-based strategy that exploits the cyclical nature of India VIX.

**Logic:** VIX tends to revert to its mean. When VIX hits extreme lows and starts expanding, it signals the beginning of a directional move in the underlying.

**Entry Rules:**

```
1. Calculate VIX 20-day percentile (current VIX vs last 20 days)
2. Condition: VIX percentile was < 20 for at least 3 consecutive days (compressed)
3. Entry Trigger: VIX rises > 5% intraday AND crosses above its 5-day MA
4. Direction: Use ADX(14) on daily chart of index — if +DI > -DI, buy CE; else buy PE
5. Time Filter: Only enter before 01:00 PM (avoid late-day IV crush)
```

**Strike Selection:** ATM or 1 strike ITM. This is a regime-change trade; you need delta to benefit from the directional move that accompanies VIX expansion.

**Best Regime:** Extended low-volatility periods (VIX < 12 for weeks).

---

### Strategy 4: IV Percentile + Directional Confluence

Combines options-specific metrics with underlying price action.

**Logic:** Buy options only when they are "cheap" relative to their own history AND the underlying shows directional conviction.

**Entry Rules:**

```
1. Fetch IV Percentile of the target option (via /v2/optionchain REST API)
2. Condition: IV Percentile < 30 (options are cheap)
3. Directional Trigger: Index breaks 20-EMA on 15-min chart with rising volume
4. OI Confirmation: Change in OI supports the direction (Put writing for bullish, Call writing for bearish)
5. Avoid: If IV Percentile > 70 (options are expensive, IV crush risk is high)
```

**Strike Selection:** ITM (Delta 0.65-0.70). When IV is low, ITM options have lower vega risk and higher delta, giving you better risk-reward.

**Best Regime:** Low VIX environments where options are underpriced.

---

## Category 3: Multi-Timeframe Trend Strategies

*Best for: Trading with the dominant trend, buying pullbacks*

### Strategy 5: Triple Timeframe Alignment (Trend Pullback)

The highest probability strategy for naked buying — trading only in the direction of higher timeframe momentum.

**Logic:** When daily, hourly, and 15-min trends align, pullbacks on the 15-min chart become high-probability entry points.

**Entry Rules:**

```
1. Daily Trend: Index above 50-DMA AND 20-EMA > 50-EMA (bullish)
2. Hourly Trend: 20-EMA sloping upward, price above 20-EMA
3. 15-min Setup: Price pulls back to 20-EMA or VWAP
4. Entry Trigger: Bullish reversal candle (hammer, engulfing) at the 20-EMA/VWAP
5. Confirmation: RSI(14) on 15-min between 40-60 during pullback (not oversold — that signals weakness)
```

**Strike Selection:** 1-2 strikes ITM (Delta 0.65-0.75). In strong trends, ITM options behave like futures with less theta decay impact.

**Best Regime:** Strong trending markets (ADX > 25 on daily).

---

### Strategy 6: VWAP + Volume Profile Confluence

Institutional benchmark-based strategy using volume-weighted metrics.

**Logic:** VWAP is the institutional fair value. Price returning to VWAP after a trend represents a "value zone" where institutions reload positions.

**Entry Rules:**

```
1. Identify strong morning trend (09:15 - 10:30) with price away from VWAP
2. Wait for pullback to VWAP (or VWAP standard deviation bands)
3. Entry Trigger: Price touches VWAP AND prints a reversal candle with volume spike
4. Volume Profile: Entry zone must coincide with High Volume Node (HVN) from previous day
5. Time Filter: Valid only till 02:00 PM (VWAP becomes less reliable late day)
```

**Strike Selection:** ATM for balanced delta/theta tradeoff.

**Best Regime:** Trending days with clean pullbacks. **Avoid:** Choppy sideways days.

---

## Category 4: Event & Time-Based Strategies

*Best for: Capturing scheduled volatility events*

### Strategy 7: Post-Event Momentum Continuation

For RBI policy days, Budget days, US Fed announcement impacts.

**Logic:** Major events create an initial volatility spike. The first 30 minutes after the event often establishes the directional tone for the day.

**Entry Rules:**

```
1. Event Calendar: RBI policy (bi-monthly), Union Budget (Feb 1), US Fed (overnight impact)
2. Wait for initial 30-min volatility to settle post-event
3. Mark the 30-min range post-announcement
4. Entry Trigger: Breakout of this range with OI confirmation (massive option writing on one side)
5. VIX Check: VIX must have expanded > 10% from previous close
```

**Strike Selection:** ATM or slightly ITM. Avoid OTM — post-event moves are sharp but can reverse quickly.

**Best Regime:** Event days only. **Never** trade this on normal days.

---

### Strategy 8: 2:00 PM European Session Momentum

Time-based strategy exploiting the European market open impact on Indian indices.

**Logic:** European markets open around 01:30-02:00 PM IST. Their directional bias often triggers a second wave of momentum in Indian indices.

**Entry Rules:**

```
1. Time Window: 01:45 PM - 02:30 PM only
2. Condition: Indian index has established a clear trend in the first half
3. Trigger: Index breaks the day's High (for CE) or Low (for PE) after 01:45 PM
4. Confirmation: European indices (DAX, FTSE) moving in same direction
5. Exit Rule: Strict time-based exit at 03:00 PM regardless of P&L
```

**Strike Selection:** ATM. Late-day entries need quick delta response.

**Best Regime:** Trending days where morning momentum continues.

---

## Strategy Comparison Matrix

| Strategy                      | Win Rate | Avg R:R | Best Market Regime      | Theta Sensitivity | Automation Complexity |
| :---------------------------- | :------- | :------ | :---------------------- | :---------------- | :-------------------- |
| **ORB (15/30 min)**           | 40-45%   | 1:2.5   | Trending days           | Medium            | Low                   |
| **VCP / Inside Bar**          | 35-40%   | 1:3     | Post-consolidation      | High              | Medium                |
| **VIX Expansion**             | 45-50%   | 1:2     | Low VIX → Expansion     | Low               | Medium                |
| **IV Percentile + Direction** | 40-45%   | 1:2.5   | Low IV environment      | Low               | High                  |
| **Triple TF Alignment**       | 50-55%   | 1:2     | Strong trends           | Low               | High                  |
| **VWAP Pullback**             | 45-50%   | 1:2     | Trending with pullbacks | Medium            | Medium                |
| **Post-Event Momentum**       | 40-45%   | 1:3     | Event days only         | High              | Medium                |
| **European Session**          | 35-40%   | 1:2     | Trend continuation      | Very High         | Low                   |

---

## The Golden Rules for Entry Strategy Selection

Regardless of which strategy you automate, these rules are non-negotiable for naked option buying survival:

1. **Never enter without a VIX filter.** If India VIX is < 12 and falling, do not buy options — theta will eat you alive.
2. **Never enter after 02:30 PM** unless it's a specific late-day momentum strategy with a hard time exit.
3. **Always prefer ITM over OTM.** OTM options are lottery tickets; ITM options are directional instruments.
4. **Require confluence.** A single indicator trigger is not enough. Every entry needs 2-3 confirming signals (price action + volume + OI + VIX).
5. **Regime detection first.** Your Ruby app should classify the market regime (trending/ranging/volatile) before selecting which strategy to deploy.

---

## Ruby Implementation Blueprint

For your `dhanhq-client` based system, structure your strategy engine like this:

```ruby
class StrategyEngine
  STRATEGIES = {
    trending:      [TripleTimeframeAlignment, VWAPPullback, ORB],
    ranging:       [VCPBreakout],
    low_vix:       [VIXExpansion, IVPercentileConfluence],
    event_day:     [PostEventMomentum],
    late_day:      [EuropeanSessionMomentum]
  }

  def evaluate(market_state)
    regime = detect_regime(market_state)  # Uses VIX, ADX, ATR
    applicable_strategies = STRATEGIES[regime]

    applicable_strategies.each do |strategy|
      signal = strategy.check_entry(market_state)
      return signal if signal.valid?
    end

    Signal::NO_TRADE  # Default to no trade if nothing qualifies
  end

  private

  def detect_regime(state)
    return :event_day if state.event_calendar.active?
    return :low_vix if state.vix.percentile < 30
    return :trending if state.adx_15min > 25
    return :late_day if state.time > Time.parse("13:45")
    :ranging
  end
end
```

### The Bottom Line

The best naked option buying strategy is the one you **don't** trade every day. Institutional prop desks typically deploy only 2-3 of these strategies and wait patiently for their specific conditions. Your Ruby automation's greatest edge is its ability to **not trade** when conditions don't match — something retail traders cannot do emotionally. Build the regime detector first, then layer the entry strategies on top. Survival comes from selectivity, not frequency.
