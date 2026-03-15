---
name: event_driven_architecture
description: Maintain clean event-driven boundaries in the trading daemon's service architecture
tags: [trading, events, websocket, services, architecture]
applies_to: [services, live]
severity: [major, critical]
---

## Goal

The trading daemon is event-driven at its core — market ticks arrive via
WebSocket and propagate through a pipeline of services. Understanding and
preserving the event flow is critical to correctness and debuggability.

## Canonical Event Flow

```
DhanHQ WebSocket (tick)
  → MarketFeedHub.on_tick(tick)
    → Live::TickCache.put(tick)          [memory + Redis cache]
    → PnlUpdaterService                  [250ms flush cycle]
      → EventBus.publish(:ltp, tick)     [debug only]
      → RiskManagerService               [direct method call]
        → UnifiedExitChecker.evaluate    [per-position check]
          → ExitEngine.execute_exit      [if condition met]

Separate 5s enforcement loop (RiskManagerService):
  → checks all active positions for exit conditions
  → calls ExitEngine.execute_exit for any triggered condition
```

**Key architectural rule:** In this codebase, services communicate via
**direct method calls**, not the EventBus. The EventBus exists but has only
a debug subscriber — do not treat it as the active communication layer.

## Service Responsibilities

| Service | Trigger | Responsibility |
|---------|---------|----------------|
| `MarketFeedHub` | WebSocket tick | Route ticks to cache and subscribers |
| `TickCache` | Per-tick | Write-through memory + Redis |
| `PnlUpdaterService` | 250ms timer | Flush PnL to Redis; notify risk manager |
| `RiskManagerService` | 5s loop + EventBus | Enforce exit conditions |
| `UnifiedExitChecker` | Per-position call | Evaluate all exit rules in priority order |
| `ExitEngine` | On exit trigger | Single authority for exit order placement |
| `TrailingEngine` | On exit trigger | Update trailing stop state only |
| `ReconciliationService` | 30s timer | Sync broker state with DB |

## Clean Event Handler Pattern

```ruby
# Good — tick handler: cache only, no heavy work
module Live
  class MarketFeedHub
    def on_tick(tick)
      return unless valid_tick?(tick)
      Live::TickCache.put(tick)
      update_market_cache(tick)
      # PnlUpdaterService runs on its own 250ms timer — not called here
    end

    private

    def valid_tick?(tick)
      tick[:ltp].to_f.positive? || tick[:prev_close].to_f.positive?
    end
  end
end
```

## Anti-patterns

### ❌ Placing orders in a tick handler

```ruby
def on_tick(tick)
  if tick[:ltp] < stop_loss
    gateway.place_exit(tracker)  # WRONG — blocks tick processing, non-idempotent
  end
end
```

### ❌ Database write in tick handler

```ruby
def on_tick(tick)
  PositionTracker.find_by(security_id: tick[:security_id])
                 .update!(ltp: tick[:ltp])  # WRONG — blocks on DB, misses ticks
end
```

### ❌ Bypassing ExitEngine

```ruby
# In RiskManagerService — WRONG
def enforce_exit(tracker)
  gateway.place_market(side: :sell, ...)  # direct gateway call, not through ExitEngine
end

# Correct
def enforce_exit(tracker)
  exit_engine.execute_exit(tracker, reason: 'risk_limit_hit')
end
```

### ❌ Polling instead of subscribing

```ruby
# WRONG — busy polling in a loop
loop do
  ltp = fetch_ltp_from_api   # HTTP call per loop — terrible
  check_exits(ltp)
  sleep 0.1
end

# Correct — subscribe to tick cache, let the feed push data
Live::MarketFeedHub.instance.subscribe(security_id, method(:on_tick))
```

## Thread Safety Rules

The trading daemon runs 11 services in concurrent threads. All shared state
must be protected:

```ruby
# Thread-safe tick cache read
ltp = Live::TickQuery.ltp(security_id)  # use TickQuery, not TickCache directly

# Thread-safe position index
tracker = Live::PositionIndex.instance.find_by_security_id(security_id)
```

## Detection Rules

Flag when:
- A tick handler calls `ActiveRecord` directly
- A tick handler places an order
- A service polls an API instead of subscribing to the feed
- `ExitEngine.execute_exit` is bypassed and gateway is called directly
- `Capital::Allocator` is bypassed and sizing is done inline
- A service modifies `TickCache` data it didn't produce

## Agent Instructions

1. For any code that handles ticks, verify it only writes to TickCache or calls
   stateless helpers — no DB writes, no order placement.
2. For any exit logic, verify it calls `ExitEngine.execute_exit` and doesn't
   place orders directly.
3. Verify polling loops are replaced by WebSocket subscriptions where possible.
4. Check that shared singleton state has mutex protection.
