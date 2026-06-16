# Options Buying Automation: Ep-92 Framework Implementation Plan

This document maps the **Options Buying Framework (Big Bull Series Ep-92)** against the current architecture of `algo_scalper_api`. It performs a gap analysis and provides a plan for implementing missing elements.

---

## 1. Summary of Framework Alignment

The existing codebase is highly aligned with the principles of Ep-92. Here is a breakdown of how the framework's core pillars map to current services:

| Ep-92 Principle | Codebase Implementation Status | Component / File |
| :--- | :--- | :--- |
| **"Three Mirrors" Rule** (Multi-confirmations) | **Implemented** | [Entries::EntryGuardPipeline](file:///home/nemesis/project/trading-workspace/algo_scalper_api/app/services/entries/entry_guard_pipeline.rb) enforces 20 sequential checks across price, regime, and risk. |
| **The 9:30 AM Rule** (Avoid market-open noise) | **Partially Implemented** | [Live::TimeRegimeService](file:///home/nemesis/project/trading-workspace/algo_scalper_api/app/services/live/time_regime_service.rb) groups 09:15–09:45 as `OPEN_EXPANSION`. It currently allows entries but applies higher SL multipliers (1.3x). |
| **Option Chain & Seller's Eyes** (OI analysis) | **Implemented** | [Options::ChainAnalyzer](file:///home/nemesis/project/trading-workspace/algo_scalper_api/app/services/options/chain_analyzer.rb) reads live option chains and filters strikes based on minimum Open Interest (OI) and bid-ask spreads. |
| **Short-Covering Momentum** (Sustaining levels) | **Under Construction** | The system uses `expiry_week_power_trend` for breakout zones but doesn't explicitly track a 20–30 minute hold above major seller OI walls. |
| **Momentum Indicators** (RSI divergence) | **Implemented** | `momentum_buying` strategy in [config/algo.yml](file:///home/nemesis/project/trading-workspace/algo_scalper_api/config/algo.yml) checks for RSI levels (`min_rsi: 60`). |
| **Spreads instead of Naked Buys** (Theta hedge) | **Missing / Planned** | The system currently executes naked directional long calls (`CE`) or puts (`PE`) via `Orders::Placer`. Spreads (e.g., Bull Call, Bear Put) are not currently default execution structures. |
| **Averaging Down is Forbidden** | **Fully Enforced** | The system has **no mechanism** to average down on losing trades. Stop-losses are strict and absolute, managed by [Live::RiskManagerService](file:///home/nemesis/project/trading-workspace/algo_scalper_api/app/services/live/risk_manager_service.rb). |
| **Strict R:R (SL = 0.5 * Target)** | **Supported** | Can be configured directly via per-index risk profiles in [config/algo.yml](file:///home/nemesis/project/trading-workspace/algo_scalper_api/config/algo.yml). |

---

## 2. Actionable Implementation Steps

### Step 1: Implement the Hard 9:30 AM Entry Filter
To fully implement the 9:30 AM rule (avoiding the first 15 minutes of market opening noise):
* **Configuration:** Under `time_regimes` in `config/algo.yml`, adjust the `open_expansion` regime to start at `09:30` instead of `09:15` for entries, or set `allow_entries: false` between `09:15-09:30`.
* **Code Modification:** In `app/services/live/time_regime_service.rb`, we can enforce a block on new entries until `09:30 AM` by checking the current time in `allow_new_trades?`:
  ```ruby
  # Add to app/services/live/time_regime_service.rb
  def allow_new_trades?(time: nil)
    time ||= current_ist_time
    time_str = time.strftime('%H:%M')
    
    # Hard gate: block all entries before 09:30 AM
    return false if time_str < '09:30'
    # ... rest of validation
  end
  ```

### Step 2: Implement Short-Covering Squeeze Triggers (OI Walls)
To ride the institutional short-covering momentum, we can create a dedicated strategy or guard that:
1. Identifies the strike with the highest Open Interest (Call OI for resistance, Put OI for support) using `Options::ChainAnalyzer`.
2. Monitors if the underlying spot price crosses and holds past this strike for **at least 20 minutes** (tracked in a Redis key).
3. Triggers a high-conviction breakout entry when the sellers are confirmed to be in squeeze territory.

### Step 3: Implement Spread Execution Mode (Theta Mitigation)
Rather than executing single options contracts, add a configuration `execution_type: :spread` in `config/algo.yml`.
* **Placer Update (`app/services/orders/placer.rb`):** When executing a signal (e.g., bullish), instead of a single CE buy, place a **Bull Call Spread** (Buy ATM call + Sell OTM call) to protect against theta decay and decrease overall margin/premium costs.

### Step 4: Configure Stop-Loss to half the Target distance
Adjust `risk_model` parameters in `config/algo.yml` to lock in a strict 1:2 Risk-to-Reward ratio:
* Ensure default stop loss is half the target (e.g., if targeting a 30% premium gain, set the stop-loss strictly at 15%).
* Confirm this in [app/services/live/risk_manager_service.rb](file:///home/nemesis/project/trading-workspace/algo_scalper_api/app/services/live/risk_manager_service.rb) checks.

---

## 3. Recommended Config Updates (`config/algo.yml`)
Add or verify these settings in your configuration file to match the Ep-92 framework:

```yaml
# Strict R:R configuration & time restrictions
risk:
  time_regimes:
    enabled: true
    open_expansion:
      start: "09:30"        # Hard-block entries before 09:30 AM
      end: "09:45"
      allow_entries: true   # Only allow entries after 9:30 AM
      sl_multiplier: 1.0    # 1:2 standard R:R
      tp_multiplier: 2.0    # TP is twice the SL distance

# Strategy tweaks for momentum
indices:
  - key: NIFTY
    strategies:
      momentum_buying:
        enabled: true
        min_rsi: 60          # Confirms strong momentum before buying options
```

---

## 4. System Architecture & Implementation Blueprints

### TL;DR

* **Map Video Logic to Code:** Convert the structural concepts from the video (RSI divergence, High-OI breakout triggers, and multi-leg Spreads) into highly opinionated, deterministic automated steps.
* **Leverage Native Tools:** Utilize raw **DhanHQ Client Gem** configurations for real-time WebSocket data feeds (`:full` mode for live Open Interest tracking) and order pipelines.
* **Enforce Execution Guardrails:** Pass criteria to execution workflows via an asynchronous engine (Solid Queue) to implement structural filters like ATR thresholds and 15-minute confirmation candles before deployment.

---

### Step-by-Step Architecture for an Automated System

To turn this specific options buying framework into a production-grade algorithmic engine using your infrastructure stack, the video logic maps directly into three distinct layers.

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

---

### Implementation Blueprints

#### 1. Data Filtering: Daily ATR and Technical Constraints

Before processing intraday entry signals, apply the structural filters discussed in the video. If the underlying asset has already exhausted its standard volatility range for the day, the entry should be flagged as low-probability and aborted.

```ruby
module Trading
  class MarketConditionFilter
    def self.valid_for_entry?(security_id, current_ltp)
      # Fetch recent daily bars to compute technical indicators
      daily_bars = DhanHQ::Models::HistoricalData.intraday(
        security_id: security_id,
        exchange_segment: "IDX_I",
        instrument: "INDEX",
        interval: "1D",
        from_date: (Date.today - 20).strftime("%Y-%m-%d"),
        to_date: Date.today.strftime("%Y-%m-%d")
      )
      
      return false if daily_bars.empty?

      # Calculate ATR (Average True Range) and Daily High/Low boundaries
      # Note: class name casing matches TechnicalAnalysis::Atr (capital A, lowercase tr)
      atr = TechnicalAnalysis::Atr.calculate(daily_bars, period: 14)
      today_open = daily_bars.last[:open]
      today_high = daily_bars.last[:high]
      today_low  = daily_bars.last[:low]
      
      total_range_moved = today_high - today_low

      # Video Guardrail: Avoid buying long options if index has exhausted over 80% of its ATR
      return false if total_range_moved > (atr * 0.8)
      true
    end
  end
end
```

#### 2. Live Validation: High-OI Breakout Monitor

Instead of trading charts blindly, the system parses live options market data using raw WebSockets. To track institutional boundaries effectively, use the `:full` subscription mode to receive real-time Open Interest (`oi`) data updates. Note that in a production setup, rather than spawning a script-level global client connection, you should hook these subscribers directly into the existing `Live::MarketFeedHub` singleton.

```ruby
# Initialize a resilient market feed configured for live depth and open interest tracking
$ws = DhanHQ::WS::Client.new(mode: :full).start

# Array of target FNO Option strike security IDs derived dynamically from the Option Chain
TARGET_FNO_STRIKES = ["43492", "43493"] 

$ws.on(:tick) do |tick|
  next unless TARGET_FNO_STRIKES.include?(tick[:security_id])
  
  # Cache updates atomically in Redis for swift timeframe tracking
  TickCache.put(tick[:security_id], {
    ltp: tick[:ltp],
    oi: tick[:oi],
    timestamp: tick[:ts]
  })
  
  # Trigger Solid Queue Job to evaluate if price breaks out and stays above the high-OI cluster for 15+ minutes
  Execution::BreakoutCheckJob.perform_later(tick[:security_id])
end

# Register tracking parameters for targeted contracts
TARGET_FNO_STRIKES.each do |id|
  $ws.subscribe_one(exchange_segment: "NSE_FNO", security_id: id)
end
```

#### 3. Execution: Multi-Leg Spread Order Construction

To prevent unhedged directional exposure and mitigate time-decay hazards, avoid naked call purchases. Group the buying of an At-The-Money (ATM) contract and the selling of a higher Out-Of-The-Money (OTM) contract into a single transactional block to build a structured vertical spread.

```ruby
module Execution
  class SpreadOrchestrator
    def self.deploy_bull_call_spread(atm_strike_id, otm_strike_id, qty)
      # Execution Safety: Ensure live trading constraints are strictly enforced via the SDK
      raise "Safety Violation: Live execution restricted" unless ENV['LIVE_TRADING'] == 'true'

      ActiveRecord::Base.transaction do
        # Leg 1: Purchase the ATM Call option to establish long target delta
        long_leg = DhanHQ::Models::Order.new(
          transaction_type: "BUY",
          exchange_segment: "NSE_FNO",
          product_type: "MARGIN",
          order_type: "MARKET",
          security_id: atm_strike_id,
          quantity: qty
        )
        
        # Leg 2: Sell the further OTM Call contract to capture premium offsetting theta decay
        short_leg = DhanHQ::Models::Order.new(
          transaction_type: "SELL",
          exchange_segment: "NSE_FNO",
          product_type: "MARGIN",
          order_type: "MARKET",
          security_id: otm_strike_id,
          quantity: qty
        )

        # Fire order calls back-to-back to minimize execution slippage
        long_leg.save
        short_leg.save
        
        # Log structure footprints inside internal order management databases
        SpreadAuditLog.create!(
          long_order_id: long_leg.id, 
          short_order_id: short_leg.id, 
          status: "DEPLOYED"
        )
      end
    end
  end
end
```

---

### Critical System Failure Modes & Mitigation Strategies

* **Leg Slippage During Spread Execution:**
  * *Failure:* A market order places Leg 1, but the underlying asset moves instantly before Leg 2 fires, skewing the entry profile.
  * *Mitigation:* Fire executions concurrently via asynchronous worker loops or use a specialized basket order configuration to push transactions as closely together as possible.
* **Data Disconnection During the 15-Minute Validation Window:**
  * *Failure:* A localized hardware or internet hiccup drops your WebSocket connection, clearing out candle sequence validation counts mid-breakout.
  * *Mitigation:* Ensure state monitoring scripts pull directly from persistent distributed caches (like Redis) rather than keeping counters in volatile application memory. Build automated fallback reconnection mechanisms with progressive exponential backoff loops directly into your platform initializers.
* **OI Distortion Near Daily Contract Expirations:**
  * *Failure:* Fast-moving open interest liquidations between 1:00 PM and 2:30 PM on expiry day spark erratic algorithmic false entries.
  * *Mitigation:* Hardcode a strict system lockout rule that prevents entry initialization after 1:00 PM on the expiration day of the contract series. Ensure active trades close out systematically when position evaluations reflect $\ge 75\%$ of the spread's total maximum potential profitability.
