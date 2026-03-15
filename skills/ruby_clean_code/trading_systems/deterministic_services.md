---
name: deterministic_services
description: Ensure trading services produce predictable, reproducible outcomes with no hidden state
tags: [trading, determinism, reliability, testing]
applies_to: [services, strategies, signal]
severity: [major, critical]
---

## Goal

Trading logic must be **deterministic**: given the same inputs, produce the
same output every time. Hidden state, non-deterministic execution order, and
side effects during decision-making create bugs that are nearly impossible to
reproduce and dangerous in a live trading system.

## Principles

### 1. Pure Decision Engines

Signal generation and exit rule evaluation must be **pure functions**:
- Input: market data, indicators, config
- Output: signal or exit decision
- No side effects: no DB writes, no order placement, no WebSocket subscriptions

```ruby
# Pure — testable, deterministic
module Signal
  class Engine
    def self.run_for(index_cfg, market_data:, config:)
      indicators = compute_indicators(market_data)
      regime     = detect_regime(indicators)
      build_signal(indicators, regime, config)  # returns Signal VO, nothing else
    end
  end
end
```

### 2. Explicit State, No Hidden State

All state that affects decisions must be explicitly passed in or loaded from
a deterministic source (DB, config). Never rely on:
- Class variables (`@@trades_today` mutated from multiple threads)
- Global variables
- `Time.current` inside decision logic (inject clock)
- Random without seed

```ruby
# Bad — hidden state in class variable
class DailyLimits
  @@loss_today = 0  # mutated by multiple threads — non-deterministic!
end

# Good — load from authoritative source each time
class DailyLimits
  def daily_loss
    PositionTracker.exited.opened_today.sum(:realised_pnl)
  end
end
```

### 3. Separate Decision from Execution

The decision to act and the act of executing must be in separate classes:

```
Decision layer: Signal::Engine, ExitRule, RiskPolicy
              → produces a decision object (Signal, ExitDecision)

Execution layer: EntryGuard, ExitEngine, Orders::Gateway
              → consumes the decision and takes action
```

No execution in the decision layer. No decision logic in the execution layer.

### 4. Idempotent Execution

An order placement, exit, or position update must be safe to retry:

```ruby
# Bad — calling twice places two orders
def place_entry(instrument, qty)
  gateway.place_market(side: :buy, qty: qty)
end

# Good — idempotent via client order ID deduplication
def place_entry(instrument, qty)
  coid = build_client_order_id(instrument)
  return if already_submitted?(coid)
  gateway.place_market(side: :buy, qty: qty, client_order_id: coid)
end
```

### 5. No Side Effects in Tick Handlers

WebSocket tick handlers are called hundreds of times per second. They must:
- **Never** write to the database directly
- **Never** place orders
- **Only** update in-memory/Redis caches
- **Enqueue** jobs for any heavy work

```ruby
# Bad — DB write in tick handler (blocks tick processing)
def on_tick(tick)
  PositionTracker.find(tick[:security_id]).update!(ltp: tick[:ltp])
end

# Good — write-through cache, async flush
def on_tick(tick)
  Live::TickCache.put(tick)  # memory + Redis
  # PnlUpdaterService flushes to DB every 30s
end
```

## Detection Rules

Flag when:
- A decision method (returns a signal/bool) also writes to DB or places an order
- Class variables (`@@`) are mutated during signal generation
- `Time.current` used inside a pure calculation (makes it non-deterministic for tests)
- A tick handler calls `ActiveRecord` directly
- Order placement is outside `Orders::Gateway`
- Exit placement is outside `ExitEngine`

## Testing Determinism

A deterministic service can be tested without stubs:

```ruby
# Deterministic — pure inputs, no mocking needed
result = Signal::Engine.run_for(index_cfg, market_data: fixture_data, config: test_config)
expect(result.direction).to eq(:bullish)
expect(result.confidence).to be >= 0.65
```

## Agent Instructions

1. Check each service method — does it read from global/class state?
2. Does the decision method also execute (place orders, write DB)?
3. Are tick handlers free of `ActiveRecord` calls?
4. Is the service testable with pure inputs and no mocks?
