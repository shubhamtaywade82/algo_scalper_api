# Phase 2 Implementation Plan - TDD Approach

## Overview

Phase 2 implements advanced optimizations for `RiskManagerService`:
1. **Consolidated Position Iteration** - Single loop instead of 7-10 iterations
2. **Batch API Calls** - Group LTP fetches into single API call
3. **Consolidated Exit Checks** - Remove duplicate SL/TP checks

## TDD Process

### Step 1: Write Tests ✅
- Created `spec/services/live/risk_manager_service_phase2_spec.rb`
- Tests define expected behavior for all 3 optimizations
- Tests verify performance improvements

### Step 2: Implement Code (Current Step)
- Implement optimizations to make tests pass
- Maintain backward compatibility
- Preserve error isolation

### Step 3: Verify
- Run tests to ensure they pass
- Verify performance improvements
- Check backward compatibility

---

## Implementation Details

### Optimization 1: Consolidated Position Iteration

**Goal**: Iterate positions only once per cycle instead of 7-10 times

**Changes**:
1. Create `process_all_positions_in_single_loop` method
2. Consolidate all position processing into single iteration
3. Batch all operations per position

**New Methods**:
- `process_all_positions_in_single_loop(positions, tracker_map, exit_engine)`
- `process_position_in_cycle(position, tracker, exit_engine)`
- `check_all_exit_conditions(position, tracker, exit_engine)`

**Modified Methods**:
- `monitor_loop` - Use consolidated iteration

---

### Optimization 2: Batch API Calls

**Goal**: Fetch LTP for multiple positions in single API call

**Changes**:
1. Create `batch_fetch_ltp` method
2. Group positions by segment
3. Make single API call per segment
4. Fallback to individual calls if batch fails

**New Methods**:
- `batch_fetch_ltp(security_ids_by_segment)`
- `batch_update_paper_positions_pnl(trackers)`

**Modified Methods**:
- `ensure_all_positions_in_redis` - Use batch fetching
- `update_paper_positions_pnl` - Use batch fetching

---

### Optimization 3: Consolidated Exit Checks

**Goal**: Check all exit conditions in single pass, remove duplicates

**Changes**:
1. Create `check_all_exit_conditions` method
2. Consolidate SL/TP/trailing/time-based/session-end checks
3. Remove duplicate checks between `process_trailing` and `enforce_hard_limits`

**New Methods**:
- `check_all_exit_conditions(position, tracker, exit_engine)`
- `check_sl_tp_limits(position, tracker, exit_engine)`

**Modified Methods**:
- `process_trailing_for_all_positions` - Use consolidated checks
- `enforce_hard_limits` - Remove duplicate checks for ActiveCache positions

---

## Performance Targets

### Before Phase 2 (with 10 positions):
- Iterations per cycle: 7-10
- DB queries per cycle: 3-5
- Redis fetches per cycle: 20-30
- API calls per cycle: 0-10
- Cycle time: 100-500ms

### After Phase 2 (with 10 positions):
- Iterations per cycle: 1
- DB queries per cycle: 1-2
- Redis fetches per cycle: 10
- API calls per cycle: 0-1 (batched)
- Cycle time: 20-100ms

**Target Improvement**: ~5x faster per cycle

---

## Risk Mitigation

1. **Backward Compatibility**: All existing behavior preserved
2. **Error Isolation**: Errors in one position don't affect others
3. **Throttling**: All throttling logic preserved
4. **Fallback**: Batch API calls fallback to individual calls on failure
5. **Testing**: Comprehensive test coverage before deployment

---

## Implementation Order

1. ✅ Write tests (TDD)
2. ⏳ Implement consolidated iteration
3. ⏳ Implement batch API calls
4. ⏳ Implement consolidated exit checks
5. ⏳ Run tests and verify
6. ⏳ Performance testing
7. ⏳ Deploy to staging
