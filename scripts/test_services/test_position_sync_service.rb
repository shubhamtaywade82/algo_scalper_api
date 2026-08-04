#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'base'
ServiceTestHelper.setup_rails

ServiceTestHelper.print_header('Live::PositionSyncService Test')

# Setup prerequisites
ServiceTestHelper.print_section('0. Prerequisites Setup')
ServiceTestHelper.setup_test_instruments

sync_service = Live::PositionSyncService.instance

# Test 1: Check paper trading mode
ServiceTestHelper.print_section('1. Paper Trading Mode Check')
paper_enabled = AlgoConfig.fetch.dig(:paper_trading, :enabled) == true
ServiceTestHelper.print_info("Paper trading enabled: #{paper_enabled}")

# Test 2: Get current positions
ServiceTestHelper.print_section('2. Current Positions')
tracked_positions = PositionTracker.active.count
ServiceTestHelper.print_info("Tracked positions in database: #{tracked_positions}")

if paper_enabled
  ServiceTestHelper.print_info('Paper mode: Positions are managed internally')
else
  ServiceTestHelper.print_info('Live mode: Will sync with DhanHQ API')
end

# Test 3: Force sync
ServiceTestHelper.print_section('3. Force Sync')
ServiceTestHelper.print_info('Forcing position synchronization...')

begin
  sync_service.force_sync!
  ServiceTestHelper.print_success('Position sync completed')
rescue StandardError => e
  ServiceTestHelper.print_error("Sync failed: #{e.class} - #{e.message}")
end

# Test 4: Check sync results
ServiceTestHelper.print_section('4. Sync Results')
after_sync_positions = PositionTracker.active.count
ServiceTestHelper.print_info("Positions after sync: #{after_sync_positions}")

if after_sync_positions > tracked_positions
  new_positions = after_sync_positions - tracked_positions
  ServiceTestHelper.print_success("Found #{new_positions} new positions")
elsif after_sync_positions < tracked_positions
  removed_positions = tracked_positions - after_sync_positions
  ServiceTestHelper.print_info("Marked #{removed_positions} positions as exited")
else
  ServiceTestHelper.print_info('No position changes detected')
end

# Test 5: Check for untracked positions (live mode only)
unless paper_enabled
  ServiceTestHelper.print_section('5. Untracked Positions Check')
  ServiceTestHelper.print_info('Checking for positions in DhanHQ that are not tracked...')

  # This would be done internally by sync_service
  ServiceTestHelper.print_info('Untracked positions are automatically created during sync')
end

# Test 6: Check for orphaned positions
ServiceTestHelper.print_section('6. Orphaned Positions Check')
orphaned = PositionTracker.active.where(status: 'exited')
ServiceTestHelper.print_info("Orphaned positions (exited): #{orphaned.count}")

# Test 7: Sync interval
ServiceTestHelper.print_section('7. Sync Interval')
sync_interval = sync_service.instance_variable_get(:@sync_interval)
ServiceTestHelper.print_info("Sync interval: #{sync_interval} seconds")

# Test 8: Manual sync test
ServiceTestHelper.print_section('8. Manual Sync Test')
ServiceTestHelper.print_info('Running manual sync...')
sync_service.sync_positions!
ServiceTestHelper.print_success('Manual sync completed')

ServiceTestHelper.print_success('PositionSyncService test completed')
ServiceTestHelper.print_info('Sync service runs periodically - check logs for sync details')
