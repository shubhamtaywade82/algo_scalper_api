# Phase 3 Implementation Plan - Advanced Features & Observability

## Overview

Phase 3 focuses on **observability, resilience, and advanced features** after Phase 2 optimizations are validated:

1. **Metrics & Monitoring** - Track performance and health
2. **Circuit Breaker** - Protect against API failures
3. **Adaptive Throttling** - Dynamic rate limiting based on load
4. **Health Monitoring** - Service health checks and alerts
5. **Performance Profiling** - Built-in performance metrics

---

## Phase 3 Goals

### 1. Observability
- Track cycle times, iteration counts, API call counts
- Monitor Redis fetch performance
- Track exit trigger frequencies
- Alert on performance degradation

### 2. Resilience
- Circuit breaker for API failures
- Graceful degradation when services are down
- Automatic recovery mechanisms
- Health check endpoints

### 3. Advanced Features
- Adaptive throttling based on system load
- Performance profiling built-in
- Detailed metrics export
- Historical performance tracking

---

## Implementation Details

### Feature 1: Metrics & Monitoring

**Goal**: Track all key performance indicators

**New Methods**:
- `record_cycle_metrics` - Track cycle performance
- `get_metrics` - Return current metrics
- `reset_metrics` - Reset metrics (for testing)

**Metrics to Track**:
- Cycle time (min/max/avg)
- Positions processed per cycle
- Redis fetch count
- DB query count
- API call count
- Exit trigger counts by reason
- Error counts by type

**Implementation**:
```ruby
def record_cycle_metrics(cycle_time:, positions_count:, redis_fetches:, db_queries:, api_calls:)
  @metrics[:cycle_count] += 1
  @metrics[:total_cycle_time] += cycle_time
  @metrics[:min_cycle_time] = [@metrics[:min_cycle_time] || cycle_time, cycle_time].min
  @metrics[:max_cycle_time] = [@metrics[:max_cycle_time] || 0, cycle_time].max
  @metrics[:total_positions] += positions_count
  @metrics[:total_redis_fetches] += redis_fetches
  @metrics[:total_db_queries] += db_queries
  @metrics[:total_api_calls] += api_calls
end

def get_metrics
  {
    cycle_count: @metrics[:cycle_count] || 0,
    avg_cycle_time: @metrics[:cycle_count]&.positive? ? (@metrics[:total_cycle_time] / @metrics[:cycle_count]) : 0,
    min_cycle_time: @metrics[:min_cycle_time],
    max_cycle_time: @metrics[:max_cycle_time],
    avg_positions_per_cycle: @metrics[:cycle_count]&.positive? ? (@metrics[:total_positions] / @metrics[:cycle_count]) : 0,
    avg_redis_fetches_per_cycle: @metrics[:cycle_count]&.positive? ? (@metrics[:total_redis_fetches] / @metrics[:cycle_count]) : 0,
    avg_db_queries_per_cycle: @metrics[:cycle_count]&.positive? ? (@metrics[:total_db_queries] / @metrics[:cycle_count]) : 0,
    avg_api_calls_per_cycle: @metrics[:cycle_count]&.positive? ? (@metrics[:total_api_calls] / @metrics[:cycle_count]) : 0,
    exit_counts: @metrics.select { |k, _| k.to_s.start_with?('exit_') },
    error_counts: @metrics.select { |k, _| k.to_s.start_with?('error_') }
  }
end
```

---

### Feature 2: Circuit Breaker for API Failures

**Goal**: Prevent cascading failures when APIs are down

**New Methods**:
- `circuit_breaker_open?` - Check if circuit is open
- `record_api_failure` - Record API failure
- `record_api_success` - Record API success
- `reset_circuit_breaker` - Reset circuit breaker

**Implementation**:
```ruby
def initialize(exit_engine: nil, trailing_engine: nil)
  # ... existing initialization ...
  @circuit_breaker_state = :closed # :closed, :open, :half_open
  @circuit_breaker_failures = 0
  @circuit_breaker_last_failure = nil
  @circuit_breaker_threshold = 5 # Open after 5 failures
  @circuit_breaker_timeout = 60 # Stay open for 60 seconds
end

def circuit_breaker_open?(cache_key = nil)
  return false if @circuit_breaker_state == :closed
  
  if @circuit_breaker_state == :open
    # Check if timeout has passed
    if @circuit_breaker_last_failure && 
       (Time.current - @circuit_breaker_last_failure) > @circuit_breaker_timeout
      @circuit_breaker_state = :half_open
      @circuit_breaker_failures = 0
      return false
    end
    return true
  end
  
  # half_open state - allow one request to test
  false
end

def record_api_failure(cache_key = nil)
  @circuit_breaker_failures += 1
  @circuit_breaker_last_failure = Time.current
  
  if @circuit_breaker_failures >= @circuit_breaker_threshold
    @circuit_breaker_state = :open
    Rails.logger.warn("[RiskManager] Circuit breaker OPEN - API failures: #{@circuit_breaker_failures}")
  end
end

def record_api_success(cache_key = nil)
  if @circuit_breaker_state == :half_open
    @circuit_breaker_state = :closed
    @circuit_breaker_failures = 0
    Rails.logger.info("[RiskManager] Circuit breaker CLOSED - API recovered")
  elsif @circuit_breaker_state == :open
    # Reset failures on success
    @circuit_breaker_failures = 0
  end
end
```

---

### Feature 3: Adaptive Throttling

**Goal**: Dynamically adjust throttling based on system load

**New Methods**:
- `calculate_adaptive_throttle` - Calculate throttle based on load
- `adjust_throttle_based_on_performance` - Adjust throttle dynamically

**Implementation**:
```ruby
def calculate_adaptive_throttle
  base_throttle = API_CALL_STAGGER_SECONDS
  
  # Adjust based on recent error rate
  recent_errors = @metrics[:recent_api_errors] || 0
  if recent_errors > 3
    base_throttle *= 2 # Double throttle on high errors
  end
  
  # Adjust based on cycle time
  avg_cycle_time = @metrics[:avg_cycle_time] || 0
  if avg_cycle_time > 0.5 # If cycles taking > 500ms
    base_throttle *= 1.5 # Increase throttle
  end
  
  base_throttle
end
```

---

### Feature 4: Health Check Endpoint

**Goal**: Provide health status for monitoring

**New Methods**:
- `health_status` - Return health status
- `running?` - Already exists, but enhance with details

**Implementation**:
```ruby
def health_status
  {
    running: running?,
    thread_alive: @thread&.alive?,
    last_cycle_time: @metrics[:last_cycle_time],
    active_positions: PositionTracker.active.count,
    circuit_breaker_state: @circuit_breaker_state,
    recent_errors: @metrics[:recent_api_errors] || 0,
    uptime_seconds: running? ? (Time.current - @started_at).to_i : 0
  }
end
```

---

### Feature 5: Performance Profiling

**Goal**: Built-in performance profiling

**New Methods**:
- `profile_cycle` - Profile a single cycle
- `get_performance_report` - Get detailed performance report

**Implementation**:
```ruby
def profile_cycle(&block)
  start_time = Time.current
  redis_fetches_before = @metrics[:total_redis_fetches] || 0
  db_queries_before = @metrics[:total_db_queries] || 0
  api_calls_before = @metrics[:total_api_calls] || 0
  
  result = yield
  
  cycle_time = Time.current - start_time
  redis_fetches = (@metrics[:total_redis_fetches] || 0) - redis_fetches_before
  db_queries = (@metrics[:total_db_queries] || 0) - db_queries_before
  api_calls = (@metrics[:total_api_calls] || 0) - api_calls_before
  
  record_cycle_metrics(
    cycle_time: cycle_time,
    positions_count: active_cache_positions.length,
    redis_fetches: redis_fetches,
    db_queries: db_queries,
    api_calls: api_calls
  )
  
  result
end
```

---

## TDD Approach

### Step 1: Write Tests First
Create `spec/services/live/risk_manager_service_phase3_spec.rb` with tests for:
- Metrics tracking
- Circuit breaker behavior
- Adaptive throttling
- Health check endpoint
- Performance profiling

### Step 2: Implement Features
Implement each feature to make tests pass

### Step 3: Integration
Integrate with existing monitoring systems

---

## Expected Benefits

1. **Observability**: Full visibility into service performance
2. **Resilience**: Automatic recovery from API failures
3. **Performance**: Adaptive throttling improves efficiency
4. **Debugging**: Detailed metrics help identify issues
5. **Monitoring**: Health checks enable proactive monitoring

---

## Implementation Order

1. ✅ Write tests (TDD)
2. ⏳ Implement metrics & monitoring
3. ⏳ Implement circuit breaker
4. ⏳ Implement adaptive throttling
5. ⏳ Implement health check endpoint
6. ⏳ Implement performance profiling
7. ⏳ Integration testing
8. ⏳ Deploy to staging

---

## Risk Assessment

**Low Risk**:
- Metrics tracking (read-only, no behavior change)
- Health check endpoint (new feature, doesn't affect existing code)

**Medium Risk**:
- Circuit breaker (could block legitimate requests if misconfigured)
- Adaptive throttling (could slow down system if too aggressive)

**Mitigation**:
- Comprehensive testing
- Configurable thresholds
- Gradual rollout
- Monitoring during deployment

---

## Success Criteria

1. ✅ All tests pass
2. ✅ Metrics accurately track performance
3. ✅ Circuit breaker prevents cascading failures
4. ✅ Adaptive throttling improves performance
5. ✅ Health check provides accurate status
6. ✅ No performance degradation
7. ✅ Backward compatibility maintained

---

**Status**: 📋 **Planning Complete - Ready for TDD Implementation**
