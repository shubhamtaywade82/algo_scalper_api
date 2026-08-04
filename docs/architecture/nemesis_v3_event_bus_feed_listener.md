# NEMESIS V3: EventBus & FeedListener Implementation

## Overview

This document describes the foundational components of NEMESIS V3 architecture: `Core::EventBus` and `Live::FeedListener`. These components provide the event-driven infrastructure for the trading system.

## Components

### 1. Core::EventBus

**Location**: `app/services/core/event_bus.rb`

**Purpose**: Central pub/sub event bus for internal system communication.

**Features**:
- Thread-safe singleton using `Concurrent::Map` and `Concurrent::Array`
- Supports multiple subscribers per event type
- Subscription management (subscribe/unsubscribe)
- Error handling (subscriber errors don't crash the bus)
- Statistics tracking (events published, delivered, errors)

**Event Types**:
```ruby
:ltp              # Last traded price update
:entry_filled     # Entry order filled
:sl_hit           # Stop loss hit
:tp_hit           # Take profit hit
:structure_break  # Structure break detected
:exit_triggered  # Exit triggered
:risk_alert       # Risk alert
:breakeven_lock   # Breakeven lock activated
:trailing_triggered # Trailing stop triggered
:danger_zone      # Danger zone entered
:volatility_spike # Volatility spike detected
:trend_flip       # Trend flip detected
```

**Usage**:
```ruby
# Subscribe to LTP events
subscription_id = Core::EventBus.instance.subscribe(:ltp) do |event|
  # event is a Live::LtpEvent
  puts "LTP: #{event.ltp} for #{event.composite_key}"
end

# Publish an event
Core::EventBus.instance.publish(:ltp, ltp_event)

# Unsubscribe
Core::EventBus.instance.unsubscribe(subscription_id)

# Get statistics
stats = Core::EventBus.instance.stats
# => { events_published: 1234, events_delivered: 1230, errors: 4 }
```

### 2. Live::LtpEvent

**Location**: `app/services/live/ltp_event.rb`

**Purpose**: Structured event data for LTP updates.

**Attributes**:
- `segment` - Exchange segment (e.g., "NSE_FNO", "IDX_I")
- `security_id` - Security ID
- `ltp` - Last traded price
- `timestamp` - Event timestamp
- `spot_price` - Underlying spot price (for derivatives)
- `volatility_state` - :low, :normal, :high, or :extreme
- `bid`, `ask` - Bid/ask prices
- `oi`, `oi_change` - Open interest data
- `volume` - Volume
- `high`, `low`, `open`, `close` - OHLC data

**Methods**:
- `composite_key` - Returns "SEGMENT:SECURITY_ID" for caching
- `valid?` - Checks if event has valid LTP
- `to_h` - Converts to hash
- `spread_pct` - Calculates bid-ask spread percentage
- `price_change_pct` - Calculates price change from previous close

**Usage**:
```ruby
event = Live::LtpEvent.new(
  segment: 'NSE_FNO',
  security_id: '49081',
  ltp: 150.5,
  bid: 150.0,
  ask: 151.0,
  oi: 500000,
  volatility_state: :normal
)

event.composite_key  # => "NSE_FNO:49081"
event.spread_pct     # => 0.66 (0.66% spread)
event.valid?         # => true
```

### 3. Live::FeedListener

**Location**: `app/services/live/feed_listener.rb`

**Purpose**: Enhanced tick processor that subscribes to `MarketFeedHub` and emits structured events via `EventBus`.

**Features**:
- Subscribes to `MarketFeedHub.on_tick` callbacks
- Multi-threaded processing using `Concurrent::FixedThreadPool`
- Enriches ticks with cached data (from `Live::TickCache` and `Live::RedisTickCache`)
- Determines spot price and volatility state
- Emits `LtpEvent` via `EventBus`
- Statistics tracking

**Configuration**:
- `FEED_LISTENER_THREADS` - Thread pool size (default: 4)

**Usage**:
```ruby
# Start listener (usually done via initializer)
Live::FeedListener.instance.start!

# Check status
Live::FeedListener.instance.running?  # => true

# Get statistics
stats = Live::FeedListener.instance.stats
# => { ticks_processed: 1234, events_emitted: 1230, errors: 4 }

# Stop listener
Live::FeedListener.instance.stop!
```

## Integration

### Startup Sequence

1. **MarketFeedHub** starts and begins receiving ticks
2. **FeedListener** starts and subscribes to `MarketFeedHub.on_tick`
3. When ticks arrive:
   - `MarketFeedHub.handle_tick` processes tick (existing logic)
   - `FeedListener.process_tick` receives tick via callback
   - `FeedListener` enriches tick and creates `LtpEvent`
   - `EventBus.publish(:ltp, event)` broadcasts to subscribers

### Non-Breaking Integration

- **FeedListener** is additive - it doesn't modify `MarketFeedHub` behavior
- Existing `MarketFeedHub` callbacks continue to work
- `ActiveSupport::Notifications` events still fire
- `Live::TickCache` updates still happen
- All existing functionality remains intact

### Initializer

**Location**: `config/initializers/nemesis_feed_listener.rb`

The initializer starts `FeedListener` automatically. It can be disabled via:
```bash
NEMESIS_FEED_LISTENER_ENABLED=false
```

## Event Flow

```
MarketFeedHub (WebSocket)
    ↓
handle_tick(tick)
    ↓
    ├─→ Live::TickCache.put(tick) [existing]
    ├─→ ActiveSupport::Notifications.instrument('dhanhq.tick', tick) [existing]
    ├─→ @callbacks.each { |cb| cb.call(tick) } [existing]
    └─→ FeedListener.process_tick(tick) [NEW - via on_tick callback]
            ↓
        Enrich tick with cached data
            ↓
        Create LtpEvent
            ↓
        EventBus.publish(:ltp, event)
            ↓
        Subscribers receive event
            ├─→ RiskManager (future)
            ├─→ Adjuster (future)
            └─→ Other components (future)
```

## Subscribing to Events

### Example: Risk Manager Subscription

```ruby
# In RiskManager initialization
Core::EventBus.instance.subscribe(:ltp) do |event|
  # Check if this is a tracked position
  trackers = Live::PositionIndex.instance.trackers_for(event.security_id)
  next if trackers.empty?

  # Process risk checks
  trackers.each do |tracker|
    check_sl_tp(event, tracker)
    check_trailing_stop(event, tracker)
    check_danger_zone(event, tracker)
  end
end
```

### Example: Adjuster Subscription

```ruby
# In Adjuster initialization
Core::EventBus.instance.subscribe(:ltp) do |event|
  # Check if position needs adjustment
  position = ActiveCache.instance.get(event.composite_key)
  next unless position

  # Move SL to breakeven if conditions met
  move_to_breakeven(event, position) if should_lock_breakeven?(event, position)
end
```

## Thread Safety

All components are thread-safe:
- **EventBus**: Uses `Concurrent::Map` and `Concurrent::Array`
- **FeedListener**: Uses `Mutex` for state management and `Concurrent::FixedThreadPool` for processing
- **LtpEvent**: Immutable data structure (read-only after initialization)

## Performance Considerations

1. **Thread Pool**: Default 4 threads (configurable via `FEED_LISTENER_THREADS`)
2. **Queue Size**: Max 1000 queued ticks (prevents memory bloat)
3. **Error Isolation**: Subscriber errors don't crash the bus
4. **Non-Blocking**: Tick processing is async (doesn't block MarketFeedHub)

## Testing

```ruby
# In RSpec
RSpec.describe Core::EventBus do
  it 'publishes and delivers events' do
    received = []
    bus = Core::EventBus.instance
    bus.clear # Clean state

    subscription = bus.subscribe(:ltp) { |e| received << e }
    event = Live::LtpEvent.new(segment: 'NSE_FNO', security_id: '123', ltp: 100.0)

    bus.publish(:ltp, event)
    sleep(0.1) # Allow async processing

    expect(received.size).to eq(1)
    expect(received.first.ltp).to eq(100.0)

    bus.unsubscribe(subscription)
  end
end
```

## Statistics & Monitoring

```ruby
# EventBus stats
bus_stats = Core::EventBus.instance.stats
# => { events_published: 1234, events_delivered: 1230, errors: 4 }

# FeedListener stats
listener_stats = Live::FeedListener.instance.stats
# => { ticks_processed: 1234, events_emitted: 1230, errors: 4 }

# Subscriber counts
Core::EventBus.instance.subscriber_count(:ltp)  # => 3
```

## Next Steps

1. **RiskManager** - Subscribe to `:ltp` events for tick-by-tick risk checks
2. **Adjuster** - Subscribe to `:ltp` events for SL/TP adjustments
3. **ActiveCache** - Subscribe to `:ltp` events to update position cache
4. **ExitEngine** - Subscribe to `:sl_hit`, `:tp_hit` events for exits

## Files Created

1. `app/services/core/event_bus.rb` - Central event bus
2. `app/services/live/ltp_event.rb` - LTP event data structure
3. `app/services/live/feed_listener.rb` - Enhanced tick processor
4. `config/initializers/nemesis_feed_listener.rb` - Startup hook (optional)

## Dependencies

- `concurrent-ruby` gem (already in Gemfile)
- `singleton` (Ruby standard library)
- `securerandom` (Ruby standard library, for subscription IDs)

