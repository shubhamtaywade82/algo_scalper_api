# Options Buying Automation: Master Integration Plan

This document serves as the single source of truth for integrating the **Options Buying Framework (Big Bull Series Ep-92)** into the Rails-based `algo_scalper_api` platform. It synthesizes the core trading rules, technical constraints, gap analysis, and implementation blueprints into a cohesive upgrade roadmap.

---

## 1. TL;DR & Core Principles

* **Do Not Naked Buy Options Overnight:** Naked options buying subjects you to brutal time decay (theta) and catastrophic unhedged gap-down risks.
* **Convert to Spreads:** Mitigation lies in using vertical spreads (e.g., buying an ATM/In-The-Money Call and selling an Out-of-the-Money Call) to cap maximum losses and dramatically lower the break-even point.
* **Dual Confirmation Framework:** Never trade based on a single chart or data point. Concurrently combine technical analysis structures (like RSI divergences) with live Options Chain data (Open Interest shifts) to identify true institutional support and resistance levels.
* **Strict Capital Allocation Rules:** Treat options buying like a business, meaning you plan your maximum risk per trade to allow at least 30 to 50 failed trades sequentially before account wipeout. Stop averaging down losing options positions immediately.

---

## 2. Phase-by-Phase Trading & Risk Rules

### Phase 1: Mindset & Capital Preservation Rules
* **The Reality Check:** Treat initial capital allocation strictly as a business expense. Do not expect to replace a full-time income immediately with tiny capital.
* **Risk Capital Baseline:** Begin total options trading capital exclusively with an amount equivalent to one month's salary.
* **Quantified Capital Allocation:** Limit risk to 2%–3% of total capital per trade (e.g., ₹2,000–₹3,000 per trade on a ₹1,00,000 base) to survive a 33 to 50 wrong-trade sequence.
* **Zero Averaging Policy:** Never average down a losing options buying position. Exit immediately if your stop-loss or trade invalidation trigger is hit.

### Phase 2: Dual Confirmation Setup Strategy (Data + Charts)
* **Chart Structure (Momentum Divergence):** Look for RSI Divergences (e.g., index making a higher high but RSI making a lower high) as an early warning of trend exhaustion.
* **Data Validation (Open Interest & Option Chain Analytics):** 
  * Identify Call strike with highest OI (Resistance) and Put strike with highest OI (Support).
  * Look for Near-The-Money (ATM) high-OI congestion representing a consolidation zone.
* **Execution Trigger:** Do not buy immediately at support or resistance. Wait for the Spot Price to cross and sustainably trade above that high-OI strike level for **15–20 minutes (roughly 3 to 4 consecutive 5-minute candles)** to trigger short covering by trapped sellers.

### Phase 3: The Vertical Spread Execution Architecture
To trade safely over a multi-day holding period, convert naked positions into **Vertical Spreads**:
* **Bull Call Spread Setup:** 
  1. Buy an At-The-Money (ATM) Call (e.g., Strike 205 at ₹8.95).
  2. Simultaneously Sell a Higher Out-Of-The-Money (OTM) Call (e.g., Strike 210 at ₹6.40).
* **Mathematics at Expiration (Lot size 1,650):**
  * **Net Premium Outflow (Max Risk):** $8.95 - 6.40 = 2.55 \text{ points}$ (₹4,207.50 max risk instead of naked ₹14,767.50).
  * **Net Profit capped at:** $2.45 \text{ points}$ (₹4,042.50) if market expires at Strike 220+.

### Phase 4: Risk Management & Trade Operations
* **Risk-Reward Ratio:** Reject setups offering less than a $1:2$ structural risk-to-reward ratio.
* **Using ATR:** Skip breakout option buys if the index has already moved $> 80\%$ of its 14-day Average True Range (ATR) by mid-day.
* **Expiration Day Operations:** 
  * Avoid entering fresh options buying positions past **2:30 PM** on contract expiration day.
  * Liquidate active spread positions once they capture **70% to 80% of their maximum profit potential**.

---

## 3. Codebase Integration Plan

### System Architecture Flow
```
+---------------------------------------------------------------------------------+
|                       Data Ingestion & Filtering Layer                          |
|  - Fetch Daily Backtest / Pre-Market Data                                      |
|  - Validate Daily ATR Thresholds (Skip if Index > 80% ATR Moved)               |
|  - Scan for RSI Divergence Structures                                           |
+---------------------------------------------------------------------------------+
                                        |
                                        v
+---------------------------------------------------------------------------------+
|                        Live Validation (WebSocket)                             |
|  - Stream :full Mode Data for Underlying Index + Near-The-Money Call/Put strikes|
|  - Track High-OI Strike Breakout Sustained for 15-20 Mins                      |
+---------------------------------------------------------------------------------+
                                        |
                                        v
+---------------------------------------------------------------------------------+
|                         Execution & Spread Orchestration                        |
|  - Atomically Route Orders (Simultaneous Multi-Leg Spreads)                      |
|  - Deploy Trailing Position Guards & Exit Safely at 70-80% Max Profit Target   |
+---------------------------------------------------------------------------------+
```

### Gap Analysis & Core Code Updates

#### Step 1: Implement the 9:30 AM Entry Filter
* **Code Modification:** Update `app/services/live/time_regime_service.rb` to block entries before `09:30 AM` in the `allow_new_trades?` logic.

#### Step 2: Incorporate the ATR Constraint
* **Implementation Blueprint:** Create a new entry guard `Guards::AtrExhaustionGuard` inside `app/services/entries/guards/` using `TechnicalAnalysis::Atr`:
  ```ruby
  module Entries
    module Guards
      class AtrExhaustionGuard
        class << self
          def call(context)
            # Fetch daily candles & determine volatility limits
            daily_bars = DhanHQ::Models::HistoricalData.intraday(
              security_id: context[:index_cfg][:sid],
              exchange_segment: "IDX_I",
              instrument: "INDEX",
              interval: "1D",
              from_date: (Date.today - 20).strftime("%Y-%m-%d"),
              to_date: Date.today.strftime("%Y-%m-%d")
            )
            return EntryGuardPipeline::PASS if daily_bars.empty?

            atr = TechnicalAnalysis::Atr.calculate(daily_bars, period: 14)
            today_range = daily_bars.last[:high] - daily_bars.last[:low]

            if today_range > (atr * 0.8)
              return { blocked: "Index has moved more than 80% of daily ATR" }
            end

            EntryGuardPipeline::PASS
          end
        end
      end
    end
  end
  ```

#### Step 3: Stream and Track Open Interest (OI)
* Modify the existing `Live::MarketFeedHub` WebSocket client to subscribe in `:full` mode.
* Parse incoming tick payloads for the `:oi` key and update the Redis state cache (`TickCache`).
* Enqueue an evaluation job via **Solid Queue**:
  ```ruby
  Execution::BreakoutCheckJob.perform_later(security_id)
  ```

#### Step 4: Multi-Leg Spread Order Construction
* Extend `Orders::Placer` to execute spreads transactionally using `DhanHQ::Models::Order.create`:
  ```ruby
  module Execution
    class SpreadOrchestrator
      def self.deploy_bull_call_spread(atm_strike_id, otm_strike_id, qty)
        raise "Safety Violation: Live execution restricted" unless ENV['LIVE_TRADING'] == 'true'

        ActiveRecord::Base.transaction do
          long_leg = DhanHQ::Models::Order.create(
            transaction_type: "BUY",
            exchange_segment: "NSE_FNO",
            security_id: atm_strike_id,
            quantity: qty,
            order_type: "MARKET",
            product_type: "MARGIN"
          )
          
          short_leg = DhanHQ::Models::Order.create(
            transaction_type: "SELL",
            exchange_segment: "NSE_FNO",
            security_id: otm_strike_id,
            quantity: qty,
            order_type: "MARKET",
            product_type: "MARGIN"
          )
        end
      end
    end
  end
  ```

---

## 4. Failure Modes & Mitigations
* **Leg Slippage:** Place spread legs inside transactional execution blocks or utilize DhanHQ basket orders to minimize delay.
* **Data Disconnection:** Track breakout timing counters inside shared Redis stores instead of in-memory instance variables to preserve state across reconnects.
* **Expiry Liquidity / Decay:** Hard-stop fresh buying entries after 1:00 PM on expiration days. Auto-exit spreads early once they capture $\ge 75\%$ of maximum profit.
