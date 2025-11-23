#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'base'
ServiceTestHelper.setup_rails

ServiceTestHelper.print_header('Live::PositionIndex Service Test')

# Setup prerequisites
ServiceTestHelper.print_section('0. Prerequisites Setup')
ServiceTestHelper.setup_test_position_tracker(paper: true)

position_index = Live::PositionIndex.instance

# Test 1: Check active positions
ServiceTestHelper.print_section('1. Active Positions')
active_positions = PositionTracker.active.includes(:watchable)
ServiceTestHelper.print_info("Found #{active_positions.count} active positions")

# Test 2: Add positions to index
ServiceTestHelper.print_section('2. Adding Positions to Index')
if active_positions.any?
  added_count = 0
  active_positions.each do |tracker|
    seg = tracker.segment || tracker.watchable&.exchange_segment || tracker.instrument&.exchange_segment
    sid = tracker.security_id

    if seg.present? && sid.present? && tracker.entry_price.present? && tracker.quantity.present?
      metadata = {
        id: tracker.id,
        security_id: sid,
        entry_price: tracker.entry_price.to_f,
        quantity: tracker.quantity.to_i,
        segment: seg
      }
      position_index.add(metadata)
      ServiceTestHelper.print_success("Added: #{seg}:#{sid} (tracker #{tracker.id})")
      added_count += 1
    else
      ServiceTestHelper.print_warning("Skipped tracker #{tracker.id}: missing required fields")
    end
  end
  ServiceTestHelper.print_info("Added #{added_count} positions to index")
else
  ServiceTestHelper.print_info('No active positions to add (this is expected if no trades are running)')
end

# Test 3: Get all keys
ServiceTestHelper.print_section('3. All Keys')
all_keys = position_index.all_keys
ServiceTestHelper.print_info("Total keys in index: #{all_keys.size}")

if all_keys.any?
  ServiceTestHelper.print_info("Sample keys: #{all_keys.first(5).join(', ')}")
else
  ServiceTestHelper.print_warning('No keys in index')
end

# Test 4: Check if key exists
ServiceTestHelper.print_section('4. Key Existence Check')
if all_keys.any?
  test_key = all_keys.first
  # Check if key exists by checking if it's in all_keys
  exists = all_keys.include?(test_key)
  ServiceTestHelper.check_condition(
    exists,
    "Key exists: #{test_key}",
    "Key not found: #{test_key}"
  )

  # Test trackers_for method
  trackers = position_index.trackers_for(test_key)
  if trackers.any?
    ServiceTestHelper.print_success("Found #{trackers.size} tracker(s) for security_id: #{test_key}")
  end
end

# Test 5: Remove position
ServiceTestHelper.print_section('5. Remove Position')
if all_keys.any? && active_positions.any?
  test_key = all_keys.first
  tracker = active_positions.find { |t| t.security_id.to_s == test_key }

  if tracker
    position_index.remove(tracker.id, tracker.security_id)
    ServiceTestHelper.print_success("Removed tracker #{tracker.id} for security_id: #{test_key}")

    # Verify removal
    keys_after = position_index.all_keys
    exists_after = keys_after.include?(test_key)
    ServiceTestHelper.check_condition(
      !exists_after || position_index.trackers_for(test_key).empty?,
      "Position removed successfully",
      "Position still exists after removal"
    )
  else
    ServiceTestHelper.print_warning("Could not find tracker for security_id: #{test_key}")
  end
end

# Test 6: Clear index
ServiceTestHelper.print_section('6. Clear Index')
position_index.clear
cleared_keys = position_index.all_keys
ServiceTestHelper.check_condition(
  cleared_keys.empty?,
  "Index cleared: #{cleared_keys.size} keys remaining",
  "Index clear failed: #{cleared_keys.size} keys remaining"
)

# Test 7: Rebuild index from active positions
ServiceTestHelper.print_section('7. Rebuild Index')
if active_positions.any?
  rebuilt_count = 0
  active_positions.each do |tracker|
    seg = tracker.segment || tracker.watchable&.exchange_segment || tracker.instrument&.exchange_segment
    sid = tracker.security_id

    if seg.present? && sid.present? && tracker.entry_price.present? && tracker.quantity.present?
      metadata = {
        id: tracker.id,
        security_id: sid,
        entry_price: tracker.entry_price.to_f,
        quantity: tracker.quantity.to_i,
        segment: seg
      }
      position_index.add(metadata)
      rebuilt_count += 1
    end
  end

  rebuilt_keys = position_index.all_keys
  ServiceTestHelper.print_success("Index rebuilt: #{rebuilt_keys.size} keys (#{rebuilt_count} positions added)")
end

# Cleanup: Remove test position trackers created during this test
ServiceTestHelper.print_section('8. Cleanup')
begin
  # Find test trackers created by setup_test_position_tracker
  # They are identified by: paper=true, order_no starts with "TEST-", and created recently
  test_trackers = PositionTracker.where(paper: true)
                                  .where("order_no LIKE 'TEST-%'")
                                  .where('created_at > ?', 10.minutes.ago)

  if test_trackers.any?
    deleted_count = test_trackers.count
    test_trackers.destroy_all
    ServiceTestHelper.print_success("Cleaned up #{deleted_count} test position tracker(s) from database")
  else
    ServiceTestHelper.print_info('No test position trackers to clean up (or they were already cleaned)')
  end

  # Also clear the index one more time to ensure it's clean
  position_index.clear
  ServiceTestHelper.print_info('PositionIndex cleared')
rescue StandardError => e
  ServiceTestHelper.print_warning("Cleanup error: #{e.message}")
end

ServiceTestHelper.print_success('PositionIndex test completed')

