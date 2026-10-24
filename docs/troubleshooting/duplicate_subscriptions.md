# Duplicate Subscriptions Issue - Fixed

## Problem

Multiple `subscribe_one` calls were being made for the same `segment:security_id` pair, causing:
- Unnecessary WebSocket traffic
- Potential rate limiting issues
- Log noise

## Root Cause

1. **PositionTracker callbacks**: `after_create_commit :subscribe_to_feed` automatically subscribes when a PositionTracker is created
2. **PositionSyncService**: Calls `tracker.subscribe` for ALL paper positions every 30 seconds, even if already subscribed
3. **No deduplication**: `MarketFeedHub.subscribe` had no tracking of which segment:security_id pairs were already subscribed

## Solution

### 1. Added Subscription Tracking in MarketFeedHub
- Added `@subscribed_keys = Concurrent::Set.new` to track subscribed `segment:security_id` pairs
- Check before subscribing if already subscribed
- Track subscription when subscribing, remove when unsubscribing
- Added `subscribed?(segment:, security_id:)` public method to check subscription status

### 2. Enhanced subscribe() Method
```ruby
def subscribe(segment:, security_id:)
  key = "#{segment}:#{security_id.to_s}"

  if @subscribed_keys.include?(key)
    Rails.logger.debug { "[MarketFeedHub] Already subscribed to #{key}, skipping" }
    return { segment: segment, security_id: security_id.to_s, already_subscribed: true }
  end

  @ws_client.subscribe_one(segment: segment, security_id: security_id.to_s)
  @subscribed_keys.add(key)

  { segment: segment, security_id: security_id.to_s, already_subscribed: false }
end
```

### 3. Enhanced subscribe_many() Method
- Filters out already subscribed instruments before calling WebSocket
- Only subscribes to new instruments
- Tracks all new subscriptions

### 4. Fixed PositionSyncService
- Checks if already subscribed before calling `tracker.subscribe`
- Only subscribes to positions that aren't already subscribed
- Logs skipped subscriptions for debugging

### 5. Fixed PositionTracker Methods
- `PositionTracker#subscribe` now checks `hub.subscribed?` before calling `hub.subscribe()`
- `PositionTracker#subscribe_to_feed` (callback) now checks before subscribing
- Prevents unnecessary calls to MarketFeedHub

### 6. Fixed EntryGuard
- Checks `hub.subscribed?` before subscribing to derivatives for LTP resolution
- Prevents duplicate subscriptions when resolving entry prices

## Benefits

✅ **No duplicate subscriptions** - Each segment:security_id is subscribed only once
✅ **Reduced WebSocket traffic** - Fewer unnecessary subscription messages
✅ **Better performance** - Less overhead from duplicate subscriptions
✅ **Cleaner logs** - No duplicate subscription messages

## Testing

After restart, check logs for:
- `[MarketFeedHub] Already subscribed to X:Y, skipping duplicate subscription` - confirms deduplication working
- `[PositionSync] Paper sync: X new subscriptions, Y already subscribed` - confirms PositionSyncService is checking before subscribing

