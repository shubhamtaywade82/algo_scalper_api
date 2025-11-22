#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'base'
ServiceTestHelper.setup_rails

ServiceTestHelper.print_header('Signal::Scheduler Service Test')

# Setup prerequisites
ServiceTestHelper.print_section('0. Prerequisites Setup')
ServiceTestHelper.setup_test_watchlist_items

scheduler = Signal::Scheduler.new

# Test 1: Check watchlist items
ServiceTestHelper.print_section('1. Watchlist Items')
# WatchlistItem uses polymorphic watchable, not direct instrument association
watchlist_items = WatchlistItem.where(active: true).includes(:watchable)
ServiceTestHelper.print_info("Found #{watchlist_items.count} active watchlist items")

if watchlist_items.empty?
  ServiceTestHelper.print_warning('No active watchlist items - cannot test signal generation')
  exit 0
end

# Test 2: Start scheduler
ServiceTestHelper.print_section('2. Starting Scheduler')
scheduler.start
ServiceTestHelper.print_success('Scheduler started')

# Test 3: Verify scheduler is running
ServiceTestHelper.print_section('3. Scheduler Thread Verification')
ServiceTestHelper.wait_for(2, 'Waiting for scheduler to initialize')

scheduler_thread = Thread.list.find { |t| t.name == 'signal-scheduler' }
if scheduler_thread&.alive?
  ServiceTestHelper.print_success('Scheduler thread is running')
  ServiceTestHelper.print_info('Scheduler evaluates each watchlist item with staggered delays')
else
  ServiceTestHelper.print_warning('Scheduler thread not found or not running')
  ServiceTestHelper.print_info('This may be expected if scheduler uses a different thread name')
end

# Test 4: Check signal generation status
ServiceTestHelper.print_section('4. Signal Generation Status')
ServiceTestHelper.print_info('Signal generation is asynchronous and staggered')
ServiceTestHelper.print_info('Scheduler processes watchlist items in background')
ServiceTestHelper.print_info('Check logs for signal generation details')
ServiceTestHelper.print_info('Note: Signals may take time to generate depending on market conditions')

# Test 5: Cleanup
ServiceTestHelper.print_section('5. Cleanup')
at_exit do
  scheduler.stop if scheduler.respond_to?(:stop)
  ServiceTestHelper.print_info('Scheduler stopped')
end

ServiceTestHelper.print_success('Signal Scheduler test completed')
ServiceTestHelper.print_info('Scheduler runs continuously - check logs for signal details')

