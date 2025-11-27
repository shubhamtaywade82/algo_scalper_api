# Design Pattern Implementation Guide

## Overview

This guide documents the implementation of six design patterns in the algo scalper API application:

1. **Factory Pattern** - Centralized position tracker creation
2. **Command Pattern** - Order operations with audit trail
3. **State Pattern** - Position lifecycle management
4. **Repository Pattern** - Data access abstraction
5. **Specification Pattern** - Business rules validation
6. **Builder Pattern** - Complex object construction

---

## 1. Factory Pattern

### Location
- `app/services/factories/position_tracker_factory.rb`

### Purpose
Centralizes position tracker creation logic for both paper and live trading, reducing duplication and ensuring consistency.

### Usage

#### Create Paper Tracker
```ruby
tracker = Factories::PositionTrackerFactory.create_paper_tracker(
  instrument: instrument,
  pick: pick_hash,
  side: 'long_ce',
  quantity: 50,
  index_cfg: { key: 'NIFTY', segment: 'NSE_FNO' },
  ltp: BigDecimal('150.50')
)
```

#### Create Live Tracker
```ruby
tracker = Factories::PositionTrackerFactory.create_live_tracker(
  instrument: instrument,
  order_no: 'ORD123456',
  pick: pick_hash,
  side: 'long_pe',
  quantity: 50,
  index_cfg: { key: 'BANKNIFTY', segment: 'NSE_FNO' },
  ltp: BigDecimal('200.75')
)
```

### Benefits
- ✅ Single source of truth for tracker creation
- ✅ Consistent initialization (Redis cache, ActiveCache)
- ✅ Easier to test and maintain
- ✅ Handles watchable resolution automatically

### Migration Notes
- Updated `Entries::EntryGuard` to use factory
- Old direct `PositionTracker.create!` calls replaced
- Backward compatible with existing `build_or_average!` method

---

## 2. Command Pattern

### Location
- `app/services/commands/base_command.rb`
- `app/services/commands/place_market_order_command.rb`
- `app/services/commands/exit_position_command.rb`

### Purpose
Encapsulates order operations as commands with audit trail, retry logic, and undo capability.

### Usage

#### Place Market Order
```ruby
command = Commands::PlaceMarketOrderCommand.new(
  side: 'BUY',
  segment: 'NSE_FNO',
  security_id: '12345',
  qty: 50,
  client_order_id: 'CUSTOM-123',
  metadata: { index_key: 'NIFTY', reason: 'signal_entry' }
)

result = command.execute
if result[:success]
  order_id = result[:data][:order_id]
else
  # Retry with exponential backoff
  retry_result = command.retry
end
```

#### Exit Position
```ruby
command = Commands::ExitPositionCommand.new(
  tracker: position_tracker,
  exit_reason: 'stop_loss_hit',
  exit_price: BigDecimal('145.00'),
  metadata: { triggered_by: 'risk_manager' }
)

result = command.execute
```

### Command Audit Trail
Commands automatically log to cache and emit events:
```ruby
# Retrieve audit log
audit_data = Rails.cache.read("command_audit:#{command.command_id}")

# Listen to command events
Core::EventBus.instance.subscribe(:command_executed) do |event|
  Rails.logger.info("Command executed: #{event[:command_type]}")
end
```

### Benefits
- ✅ Complete audit trail for all orders
- ✅ Automatic retry with exponential backoff
- ✅ Undo capability (where supported)
- ✅ Consistent error handling
- ✅ Event-driven architecture integration

### Migration Notes
- Can be used alongside existing `Orders::Placer` methods
- Gradually migrate order placement to use commands
- Commands emit events for monitoring/alerting

---

## 3. State Pattern

### Location
- `app/services/state/position_state_machine.rb`
- `app/models/concerns/position_state_management.rb`

### Purpose
Manages position lifecycle with validated state transitions, preventing invalid operations.

### Usage

#### State Machine API
```ruby
# Check valid transitions
State::PositionStateMachine.valid_transition?(:pending, :active) # => true
State::PositionStateMachine.valid_transition?(:active, :pending) # => false

# Get valid next states
State::PositionStateMachine.valid_transitions_from(:active) # => [:exited, :cancelled]

# Validate transition (raises if invalid)
State::PositionStateMachine.validate_transition!(:active, :exited)
```

#### Position Tracker Methods
```ruby
tracker = PositionTracker.find(123)

# Transition methods
tracker.activate!                    # pending -> active
tracker.exit!(exit_price: 150.0, exit_reason: 'tp_hit')
tracker.cancel!(reason: 'manual_cancel')

# Query methods
tracker.can_transition_to?(:exited)  # => true/false
tracker.valid_next_states            # => [:exited, :cancelled]
tracker.terminal_state?             # => false (if active)
tracker.state_display_name           # => "Active"
```

### State Transitions
```
pending → active
pending → cancelled
active → exited
active → cancelled
exited → (terminal)
cancelled → (terminal)
```

### Benefits
- ✅ Prevents invalid state transitions
- ✅ Clear position lifecycle
- ✅ Automatic validation on status changes
- ✅ Better error messages

### Migration Notes
- `PositionTracker` model includes `PositionStateManagement` concern
- Existing `mark_exited!` method still works
- New transition methods available for explicit state management

---

## 4. Repository Pattern

### Location
- `app/services/repositories/position_tracker_repository.rb`

### Purpose
Abstracts data access logic, making queries testable and maintainable.

### Usage

#### Find Operations
```ruby
# Find active tracker
tracker = Repositories::PositionTrackerRepository.find_active_by_segment_and_security(
  segment: 'NSE_FNO',
  security_id: '12345'
)

# Find by order number
tracker = Repositories::PositionTrackerRepository.find_by_order_no('ORD123456')

# Find by index key
positions = Repositories::PositionTrackerRepository.find_active_by_index_key('NIFTY')
```

#### Count Operations
```ruby
# Count active positions by side
count = Repositories::PositionTrackerRepository.active_count_by_side(side: 'long_ce')

# Total active count
total = Repositories::PositionTrackerRepository.active_count
```

#### Statistics
```ruby
# Get statistics for all positions
stats = Repositories::PositionTrackerRepository.statistics
# => { total: 100, active: 5, exited: 90, cancelled: 5, ... }

# Get statistics for specific scope
scope = PositionTracker.paper.active
stats = Repositories::PositionTrackerRepository.statistics(scope: scope)
```

### Benefits
- ✅ Centralized query logic
- ✅ Easier to test (can mock repository)
- ✅ Consistent query patterns
- ✅ Can swap implementations (e.g., cache-backed)

### Migration Notes
- Gradually replace direct `PositionTracker` queries
- Repository methods delegate to ActiveRecord
- Can add caching layer in repository without changing callers

---

## 5. Specification Pattern

### Location
- `app/services/specifications/base_specification.rb`
- `app/services/specifications/entry_specifications.rb`

### Purpose
Encapsulates business rules as composable, testable specifications.

### Usage

#### Individual Specifications
```ruby
# Trading session check
session_spec = Specifications::TradingSessionSpecification.new
if session_spec.satisfied?(nil)
  # Allow entry
else
  reason = session_spec.failure_reason(nil)
  Rails.logger.warn("Entry blocked: #{reason}")
end

# Exposure check
exposure_spec = Specifications::ExposureSpecification.new(
  instrument: instrument,
  side: 'long_ce',
  max_same_side: 2
)
unless exposure_spec.satisfied?(nil)
  Rails.logger.warn("Exposure limit: #{exposure_spec.failure_reason(nil)}")
end
```

#### Composite Specifications
```ruby
# Combine with AND
combined = session_spec.and(exposure_spec).and(cooldown_spec)
if combined.satisfied?(nil)
  # All checks passed
else
  reason = combined.failure_reason(nil)
end

# Combine with OR
either = session_spec.or(alternative_spec)

# Negate
not_spec = session_spec.not
```

#### Entry Eligibility (Composite)
```ruby
entry_spec = Specifications::EntryEligibilitySpecification.new(
  index_cfg: { key: 'NIFTY', max_same_side: 2, cooldown_sec: 300 },
  pick: { symbol: 'NIFTY25000CE', ltp: 150.0, expiry: Date.today + 5.days },
  direction: :bullish
)

if entry_spec.satisfied?(nil)
  # Proceed with entry
else
  # Get all failure reasons for debugging
  failures = entry_spec.all_failure_reasons(nil)
  Rails.logger.warn("Entry blocked: #{failures.join(', ')}")
end
```

### Benefits
- ✅ Composable business rules
- ✅ Testable in isolation
- ✅ Clear failure reasons
- ✅ Reusable across contexts

### Migration Notes
- `EntryGuard` uses `EntryEligibilitySpecification` for validation
- Individual specifications can be used independently
- Easy to add new validation rules

---

## 6. Builder Pattern

### Location
- `app/services/builders/bracket_order_builder.rb`

### Purpose
Provides fluent API for constructing complex bracket orders with SL/TP configuration.

### Usage

#### Basic Builder
```ruby
builder = Builders::BracketOrderBuilder.new(tracker)
  .with_stop_loss(100.0)
  .with_take_profit(200.0)
  .with_reason('initial_bracket')

result = builder.build
if result[:success]
  Rails.logger.info("Bracket placed: SL=#{result[:sl_price]}, TP=#{result[:tp_price]}")
end
```

#### Percentage-Based Builder
```ruby
builder = Builders::BracketOrderBuilder.new(tracker)
  .with_stop_loss_percentage(0.30)  # 30% below entry
  .with_take_profit_percentage(0.60) # 60% above entry
  .with_reason('signal_entry')

result = builder.build
```

#### With Trailing Stop
```ruby
builder = Builders::BracketOrderBuilder.new(tracker)
  .with_stop_loss_percentage(0.30)
  .with_take_profit_percentage(0.60)
  .with_trailing(
    enabled: true,
    activation_pct: 0.20,  # Activate trailing after 20% profit
    trail_pct: 0.10         # Trail by 10%
  )
  .with_reason('trailing_bracket')

result = builder.build
```

#### Build Configuration Only
```ruby
config = Builders::BracketOrderBuilder.new(tracker)
  .with_stop_loss_percentage(0.30)
  .with_take_profit_percentage(0.60)
  .build_config

# Use config later or modify before placing
```

### Benefits
- ✅ Fluent, readable API
- ✅ Flexible configuration
- ✅ Automatic validation
- ✅ Default value calculation

### Migration Notes
- `EntryGuard.post_entry_wiring` uses builder
- Can replace direct `BracketPlacer.place_bracket` calls
- Builder validates before placing orders

---

## Integration Examples

### Complete Entry Flow with All Patterns

```ruby
# 1. Specification Pattern - Validate entry eligibility
entry_spec = Specifications::EntryEligibilitySpecification.new(
  index_cfg: index_cfg,
  pick: pick,
  direction: direction
)

return false unless entry_spec.satisfied?(nil)

# 2. Command Pattern - Place order
order_command = Commands::PlaceMarketOrderCommand.new(
  side: 'BUY',
  segment: pick[:segment],
  security_id: pick[:security_id],
  qty: quantity,
  metadata: { index_key: index_cfg[:key] }
)

order_result = order_command.execute
return false unless order_result[:success]

# 3. Factory Pattern - Create tracker
tracker = Factories::PositionTrackerFactory.create_live_tracker(
  instrument: instrument,
  order_no: order_result[:data][:order_id],
  pick: pick,
  side: 'long_ce',
  quantity: quantity,
  index_cfg: index_cfg,
  ltp: ltp
)

# 4. State Pattern - Activate position
tracker.activate! if tracker.pending?

# 5. Builder Pattern - Place bracket orders
Builders::BracketOrderBuilder.new(tracker)
  .with_stop_loss_percentage(0.30)
  .with_take_profit_percentage(0.60)
  .with_reason('initial_bracket')
  .build

# 6. Repository Pattern - Query position
active_positions = Repositories::PositionTrackerRepository.find_active_by_index_key(index_cfg[:key])
```

### Exit Flow with Command and State Patterns

```ruby
# 1. Repository Pattern - Find position
tracker = Repositories::PositionTrackerRepository.find_active_by_segment_and_security(
  segment: segment,
  security_id: security_id
)

return unless tracker

# 2. State Pattern - Check if can exit
unless tracker.can_transition_to?(:exited)
  Rails.logger.warn("Cannot exit: #{tracker.state_display_name}")
  return
end

# 3. Command Pattern - Execute exit
exit_command = Commands::ExitPositionCommand.new(
  tracker: tracker,
  exit_reason: 'stop_loss_hit',
  metadata: { triggered_by: 'risk_manager' }
)

exit_result = exit_command.execute
if exit_result[:success]
  Rails.logger.info("Position exited: #{tracker.order_no}")
end
```

---

## Testing Examples

### Factory Pattern Test
```ruby
RSpec.describe Factories::PositionTrackerFactory do
  it 'creates paper tracker with correct attributes' do
    tracker = described_class.create_paper_tracker(...)
    expect(tracker.paper).to be true
    expect(tracker.status).to eq('active')
  end
end
```

### Specification Pattern Test
```ruby
RSpec.describe Specifications::EntryEligibilitySpecification do
  it 'validates all entry requirements' do
    spec = described_class.new(...)
    expect(spec.satisfied?(nil)).to be true
  end
end
```

### Command Pattern Test
```ruby
RSpec.describe Commands::PlaceMarketOrderCommand do
  it 'executes order placement with audit trail' do
    command = described_class.new(...)
    result = command.execute
    expect(result[:success]).to be true
    
    audit = Rails.cache.read("command_audit:#{command.command_id}")
    expect(audit[:status]).to eq(:completed)
  end
end
```

---

## Migration Checklist

- [x] Factory Pattern implemented
- [x] Command Pattern implemented
- [x] State Pattern implemented
- [x] Repository Pattern implemented
- [x] Specification Pattern implemented
- [x] Builder Pattern implemented
- [x] Updated `EntryGuard` to use Factory and Specifications
- [x] Updated `PositionTracker` to include State Management
- [ ] Migrate all order placement to Command Pattern
- [ ] Migrate all queries to Repository Pattern
- [ ] Add tests for all patterns
- [ ] Update documentation

---

## Best Practices

1. **Factory Pattern**: Use for all object creation, especially complex ones
2. **Command Pattern**: Use for all order operations that need audit trail
3. **State Pattern**: Always use transition methods instead of direct status updates
4. **Repository Pattern**: Use for all database queries, avoid direct ActiveRecord calls
5. **Specification Pattern**: Use for all business rule validation
6. **Builder Pattern**: Use for complex object construction with multiple parameters

---

## Performance Considerations

- **Factory Pattern**: Minimal overhead, improves code organization
- **Command Pattern**: Adds audit logging overhead (cache writes)
- **State Pattern**: Adds validation overhead (negligible)
- **Repository Pattern**: No overhead, just abstraction layer
- **Specification Pattern**: Can chain multiple checks (consider caching)
- **Builder Pattern**: Minimal overhead, improves readability

---

## Future Enhancements

1. **Command Pattern**: Add command queue for async execution
2. **State Pattern**: Add state history tracking
3. **Repository Pattern**: Add caching layer
4. **Specification Pattern**: Add specification registry
5. **Builder Pattern**: Add builder for other complex objects (e.g., strategy config)
