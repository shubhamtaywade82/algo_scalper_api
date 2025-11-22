# FeedListener Analysis: Is It Necessary?

## Current Architecture

```
MarketFeedHub (WebSocket)
  ↓ (raw ticks)
  ├─→ TickCache (storage)
  ├─→ ActiveSupport::Notifications
  └─→ Callbacks (@callbacks)
       ↓
FeedListener (subscribes to callbacks)
  ↓ (enriches + async processing)
  ├─→ Creates LtpEvent objects
  └─→ Publishes to EventBus
       ↓
ActiveCache (subscribes to EventBus)
  ↓
Updates position PnL
```

## What FeedListener Adds

1. **Async Processing**: Thread pool (4 threads by default)
2. **Data Enrichment**:
   - Spot price: Just uses LTP for IDX_I, nil for others
   - Volatility state: Simple heuristic (price change %)
3. **Structured Events**: Creates `LtpEvent` objects
4. **EventBus Integration**: Publishes to EventBus

## Analysis

### FeedListener Enrichment is Minimal

```ruby
# Spot price: Just LTP for index, nil for derivatives
def determine_spot_price(segment, _security_id, tick)
  return tick[:ltp].to_f if segment == 'IDX_I'
  nil  # No actual enrichment
end

# Volatility: Simple price change heuristic
def determine_volatility_state(tick)
  change_pct = ((tick[:ltp] - tick[:close]) / tick[:close] * 100.0).abs
  case change_pct
  when 0.0..0.5 then :low
  when 0.5..2.0 then :normal
  when 2.0..5.0 then :high
  else :extreme
  end
end
```

### ActiveCache May Not Be Started

- Not registered in `trading_supervisor.rb`
- FeedListener publishes events, but no subscribers?
- FeedListener is optional (can be disabled via env var)

## Recommendation: Remove FeedListener

### Option 1: Direct Subscription (Simplest)

Have `ActiveCache` subscribe directly to `MarketFeedHub` callbacks:

```ruby
# In ActiveCache#start!
hub = Live::MarketFeedHub.instance
hub.on_tick { |tick| handle_tick(tick) }
```

**Pros:**
- Simpler architecture
- One less service to manage
- No async overhead (if not needed)
- Direct tick processing

**Cons:**
- Synchronous processing (could block MarketFeedHub)
- No structured LtpEvent objects

### Option 2: MarketFeedHub → EventBus Directly

Have `MarketFeedHub` publish directly to EventBus:

```ruby
# In MarketFeedHub#handle_tick
event = Live::LtpEvent.new(
  segment: tick[:segment],
  security_id: tick[:security_id],
  ltp: tick[:ltp],
  # ... minimal enrichment here if needed
)
Core::EventBus.instance.publish(:ltp, event)
```

**Pros:**
- Keeps EventBus architecture
- Removes FeedListener layer
- Still async if EventBus is async

**Cons:**
- MarketFeedHub becomes responsible for event creation
- Enrichment logic in MarketFeedHub

### Option 3: Keep FeedListener (Current)

**Only if:**
- Async processing is critical
- More complex enrichment is planned
- Multiple EventBus subscribers need structured events

## Decision

**Recommendation: Remove FeedListener**

Reasons:
1. Minimal enrichment doesn't justify a separate service
2. ActiveCache not started = FeedListener events unused
3. MarketFeedHub already has callback mechanism
4. Simpler architecture = easier maintenance

**Implementation:**
- Remove FeedListener from supervisor
- Have ActiveCache subscribe directly to MarketFeedHub
- Or have MarketFeedHub publish to EventBus directly

