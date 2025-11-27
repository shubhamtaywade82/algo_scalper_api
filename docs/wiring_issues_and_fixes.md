# Wiring Issues and Fixes

## Current Status

After reviewing the codebase, here are the wiring issues found and fixes needed:

---

## ✅ Correctly Wired

### 1. Factory Pattern ✅
- **Status**: Correctly wired
- **Location**: `EntryGuard.create_paper_tracker!` and `create_tracker!`
- **Usage**: Both methods use `Factories::PositionTrackerFactory`

### 2. Builder Pattern ✅
- **Status**: Correctly wired
- **Location**: `EntryGuard.post_entry_wiring`
- **Usage**: Uses `Builders::BracketOrderBuilder` to construct bracket orders

### 3. State Pattern (Partial) ⚠️
- **Status**: Partially wired
- **Issue**: `mark_exited!` method directly updates status, bypassing state validation
- **Fix Needed**: Update `mark_exited!` to use state machine validation

---

## ⚠️ Issues Found

### 1. Specification Pattern - Incomplete Integration

**Issue**: 
- Specification is used but doesn't receive the `instrument` parameter correctly
- Duplicate validation logic still exists (expiry check, LTP check after specification)
- Specification tries to resolve instrument internally, but instrument is already available

**Current Code**:
```ruby
# EntryGuard.try_enter
entry_spec = Specifications::EntryEligibilitySpecification.new(
  index_cfg: index_cfg,
  pick: pick,
  direction: direction
)
# But instrument is available here and not passed to spec
```

**Fix Needed**:
1. Pass instrument to specification
2. Move all validation logic into specification
3. Remove duplicate checks

---

### 2. Command Pattern - Not Integrated

**Issue**: 
- Commands are defined but NOT used anywhere
- Order placement still uses `Orders::Placer` directly
- Exit operations don't use `ExitPositionCommand`

**Current Code**:
```ruby
# EntryGuard still uses:
Orders.config.place_market(...)

# ExitEngine still uses:
tracker.mark_exited!(...)
```

**Fix Needed**:
1. Integrate `PlaceMarketOrderCommand` in `EntryGuard`
2. Integrate `ExitPositionCommand` in `ExitEngine` and `RiskManagerService`

---

### 3. Repository Pattern - Not Integrated

**Issue**: 
- Repository is defined but NOT used anywhere
- Direct `PositionTracker` queries still used throughout codebase

**Current Code**:
```ruby
# Still using direct queries:
PositionTracker.active.find_by(...)
PositionTracker.find_by(...)
```

**Fix Needed**:
1. Replace direct queries with repository methods
2. Start with high-traffic areas (EntryGuard, ExitEngine)

---

### 4. State Pattern - mark_exited! Bypasses Validation

**Issue**: 
- `mark_exited!` directly updates status to 'exited' without state machine validation
- The `update_exit_attributes` method likely sets status directly
- State validation callback will trigger but might fail silently

**Current Code**:
```ruby
def mark_exited!(...)
  update_exit_attributes(exit_price, exited_at, metadata)
  # This likely sets status: 'exited' directly
end
```

**Fix Needed**:
1. Update `mark_exited!` to use state machine
2. Ensure `update_exit_attributes` respects state transitions
3. Or wrap status update in state validation

---

## 🔧 Required Fixes

### Fix 1: Update Specification to Accept Instrument

```ruby
# In EntryGuard.try_enter
entry_spec = Specifications::EntryEligibilitySpecification.new(
  instrument: instrument,  # ADD THIS
  index_cfg: index_cfg,
  pick: pick,
  direction: direction
)
```

### Fix 2: Integrate Command Pattern

```ruby
# In EntryGuard.try_enter (live trading section)
command = Commands::PlaceMarketOrderCommand.new(
  side: 'buy',
  segment: segment,
  security_id: pick[:security_id],
  qty: quantity,
  metadata: { index_key: index_cfg[:key] }
)
result = command.execute
order_no = result[:data][:order_id] if result[:success]
```

### Fix 3: Integrate Repository Pattern

```ruby
# Replace:
PositionTracker.active.find_by(segment: seg, security_id: sid)

# With:
Repositories::PositionTrackerRepository.find_active_by_segment_and_security(
  segment: seg,
  security_id: sid
)
```

### Fix 4: Fix State Pattern Integration

```ruby
# Update mark_exited! to use state machine
def mark_exited!(exit_price: nil, exited_at: nil, exit_reason: nil)
  # Validate state transition first
  State::PositionStateMachine.validate_transition!(status, :exited)
  
  # Then proceed with existing logic
  persist_final_pnl_from_cache
  # ... rest of method
  update!(status: :exited, ...)  # This will trigger validation callback
end
```

---

## 📋 Implementation Checklist

- [ ] Fix Specification Pattern - Pass instrument parameter
- [ ] Fix Specification Pattern - Move all validation into spec
- [ ] Integrate Command Pattern - EntryGuard order placement
- [ ] Integrate Command Pattern - ExitEngine exit operations
- [ ] Integrate Repository Pattern - Replace direct queries
- [ ] Fix State Pattern - Update mark_exited! to use state machine
- [ ] Test all integrations
- [ ] Update documentation

---

## 🎯 Priority Order

1. **High Priority**: Fix State Pattern (prevents invalid transitions)
2. **High Priority**: Fix Specification Pattern (entry validation)
3. **Medium Priority**: Integrate Command Pattern (audit trail)
4. **Low Priority**: Integrate Repository Pattern (code quality)

---

## ⚠️ Breaking Changes

None of these fixes should break existing functionality. All changes are:
- Backward compatible
- Additive (new methods, don't remove old ones)
- Can be adopted gradually

---

## 📝 Notes

- Factory and Builder patterns are correctly wired ✅
- State, Command, Repository, and Specification need fixes ⚠️
- All patterns are production-ready once fixes are applied
- Fixes can be done incrementally without breaking changes
