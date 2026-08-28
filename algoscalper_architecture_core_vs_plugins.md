# AlgoScalper API — Core vs. Plugin Architecture Boundary

> **Goal**: Define what's locked in (core engine) vs. what's pluggable (strategies), so that once the core is complete and tested, a user only ever needs to build/activate strategy plugins to trade.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                    FRONTEND (SolidJS)                    │
│         Dashboard, Charts, Controls, Logs               │
│                    (IMMUTABLE CORE)                      │
└────────────────────────┬────────────────────────────────┘
                         │ WebSocket / REST API
┌────────────────────────▼────────────────────────────────┐
│                   RAILS API LAYER                        │
│    Controllers, Channels, Auth, Config Endpoints         │
│                    (IMMUTABLE CORE)                      │
└──────┬─────────┬──────────┬──────────┬─────────┬────────┘
       │         │          │          │         │
┌──────▼──┐ ┌────▼────┐ ┌──▼───┐ ┌───▼───┐ ┌─▼──────┐
│  RISK   │ │  ORDER  │ │POSITION│ │LEDGER │ │RECONCIL│
│  GUARDS │ │MANAGEMENT│ │  MGMT  │ │ (P&L) │ │ SERVICE│
│(CORE)   │ │ (CORE)  │ │(CORE)  │ │(CORE)  │ │ (CORE) │
└──────┬──┘ └────┬────┘ └──┬───┘ └───┬───┘ └─┬──────┘
       │         │          │          │         │
┌──────▼─────────▼──────────▼──────────▼─────────▼──────┐
│              BROKER ABSTRACTION LAYER                    │
│     Order Placement, Fill Tracking, Instruments          │
│              Paper Trading Simulation                     │
│                    (IMMUTABLE CORE)                      │
└────────────────────────┬────────────────────────────────┘
                         │
              ┌──────────▼──────────┐
              │  STRATEGY INTERFACE  │
              │   (PLUGIN BOUNDARY)  │
              └──────────┬──────────┘
                         │
        ┌────────────────┼────────────────┐
        │                │                │
   ┌────▼─────┐   ┌─────▼────┐   ┌─────▼─────┐
   │ Strategy  │   │ Strategy  │   │ Strategy  │
   │ Plugin A  │   │ Plugin B  │   │ Plugin C  │
   │(PLUGGABLE)│   │(PLUGGABLE)│   │(PLUGGABLE)│
   └──────────┘   └──────────┘   └──────────┘
```

The **Strategy Interface** is the contract. Everything above it is core. Everything below it is a plugin.

---

## LAYER 1: IMMUTABLE CORE

### These features are built once, tested, and never touched when adding new strategies.

---

### 1.1 Broker Abstraction

Everything that talks to DhanHQ (or any broker). If you switch brokers in the future, only this layer changes.

| Component | What It Does | Key Files |
|---|---|---|
| **Broker Client** | HTTP client for DhanHQ REST API with retry, timeout, error handling | `app/services/broker/` or `app/services/dhan/` |
| **Order Placement** | Place market/limit/IOC orders, handle partial fills, order slicing | `app/services/orders/placer.rb` |
| **Fill Tracking** | Receive fill confirmations, update order status | `app/services/orders/fill_handler.rb` |
| **Order Status Polling** | Periodically poll broker for order status updates | `app/services/orders/status_poller.rb` |
| **Instrument Registry** | Fetch and cache instrument master (NSE symbols, lot sizes, tick sizes, expiry calendar) | `app/services/instruments/` |
| **Access Token Management** | OAuth token refresh, token storage | `app/services/broker/token_manager.rb` |
| **WebSocket Feed** | Real-time price quotes from broker | Node sidecar or `app/services/broker/price_feed.rb` |

**What never changes**: The API shape — place_order, cancel_order, get_order_status, get_ltp, get_instruments. The strategy never calls DhanHQ directly.

---

### 1.2 Paper Trading Engine

The full simulation layer. Identical behavior to live, just with virtual fills and virtual P&L.

| Component | What It Does | Key Files |
|---|---|---|
| **Paper Order Executor** | Simulates order placement, generates virtual fills at market price + configurable slippage | `app/services/paper/executor.rb` |
| **Slippage Model** | Adds realistic slippage to paper fills (fixed points, percentage, or random) | `app/services/paper/slippage.rb` |
| **Paper Fill Simulator** | Simulates fill timing (instant, delayed, or partial fill behavior) | `app/services/paper/fill_simulator.rb` |
| **Virtual Ledger** | Maintains double-entry bookkeeping for paper trades identical to live ledger | `app/services/ledger/` (shared with live) |
| **Mode Switch** | `paper_trading.enabled: true/false` toggle that routes through paper or live executor | `app/services/trading_mode_router.rb` or equivalent |
| **Paper P&L** | Real-time unrealized/realized P&L calculation using live market prices | `app/services/positions/pnl_calculator.rb` |

**What never changes**: The paper system is a drop-in replacement for the broker. Strategies don't know if they're trading paper or live.

---

### 1.3 Order Lifecycle Management

The complete state machine for every order from creation to final state.

| Component | What It Does | Key Files |
|---|---|---|
| **Order FSM** | State transitions: pending → claimed → placing → placed → partial_fill/filled/rejected/cancelled/expired | `app/services/orders/fsm.rb` (or AASM on Order model) |
| **Client Order ID** | Deterministic SHA256 generation, uniqueness guarantee, claim/release mechanism | `app/services/orders/client_order_id.rb` |
| **Claim/Release** | Prevents duplicate order submissions for the same ID; TTL-based auto-release | `app/services/orders/claim_service.rb` |
| **Order Slicing** | Break large orders into smaller chunks with partial fill handling | `app/services/orders/slicer.rb` |
| **Order Intent** | Persist entry/exit intent BEFORE calling broker (crash safety) | `app/services/orders/intent_persister.rb` |

**What never changes**: The lifecycle states, the claim mechanism, the client order ID scheme.

---

### 1.4 Position Management

Track every open position, its protective orders, and its P&L.

| Component | What It Does | Key Files |
|---|---|---|
| **Position Cache** | Three-layer cache: Redis → ActiveCache (memory) → DB for fast position lookups | `app/services/positions/active_cache.rb` |
| **Position Open/Close** | Create position on fill, close on exit fill, update quantities on partial fills | `app/services/positions/lifecycle.rb` |
| **Protective Order Tracking** | Links SL/TP orders to their parent position | Position model associations |
| **Multi-Leg Tracking** | Track entry + SL + TP as a group (all-or-nothing semantics) | `app/services/positions/multi_leg_manager.rb` |
| **Position Recovery** | On restart, rebuild active positions from DB + broker state | `app/services/positions/recovery_service.rb` |

**What never changes**: Position open/close semantics, cache hierarchy, recovery logic.

---

### 1.5 Risk Management

The multi-layered risk system that prevents catastrophic losses.

| Component | What It Does | Key Files |
|---|---|---|
| **Entry Guard Pipeline** | 30+ pre-trade checks run before any order is placed | `app/services/risk/entry_guard_pipeline.rb` |
| **Daily Loss Limit** | Tracks cumulative daily P&L, blocks trading when limit hit | `app/services/risk/limits_guard.rb` |
| **Max Position Size** | Limits total open quantity per index | `app/services/risk/limits_guard.rb` |
| **Max Trades Per Day** | Limits number of entries per day (global + per-strategy) | `app/services/risk/limits_guard.rb` |
| **Circuit Breaker** | Fail-closed on consecutive losses, Redis down, broker errors | `app/services/risk/circuit_breaker.rb` |
| **Global Loss Limit** | Hard stop on total capital drawdown | `app/services/risk/limits_guard.rb` |
| **Per-Strategy Limits** | Each strategy has its own risk budget (max trades, max loss) | `app/services/risk/limits_guard.rb` |
| **Time-based Guards** | No trading in first/last N minutes of session, no trading during high-volatility events | `app/services/risk/time_guard.rb` |

**What never changes**: The guard pipeline structure, the fail-closed philosophy, the limit types. Only the **values** (max trades = 10, max loss = 5000) change via config.

---

### 1.6 Exit Enforcement System

The multi-layer exit system that ensures positions are always closed properly.

| Component | What It Does | Key Files |
|---|---|---|
| **Hard SL/TP** | Broker-side stop-loss and take-profit orders placed at entry time | `app/services/exits/hard_sl_tp.rb` |
| **Dynamic Trailing Stop** | Moves SL as price moves in favor, with configurable activation distance and trail interval | `app/services/exits/trailing_stop.rb` |
| **Structure Invalidation** | Exits when market structure (SMC) invalidates the trade thesis | `app/services/exits/structure_invalidation.rb` |
| **Premium Decay Exit** | Exits when option premium decays below threshold (theta play) | `app/services/exits/premium_decay.rb` |
| **Time-based Exit** | Exits positions held beyond max holding period | `app/services/exits/time_based_exit.rb` |
| **Expiry Force-Close** | Closes all positions before market close on expiry day | `app/services/positions/expiry_guard.rb` |
| **Global Emergency Exit** | One-button kill switch: closes ALL positions immediately | `app/services/exits/emergency_exit.rb` |
| **Exit Intent Persistence** | Writes exit intent to DB before calling broker (crash safety) | `app/services/ledger/exit_poster.rb` |

**What never changes**: The multi-layer architecture (hard SL always first, then dynamic layers). The kill switch. The persistence-before-action pattern.

---

### 1.7 Ledger & Bookkeeping

The source of truth for all financial records.

| Component | What It Does | Key Files |
|---|---|---|
| **Double-Entry Ledger** | Every trade creates debit + credit entries; ledger always balances | `app/services/ledger/` |
| **Trade History** | Immutable record of every trade with full context | Trade model |
| **Daily P&L** | Realized + unrealized P&L calculated from ledger + live prices | `app/services/positions/pnl_calculator.rb` |
| **Broker Reconciliation** | Periodically compare local state vs broker state, fix discrepancies | `app/services/live/reconciliation_service.rb` |
| **Audit Trail** | Every state change logged with timestamp, actor, reason | `app/services/audit/logger.rb` or model callbacks |

**What never changes**: Double-entry rules, reconciliation logic, audit trail format.

---

### 1.8 Configuration & State Management

| Component | What It Does | Key Files |
|---|---|---|
| **AlgoConfig** | Centralized config loaded from YAML + env vars + DB overrides | `app/services/algo_config.rb` |
| **Feature Flags** | Toggle strategies on/off, enable/disable features without deploy | `app/services/feature_flags.rb` |
| **Runtime Settings API** | Frontend can read/modify non-critical settings via REST API | `app/controllers/api/settings_controller.rb` |
| **Environment Config** | Rails env configs, credentials, Kamal secrets | `config/`, `deploy.yml` |

**What never changes**: The config loading mechanism, the API shape.

---

### 1.9 Real-Time Communication

| Component | What It Does | Key Files |
|---|---|---|
| **WebSocket Channels** | 5+ channels: orders, positions, signals, P&L, system status | `app/channels/` |
| **Price Broadcast** | Streams LTP updates to frontend | Price channel |
| **Order Events** | Streams order state changes (placed, filled, rejected) | Orders channel |
| **Position Events** | Streams position open/close/P&L updates | Positions channel |
| **Signal Events** | Streams generated signals (before execution) | Signals channel |
| **System Events** | Streams alerts, errors, risk limit warnings | System channel |
| **Node Sidecar** | WebSocket bridge for broker price feed | `node-sidecar/` |

**What never changes**: Channel names, event payload schemas, broadcast patterns.

---

### 1.10 Frontend Dashboard (SolidJS)

| Component | What It Does |
|---|---|
| **Trading Dashboard** | Real-time P&L, open positions, today's trades |
| **Order Book** | Live order status with fill progress |
| **Signal Feed** | Streaming signal display with accept/reject |
| **Chart Panel** | Price charts with entry/exit markers, indicators |
| **Risk Monitor** | Daily loss, trades used, circuit breaker status |
| **Settings Panel** | Config editor, strategy toggle, kill switch |
| **Log Viewer** | Real-time log stream with correlation ID filtering |
| **Paper/Live Toggle** | Switch between paper and live mode |
| **Historical P&L** | Daily/weekly/monthly P&L charts |

**What never changes**: The dashboard layout, the chart library, the WebSocket subscription patterns. Strategies add data to the same channels — the frontend renders it the same way.

---

### 1.11 Infrastructure & Deployment

| Component | What It Does |
|---|---|
| **Docker Setup** | Dockerfile for Rails + Node sidecar |
| **Kamal 2 Deployment** | Single-server deploy with zero-downtime |
| **PostgreSQL** | Primary database with migrations |
| **Redis** | Caching, risk limit counters, position cache, claim TTLs |
| **Process Management** | Puma (web) + Sidekiq/Solid Queue (background) + Sidecar (prices) |
| **Log Management** | Structured logging with rotation |
| **Health Checks** | `/up` endpoint for process monitoring |
| **Backup** | Database backup strategy |

**What never changes**: The deployment pipeline, the infrastructure stack.

---

## LAYER 2: PLUGGABLE STRATEGY LAYER

### These are the ONLY things a user needs to create, modify, or swap.

---

### 2.1 Strategy Interface Contract

Every strategy must implement this interface. The core engine calls these methods — it doesn't care what's inside.

```ruby
# app/strategies/base_strategy.rb
module Strategies
  class BaseStrategy
    # ─── IDENTITY ───
    # Unique slug used for config lookups, logging, per-strategy limits
    def slug
      raise NotImplementedError, "#{self.class} must implement #slug"
    end

    # Human-readable name for the frontend
    def display_name
      raise NotImplementedError
    end

    # ─── LIFECYCLE ───
    # Called once when strategy is activated
    def on_activate
      # Optional: warm up caches, validate config, subscribe to feeds
    end

    # Called when strategy is deactivated
    def on_deactivate
      # Optional: clean up resources, cancel pending orders
    end

    # Called every tick (new price update)
    # Returns: Signal or nil
    def on_tick(tick_data)
      raise NotImplementedError, "#{self.class} must implement #on_tick"
    end

    # ─── SIGNAL GENERATION ───
    # The core method. Analyze market data and return a signal or nil.
    #
    # tick_data: {
    #   symbol: "NIFTY",
    #   ltp: 24350.50,
    #   ohlc: { o: 24300, h: 24400, l: 24280, c: 24350 },
    #   volume: 1250000,
    #   timestamp: Time.current,
    #   options_chain: [...],  # if needed
    #   historical_candles: [...],  # if needed
    # }
    #
    # Returns: Signal or nil
    #   Signal: {
    #     direction: :long or :short,
    #     entry_strategy: "smc_momentum",  # must match slug
    #     index: "NIFTY",
    #     option_type: "CE" or "PE",
    #     strike: 24400,
    #     expiry: Date.tomorrow,
    #     lot_size: 25,
    #     quantity: 2,
    #     sl_points: 50,
    #     tp_points: 100,  # optional
    #     conviction: 0.85,  # 0.0-1.0, used by risk guard
    #     metadata: { reason: "Break of structure on 5min", ... }  # freeform, logged
    #   }
    def generate_signal(tick_data)
      raise NotImplementedError
    end

    # ─── DYNAMIC EXIT CONDITIONS ───
    # Called periodically for each open position running this strategy.
    # Returns: :hold, :exit, or { action: :trail_sl, new_sl: 24380 }
    #
    # position: the open Position ActiveRecord object
    # tick_data: current market data
    def evaluate_exit(position, tick_data)
      :hold  # Default: let core exit layers (SL/TP/trailing) handle it
    end

    # ─── OPTIONAL: CUSTOM INDICATORS ───
    # If the strategy needs indicators not in the standard set,
    # compute them here. Called by the core before on_tick.
    def compute_indicators(tick_data)
      tick_data  # Return enriched data (add keys to the hash)
    end

    # ─── OPTIONAL: STRATEGY-SPECIFIC CONFIG ───
    # Define what config keys this strategy needs from algo_config.yml
    def config_schema
      {
        # key_name: { type: :integer, default: 50, min: 10, max: 200, description: "..." },
      }
    end

    # ─── OPTIONAL: VALIDATION ───
    # Called on activation. Return array of error strings or empty array.
    def validate_config
      []
    end
  end
end
```

---

### 2.2 What a Strategy Plugin Contains

A strategy plugin is a **single directory** with a fixed structure:

```
app/strategies/
├── base_strategy.rb              # Interface (IMMUTABLE — part of core)
├── smc_momentum/
│   ├── strategy.rb               # Main strategy class
│   ├── indicators/
│   │   ├── structure_detector.rb # SMC-specific: BOS, CHoCH, swing points
│   │   └── order_block_finder.rb # SMC-specific: bullish/bearish OBs
│   └── config_schema.yml         # Default config values for this strategy
├── premium_decay/
│   ├── strategy.rb
│   ├── indicators/
│   │   ├── theta_calculator.rb   # Options Greeks
│   │   └── iv_rank_calculator.rb # Implied volatility percentile
│   └── config_schema.yml
├── opening_range_breakout/
│   ├── strategy.rb
│   ├── indicators/
│   │   ├── range_calculator.rb   # First N-minute range
│   │   └── volume_filter.rb      # Volume confirmation
│   └── config_schema.yml
└── registry.rb                   # Strategy registry (IMMUTABLE — part of core)
```

---

### 2.3 Strategy Registry (Core — Doesn't Change)

```ruby
# app/strategies/registry.rb
module Strategies
  class Registry
    class << self
      def all
        @strategies ||= {}
      end

      def register(strategy_class)
        instance = strategy_class.new
        all[instance.slug] = { class: strategy_class, instance: instance }
      end

      def get(slug)
        all.dig(slug, :instance)
      end

      def active
        active_slugs = AlgoConfig.fetch.dig(:active_strategies) || []
        all.select { |slug, _| active_slugs.include?(slug) }.values.map { |v| v[:instance] }
      end

      def activate!(slug)
        strategy = get(slug)
        raise "Unknown strategy: #{slug}" unless strategy
        strategy.on_activate
        # Persist activation
        config = AlgoConfig.fetch
        config[:active_strategies] ||= []
        config[:active_strategies] << slug unless config[:active_strategies].include?(slug)
        AlgoConfig.save(config)
      end

      def deactivate!(slug)
        strategy = get(slug)
        strategy&.on_deactivate
        config = AlgoConfig.fetch
        config[:active_strategies]&.delete(slug)
        AlgoConfig.save(config)
      end

      def available
        all.values.map { |v| { slug: v[:instance].slug, name: v[:instance].display_name } }
      end
    end
  end
end
```

---

### 2.4 Strategy Configuration

Per-strategy config lives under the strategy's slug in `algo_config.yml`:

```yaml
# config/algo_config.yml

active_strategies:
  - smc_momentum
  - premium_decay

strategies:
  smc_momentum:
    enabled: true
    conviction_threshold: 0.7        # Minimum conviction to take trade
    lookback_candles: 20
    structure_timeframe: "5min"
    min_risk_reward: 2.0
    max_spread_points: 5

  premium_decay:
    enabled: true
    min_iv_rank: 30                  # Only trade when IV is elevated
    min_days_to_expiry: 1
    max_days_to_expiry: 5
    entry_time: "09:30"              # Don't enter before this time
    exit_time: "15:00"                # Force exit before this time
    max_theta_decay_pct: 30           # Exit when premium decays 30%

  opening_range_breakout:
    enabled: false                   # Disabled but available
    range_minutes: 15
    breakout_buffer_points: 5
    volume_multiplier: 1.5
```

---

### 2.5 Core Signal Router (Plugs Strategies Into Core)

```ruby
# app/services/signal/router.rb  (CORE — doesn't change)
class Signal::Router
  def self.tick(tick_data)
    Strategies::Registry.active.each do |strategy|
      begin
        enriched_data = strategy.compute_indicators(tick_data)
        signal = strategy.generate_signal(enriched_data)

        next unless signal

        # Run through core entry guard pipeline (30+ checks)
        guard_result = Risk::EntryGuardPipeline.run(signal, strategy: strategy)

        unless guard_result.passed?
              Rails.logger.info("[SignalRouter] #{strategy.slug} signal blocked: #{guard_result.reason}")
              next
        end

        # Route to core order placement
        Orders::Placer.place_from_signal(signal)
      rescue StandardError => e
        Rails.logger.error("[SignalRouter] #{strategy.slug} error: #{e.class}: #{e.message}")
        Metrics.increment_error(component: 'signal_router', error_class: e.class.name)
      end
    end
  end

  def self.evaluate_exits(tick_data)
    Position.open.find_each do |pos|
      strategy = Strategies::Registry.get(pos.entry_strategy)
      next unless strategy

      exit_decision = strategy.evaluate_exit(pos, tick_data)

      case exit_decision
      when :exit
        Orders::ExitService.strategy_exit!(pos, reason: "#{strategy.slug} exit condition")
      when Hash
        if exit_decision[:action] == :trail_sl
          Exits::TrailingStop.update!(pos, new_sl: exit_decision[:new_sl])
        end
      when :hold
        # Do nothing — core exit layers (hard SL/TP/time) still apply
      end
    end
  end
end
```

---

### 2.6 Example: Creating a New Strategy Plugin

**Goal**: Add a simple RSI-based mean reversion strategy.

**Step 1**: Create the strategy directory and file.

```ruby
# app/strategies/rsi_mean_reversion/strategy.rb
module Strategies
  module RsiMeanReversion
    class Strategy < BaseStrategy
      def slug
        "rsi_mean_reversion"
      end

      def display_name
        "RSI Mean Reversion"
      end

      def config_schema
        {
          rsi_period: { type: :integer, default: 14, min: 5, max: 50 },
          oversold: { type: :integer, default: 30, min: 10, max: 45 },
          overbought: { type: :integer, default: 70, min: 55, max: 90 },
          lookback: { type: :integer, default: 5, min: 1, max: 20 },
        }
      end

      def generate_signal(tick_data)
        config = strategy_config
        candles = tick_data[:historical_candles]
        return nil unless candles&.length >= config[:rsi_period] + config[:lookback]

        rsi_values = compute_rsi(candles, config[:rsi_period])
        current_rsi = rsi_values.last
        ltp = tick_data[:ltp]

        # CE entry: RSI crosses above oversold
        if rsi_values[-2] < config[:oversold] && current_rsi >= config[:oversold]
          return build_signal(:long, tick_data, reason: "RSI crossed above #{config[:oversold]} (#{current_rsi.round(1)})")
        end

        # PE entry: RSI crosses below overbought
        if rsi_values[-2] > config[:overbought] && current_rsi <= config[:overbought]
          return build_signal(:short, tick_data, reason: "RSI crossed below #{config[:overbought]} (#{current_rsi.round(1)})")
        end

        nil
      end

      def evaluate_exit(position, tick_data)
        config = strategy_config
        candles = tick_data[:historical_candles]
        return :hold unless candles&.length >= config[:rsi_period]

        rsi = compute_rsi(candles, config[:rsi_period]).last

        # Exit long if RSI hits overbought
        if position.direction == "long" && rsi >= config[:overbought]
          return :exit
        end

        # Exit short if RSI hits oversold
        if position.direction == "short" && rsi <= config[:oversold]
          return :exit
        end

        :hold
      end

      private

      def strategy_config
        AlgoConfig.fetch.dig(:strategies, :rsi_mean_reversion) || {}
      end

      def compute_rsi(candles, period)
        # Standard RSI calculation
        # ... implementation ...
      end

      def build_signal(direction, tick_data, reason:)
        # Determine strike, expiry, lot_size from tick_data
        index = tick_data[:symbol]  # e.g. "NIFTY"
        option_type = direction == :long ? "CE" : "PE"
        atm_strike = find_atm_strike(tick_data[:ltp], index)
        expiry = next_weekly_expiry(index)
        lot_size = instrument_registry.lot_size(index)

        Signal.new(
          direction: direction,
          entry_strategy: slug,
          index: index,
          option_type: option_type,
          strike: atm_strike,
          expiry: expiry,
          lot_size: lot_size,
          quantity: 1,
          sl_points: 50,
          conviction: 0.6,
          metadata: { reason: reason }
        )
      end
    end
  end
end
```

**Step 2**: Register the strategy.

```ruby
# In app/strategies/rsi_mean_reversion/strategy.rb (at bottom, outside class):
Strategies::Registry.register(Strategies::RsiMeanReversion::Strategy)
```

Or in an initializer:

```ruby
# config/initializers/strategies.rb
# This file loads and registers all strategies
Dir[Rails.root.join("app/strategies/*/strategy.rb")].each { |f| require f }
```

**Step 3**: Add default config.

```yaml
# config/algo_config.yml — add under strategies:
strategies:
  rsi_mean_reversion:
    enabled: false           # Start disabled
    rsi_period: 14
    oversold: 30
    overbought: 70
    lookback: 5
    max_trades_per_day: 4
    max_daily_loss: 2000
```

**Step 4**: Activate from the frontend or Rails console.

```ruby
# Rails console
Strategies::Registry.activate!("rsi_mean_reversion")

# Or via API
POST /api/v1/strategies/rsi_mean_reversion/activate
```

**That's it.** No core code touched. No restart needed (if using autoload).

---

## CLEAR BOUNDARY SUMMARY

### CORE (Lock It In) — These NEVER change when adding strategies

```
Broker Integration          Paper Trading Engine        Order Lifecycle (FSM)
Position Management        Risk Guard Pipeline          Exit Enforcement Layers
Ledger & Bookkeeping       Reconciliation Service       Configuration System
WebSocket Channels         Frontend Dashboard           Infrastructure & Deployment
Strategy Registry          Signal Router               Entry Guard Pipeline
Claim/Release System       Client Order ID Scheme       Double-Entry Accounting
Emergency Kill Switch      Expiry Force-Close           P&L Calculator
Instrument Registry        Access Token Management      Fill Tracking
```

### PLUGINS (Swap Freely) — These ARE the strategies

```
Signal Generation Logic     Entry Conditions            Exit Conditions (strategy-specific)
Indicator Calculations      Strategy Parameters          Strategy Activation/Deactivation
Strategy-Specific Config    Custom Validation Rules     Strategy Metadata/Reasoning
```

---

## DATA FLOW: Signal → Fill → Exit

```
Market Tick Received
       │
       ▼
Signal::Router.tick(tick_data)              ← CORE (doesn't change)
       │
       ├──► Strategy A.generate_signal()    ← PLUGIN
       ├──► Strategy B.generate_signal()    ← PLUGIN
       └──► Strategy C.generate_signal()    ← PLUGIN
              │
              ▼ (returns Signal or nil)
       Risk::EntryGuardPipeline.run(signal)  ← CORE
              │
              ▼ (passed or blocked)
       Orders::Placer.place_from_signal()    ← CORE
              │
              ▼
       TradingModeRouter.route(order)        ← CORE
              │
         ┌────┴────┐
         ▼         ▼
      LIVE      PAPER                          ← CORE
      (Broker)  (Simulator)
         │         │
         └────┬────┘
              ▼
       Orders::FillHandler.process()         ← CORE
              │
              ▼
       Position.open!()                       ← CORE
       Ledger.record()                         ← CORE
       WebSocket.broadcast(position)           ← CORE
              │
              ▼ (on subsequent ticks)
       Strategy X.evaluate_exit(pos, tick)    ← PLUGIN
              │
              ▼
       Exits::HardSL / TrailingSL / TimeBased ← CORE
              │
              ▼
       Orders::ExitService.exit!(position)   ← CORE
              │
              ▼
       Position.close!()                      ← CORE
       Ledger.record()                         ← CORE
       WebSocket.broadcast(closed)             ← CORE
```

The strategy only appears in TWO places: `generate_signal()` and `evaluate_exit()`. Everything else is core.

---

## CHECKLIST: Core Completeness

Before the core is "locked in," verify every item below works:

### Broker Integration
- [ ] Place market/limit/IOC orders
- [ ] Receive fill confirmations
- [ ] Cancel orders
- [ ] Poll order status
- [ ] Fetch LTP (last traded price)
- [ ] Fetch instrument master
- [ ] Refresh access token
- [ ] WebSocket price feed

### Paper Trading
- [ ] Paper executor simulates fills at LTP + slippage
- [ ] Paper fills go through same ledger as live
- [ ] Paper P&L matches manual calculation
- [ ] Mode switch (paper/live) works without restart

### Order Management
- [ ] Client order ID generation is deterministic and unique
- [ ] Claim/release prevents duplicate orders
- [ ] Claim auto-releases on timeout
- [ ] Order FSM covers all states
- [ ] Multi-leg atomicity (entry + SL + TP)
- [ ] Order slicing for large quantities

### Position Management
- [ ] Three-layer cache (Redis → memory → DB)
- [ ] Position opens on fill, closes on exit fill
- [ ] Protective orders linked to positions
- [ ] Recovery on process restart

### Risk Management
- [ ] Entry guard pipeline runs all checks
- [ ] Daily loss limit enforced
- [ ] Max position size enforced
- [ ] Max trades per day enforced
- [ ] Per-strategy limits enforced
- [ ] Circuit breaker triggers on consecutive losses
- [ ] Time-based guards block trading in first/last minutes

### Exit Enforcement
- [ ] Hard SL placed at entry
- [ ] Hard TP placed at entry
- [ ] Trailing stop activates and trails
- [ ] Time-based exit for stale positions
- [ ] Expiry force-close
- [ ] Emergency kill switch closes everything
- [ ] Exit intent persisted before broker call

### Ledger
- [ ] Double-entry bookkeeping balances
- [ ] Every trade has immutable audit trail
- [ ] Daily P&L is accurate
- [ ] Broker reconciliation finds and fixes discrepancies

### Infrastructure
- [ ] Optimistic locking on orders/positions/strategies
- [ ] Auto-correlation IDs in all log lines
- [ ] Health check endpoint
- [ ] Graceful shutdown (no orphaned orders)
- [ ] Log rotation
- [ ] Database backups

### Strategy Plugin System
- [ ] Base strategy interface defined
- [ ] Registry loads and lists all strategies
- [ ] Activate/deactivate without restart
- [ ] Signal router calls active strategies
- [ ] Exit evaluator calls strategy for open positions
- [ ] Per-strategy config loaded from algo_config.yml
- [ ] Frontend shows available/active strategies
- [ ] New strategy can be added by creating one file + adding config

---

## WHAT "LOCKED IN" MEANS PRACTICALLY

1. **Core tests pass at 100%** — every core service has comprehensive tests
2. **Paper trading validated** — 5+ trading days with zero critical errors
3. **Core is on its own branch** — `main` is the locked core, strategies are developed on feature branches
4. **Strategy interface is documented** — `BaseStrategy` is the contract, any deviation is a core change
5. **Core changes require a migration plan** — if the interface changes, all existing strategies must be updated
6. **No strategy logic in core files** — if you find SMC-specific code in `orders/placer.rb`, it's in the wrong place