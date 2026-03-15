---
name: trading_strategy_clean_code
description: Ensure trading strategies are pure signal engines, never order executors
tags: [trading, strategy, signals, design]
applies_to: [strategies, signal, services]
severity: [major, critical]
---

## Goal

A trading strategy is a **pure decision engine**. Its sole responsibility is
to analyse market data and produce a signal. It never places orders, never
manages positions, and never has side effects.

## The Strategy Contract

```
Input:  market data (OHLCV, indicators, regime, config)
Output: Signal value object (direction, confidence, metadata)
        OR nil/Signal::None if no signal
```

No broker calls. No DB writes. No position tracking. No notifications.

## Layer Architecture

```
Market Data (WebSocket + Historical API)
      ↓
Indicators (Supertrend, ADX, RSI, MACD)
      ↓
Strategy / Signal Engine  ← PURE
      ↓
Signal (value object)
      ↓
EntryGuard (validates + executes)  ← SIDE EFFECTS HERE
      ↓
Orders::Gateway (broker)
      ↓
PositionTracker (DB record)
```

## Signal Value Object

```ruby
# Immutable signal produced by strategy
Signal = Data.define(:direction, :confidence, :regime, :adx, :supertrend,
                     :index_key, :timestamp) do
  def actionable?
    confidence >= MIN_CONFIDENCE &&
      %i[bullish bearish].include?(direction) &&
      !stale?
  end

  def bullish?  = direction == :bullish
  def bearish?  = direction == :bearish
  def stale?    = Time.current - timestamp > SIGNAL_TTL

  MIN_CONFIDENCE = 0.65
  SIGNAL_TTL     = 45.seconds
end
```

## Clean Strategy Implementation

```ruby
module Signal
  class Engine
    class << self
      def run_for(index_cfg)
        series    = load_candle_series(index_cfg)
        return nil unless series&.sufficient_data?

        indicators = compute_indicators(series)
        regime     = MarketRegimeDetector.new(series).detect
        direction  = determine_direction(indicators, regime)
        confidence = compute_confidence(indicators, regime)

        return nil unless direction && confidence >= Signal::MIN_CONFIDENCE

        Signal.new(
          direction:  direction,
          confidence: confidence,
          regime:     regime[:regime],
          adx:        indicators[:adx],
          supertrend: indicators[:supertrend],
          index_key:  index_cfg[:key],
          timestamp:  Time.current
        )
      end

      private

      def compute_indicators(series)
        {
          adx:        series.adx(14).to_f,
          rsi:        series.rsi(14).to_f,
          supertrend: series.supertrend_signal
        }
      end

      def determine_direction(indicators, regime)
        return nil unless regime[:regime].start_with?('TRENDING')
        indicators[:supertrend] == :bullish ? :bullish : :bearish
      end

      def compute_confidence(indicators, regime)
        score = 0.0
        score += 0.4 if indicators[:adx] > 25
        score += 0.3 if indicators[:rsi].between?(30, 70)
        score += 0.3 if regime[:confidence] > 70
        score
      end
    end
  end
end
```

## Anti-Patterns

### ❌ Strategy places order directly

```ruby
class SupertrendStrategy
  def run(index_cfg)
    signal = compute_signal(index_cfg)
    if signal.bullish?
      Orders::GatewayLive.new.place_market(...)  # WRONG — strategy must not execute
    end
  end
end
```

### ❌ Strategy modifies shared state

```ruby
class SignalEngine
  def run_for(index_cfg)
    signals_cfg = AlgoConfig.fetch[:signals]
    signals_cfg[:validation_mode] = 'conservative'  # WRONG — mutates shared config
    ...
  end
end
```

### ❌ Strategy queries the database

```ruby
class SignalEngine
  def run_for(index_cfg)
    recent_positions = PositionTracker.active.for_index(index_cfg[:key])
    return nil if recent_positions.count >= 2  # WRONG — DB call in signal engine
  end
end
```

The entry guard (not the strategy) should check position limits.

### ❌ Strategy has side effects for "logging"

```ruby
class SignalEngine
  def run_for(index_cfg)
    signal = compute_signal
    Signal::StateTracker.record(index_cfg[:key], signal)  # side effect — OK only if non-DB
    SlackNotifier.notify(signal)                           # WRONG — notification in strategy
    signal
  end
end
```

## Detection Rules

Flag when a strategy/signal engine:
- Calls `Orders::Gateway`, `gateway.place_market`, or any broker method
- Calls `ActiveRecord` methods (reads OR writes) inside signal computation
- Sends notifications (Telegram, Slack, email)
- Modifies a shared config object
- Returns something other than a Signal value object or nil

## Agent Instructions

1. Identify the strategy/signal class entry point.
2. Trace all method calls from `run`/`call`/`run_for`.
3. Flag any call that reaches the broker, DB, or notification layer.
4. Verify the return type is a Signal VO or nil.
5. Suggest moving prohibited logic to `EntryGuard` (execution) or a job (notification).
