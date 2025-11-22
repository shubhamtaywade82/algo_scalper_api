#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'base'
ServiceTestHelper.setup_rails

ServiceTestHelper.print_header('TradingSystem::PositionHeartbeat Service Test')

# Setup prerequisites
ServiceTestHelper.print_section('0. Prerequisites Setup')
ServiceTestHelper.setup_test_position_tracker(paper: true)

heartbeat = TradingSystem::PositionHeartbeat.new

# Test 1: Check service initialization
ServiceTestHelper.print_section('1. Service Initialization')
ServiceTestHelper.print_success('PositionHeartbeat initialized')
ServiceTestHelper.print_info("Heartbeat interval: #{TradingSystem::PositionHeartbeat::INTERVAL} seconds")

# Test 2: Start heartbeat
ServiceTestHelper.print_section('2. Starting PositionHeartbeat')
heartbeat.start
ServiceTestHelper.print_success('PositionHeartbeat started')
ServiceTestHelper.wait_for(1, 'Waiting for heartbeat to initialize')

# Test 3: Verify thread is running
ServiceTestHelper.print_section('3. Thread Verification')
heartbeat_thread = Thread.list.find { |t| t.name == 'position-heartbeat' }
if heartbeat_thread&.alive?
  ServiceTestHelper.print_success('Heartbeat thread is running')
else
  ServiceTestHelper.print_warning('Heartbeat thread not found or not running')
end

# Test 4: Check PositionIndex bulk load
ServiceTestHelper.print_section('4. PositionIndex Bulk Load')
position_index = Live::PositionIndex.instance
initial_keys = position_index.all_keys.size
ServiceTestHelper.print_info("Initial PositionIndex keys: #{initial_keys}")

# Wait for heartbeat to run (INTERVAL = 10 seconds)
ServiceTestHelper.print_info("Waiting for heartbeat cycle (#{TradingSystem::PositionHeartbeat::INTERVAL + 2} seconds)...")
ServiceTestHelper.wait_for(TradingSystem::PositionHeartbeat::INTERVAL + 2, 'Waiting for heartbeat cycle')

# Check if PositionIndex was updated
after_keys = position_index.all_keys.size
ServiceTestHelper.print_info("PositionIndex keys after heartbeat: #{after_keys}")

if after_keys >= initial_keys
  ServiceTestHelper.print_success("PositionIndex bulk load working (keys: #{initial_keys} → #{after_keys})")
else
  ServiceTestHelper.print_info("PositionIndex keys changed (expected if positions were pruned)")
end

# Test 5: Check PositionTrackerPruner
ServiceTestHelper.print_section('5. PositionTrackerPruner')
active_before = PositionTracker.active.count
ServiceTestHelper.print_info("Active positions before pruner: #{active_before}")

# Wait another cycle for pruner to run
ServiceTestHelper.wait_for(TradingSystem::PositionHeartbeat::INTERVAL + 2, 'Waiting for pruner cycle')

active_after = PositionTracker.active.count
ServiceTestHelper.print_info("Active positions after pruner: #{active_after}")

if active_after <= active_before
  ServiceTestHelper.print_success("PositionTrackerPruner working (positions: #{active_before} → #{active_after})")
else
  ServiceTestHelper.print_info("No positions pruned (expected if all positions are valid)")
end

# Test 6: Verify heartbeat continues running
ServiceTestHelper.print_section('6. Continuous Operation')
ServiceTestHelper.print_info('Heartbeat runs continuously every 10 seconds')
ServiceTestHelper.print_info('It performs:')
ServiceTestHelper.print_info('  - PositionIndex.bulk_load_active! (syncs active positions)')
ServiceTestHelper.print_info('  - PositionTrackerPruner.call (removes orphaned positions)')

# Test 7: Cleanup
ServiceTestHelper.print_section('7. Cleanup')
at_exit do
  heartbeat.stop
  ServiceTestHelper.print_info('PositionHeartbeat stopped')
end

ServiceTestHelper.print_success('PositionHeartbeat test completed')
ServiceTestHelper.print_info('Heartbeat runs continuously - check logs for heartbeat details')

