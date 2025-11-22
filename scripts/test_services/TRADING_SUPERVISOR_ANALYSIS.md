# TradingSupervisor Analysis & Potential Issues

## Current Implementation Review

### ✅ What Works Well

1. **Service Registration**: All services are properly registered
2. **Start/Stop Methods**: All services implement `start`/`stop` methods:
   - ✅ `MarketFeedHubService` → `@hub.start!` / `@hub.stop!`
   - ✅ `Signal::Scheduler` → `start` / `stop`
   - ✅ `Live::RiskManagerService` → `start` / `stop`
   - ✅ `TradingSystem::PositionHeartbeat` → `start` / `stop`
   - ✅ `TradingSystem::OrderRouter` → `start` / `stop`
   - ✅ `Live::PaperPnlRefresher` → `start` / `stop`
   - ✅ `Live::ExitEngine` → `start` / `stop`
   - ✅ `ActiveCacheService` → `@cache.start!` / `@cache.stop!`

3. **Error Handling**: Supervisor catches exceptions during start/stop
4. **Signal Handlers**: Properly handles INT/TERM signals for graceful shutdown
5. **at_exit Hook**: Fallback cleanup mechanism

### ⚠️ Potential Issues

#### 1. **Rails Reload in Development**

**Issue**: `Rails.application.config.to_prepare` runs on EVERY code reload in development mode.

**Problem**:
- New supervisor instance created on each reload
- Services re-registered but `$trading_supervisor_started` guard prevents re-starting
- Old services may still be running (orphaned threads)
- New supervisor instance has no reference to old services

**Impact**:
- Memory leaks (orphaned threads)
- Duplicate service instances
- Services not properly stopped on reload

**Fix Needed**:
```ruby
# Store reference to old supervisor before creating new one
old_supervisor = Rails.application.config.x.trading_supervisor
old_supervisor&.stop_all

# Then create new supervisor
supervisor = TradingSystem::Supervisor.new
# ... register services ...
```

#### 2. **Service Start Order Dependency**

**Issue**: Services are started in registration order, but some have dependencies:

- `ActiveCache` needs `MarketFeedHub` to be running first (for subscription)
- `ExitEngine` needs `OrderRouter` to be running
- `Signal::Scheduler` needs `MarketFeedHub` for tick data

**Current Behavior**: Services start in arbitrary order, which could cause:
- `ActiveCache` trying to subscribe before `MarketFeedHub` is connected
- `Signal::Scheduler` processing before market data is available

**Fix Needed**: Implement dependency-aware startup:
```ruby
def start_all
  # Start in dependency order
  start_service(:market_feed)      # First - no dependencies
  start_service(:active_cache)     # Depends on market_feed
  start_service(:order_router)    # No dependencies
  start_service(:exit_manager)     # Depends on order_router
  # ... etc
end
```

#### 3. **Partial Startup Failure**

**Issue**: If one service fails to start, others continue starting.

**Problem**:
- Supervisor marks `@running = true` even if some services failed
- No rollback mechanism
- System may be in inconsistent state

**Fix Needed**:
- Track which services started successfully
- Implement rollback on critical service failure
- Or at least log which services failed

#### 4. **Global Variable for Startup Guard**

**Issue**: Uses `$trading_supervisor_started` global variable.

**Problem**:
- Global variables are not thread-safe
- In multi-threaded environments (Puma with multiple workers), each worker has its own process, but globals can still cause issues
- Not ideal for testing

**Better Approach**: Use Rails.config.x or a class variable:
```ruby
unless Rails.application.config.x.trading_supervisor_started
  Rails.application.config.x.trading_supervisor_started = true
  # ...
end
```

#### 5. **ActiveCache Subscription Timing**

**Issue**: `ActiveCache` subscribes to `MarketFeedHub` in its `start!` method, but `MarketFeedHub` may not be connected yet.

**Current Code**:
```ruby
def start!
  hub = Live::MarketFeedHub.instance
  hub.on_tick { |tick| handle_tick(tick) } # Direct subscription
  # ...
end
```

**Problem**: If `MarketFeedHub` hasn't connected to WebSocket yet, subscription may be lost.

**Fix Needed**: Wait for connection or use a callback:
```ruby
def start!
  hub = Live::MarketFeedHub.instance
  if hub.connected?
    hub.on_tick { |tick| handle_tick(tick) }
  else
    # Wait for connection or subscribe on connect event
  end
end
```

#### 6. **PositionIndex Subscription**

**Issue**: Supervisor subscribes to active positions AFTER starting all services:

```ruby
supervisor.start_all
active_pairs = Live::PositionIndex.instance.all_keys.map { ... }
supervisor[:market_feed].subscribe_many(active_pairs) if active_pairs.any?
```

**Problem**:
- `PositionIndex` may be empty at startup (positions loaded later)
- Active positions from database not automatically subscribed
- Need to ensure `PositionIndex.bulk_load_active!` runs before subscription

**Fix Needed**: Ensure `PositionHeartbeat` runs `bulk_load_active!` before subscription, or do it explicitly:
```ruby
Live::PositionIndex.instance.bulk_load_active!
active_pairs = Live::PositionIndex.instance.all_keys.map { ... }
supervisor[:market_feed].subscribe_many(active_pairs) if active_pairs.any?
```

#### 7. **Service Stop Order**

**Issue**: Services are stopped in reverse order, but some should stop before others.

**Current**: `@services.reverse_each` - stops in reverse registration order

**Better**: Stop in dependency order (opposite of start):
- Stop `ExitEngine` before `OrderRouter`
- Stop `ActiveCache` before `MarketFeedHub`
- Stop `Signal::Scheduler` before `MarketFeedHub`

#### 8. **Missing Health Checks**

**Issue**: No way to verify services are actually running after startup.

**Fix Needed**: Add health check method:
```ruby
def health_check
  @services.map do |name, service|
    running = service.respond_to?(:running?) ? service.running? : true
    { name: name, running: running }
  end
end
```

## Recommendations

### High Priority Fixes

1. **Fix Rails Reload Issue**: Stop old supervisor before creating new one
2. **Fix Service Start Order**: Implement dependency-aware startup
3. **Fix ActiveCache Subscription**: Wait for MarketFeedHub connection
4. **Fix PositionIndex Subscription**: Load positions before subscribing

### Medium Priority

5. **Improve Error Handling**: Track which services started/failed
6. **Replace Global Variable**: Use Rails.config.x instead
7. **Add Health Checks**: Verify services are actually running

### Low Priority

8. **Improve Stop Order**: Stop in dependency order
9. **Add Service Status API**: Expose service status via health endpoint

## Testing Recommendations

1. **Test in Development Mode**: Verify services restart correctly on code reload
2. **Test Service Dependencies**: Verify ActiveCache works after MarketFeedHub connects
3. **Test Partial Failures**: Verify system handles service startup failures gracefully
4. **Test Signal Handling**: Verify CTRL+C properly stops all services
5. **Test Position Subscription**: Verify active positions are subscribed on startup

