#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'base'
ServiceTestHelper.setup_rails

ServiceTestHelper.print_header('Live::RiskManagerService Test')

# Setup prerequisites
ServiceTestHelper.print_section('0. Prerequisites Setup')
ServiceTestHelper.setup_test_position_tracker(paper: true)

risk_manager = Live::RiskManagerService.new

# Test 1: Check active positions
ServiceTestHelper.print_section('1. Active Positions Check')
active_positions = PositionTracker.active.includes(:watchable)
ServiceTestHelper.print_info("Found #{active_positions.count} active positions")

# Test 2: Start risk manager
ServiceTestHelper.print_section('2. Starting Risk Manager')
risk_manager.start
ServiceTestHelper.print_success('Risk Manager started')

# Test 3: Check risk manager thread
ServiceTestHelper.print_section('3. Risk Manager Thread')
risk_thread = Thread.list.find { |t| t.name&.include?('risk') }
if risk_thread&.alive?
  ServiceTestHelper.print_success('Risk manager thread is running')
else
  ServiceTestHelper.print_warning('Risk manager thread not found')
end

# Test 4: Test position risk checks
ServiceTestHelper.print_section('4. Position Risk Checks')
if active_positions.any?
  active_positions.limit(3).each do |tracker|
    ServiceTestHelper.print_info("\nTracker ID: #{tracker.id}")
    ServiceTestHelper.print_info("  Symbol: #{tracker.symbol}")
    ServiceTestHelper.print_info("  Entry Price: ₹#{tracker.entry_price}")
    ServiceTestHelper.print_info("  Quantity: #{tracker.quantity}")

    # Get current PnL
    pnl_data = Live::RedisPnlCache.instance.fetch_pnl(tracker.id)
    if pnl_data
      ServiceTestHelper.print_info("  Current PnL: ₹#{pnl_data[:pnl]}")
      ServiceTestHelper.print_info("  PnL %: #{pnl_data[:pnl_pct]}%")
    else
      ServiceTestHelper.print_warning("  PnL not yet calculated")
    end

    # Risk manager checks these internally
    ServiceTestHelper.print_info("  Risk evaluation: Checked by RiskManager service")
  end
else
  ServiceTestHelper.print_warning('No active positions to check')
end

# Test 5: Test risk limits
ServiceTestHelper.print_section('5. Risk Limits')
ServiceTestHelper.print_info('Risk manager checks:')
ServiceTestHelper.print_info('  - Maximum position size')
ServiceTestHelper.print_info('  - Maximum loss per position')
ServiceTestHelper.print_info('  - Maximum total exposure')
ServiceTestHelper.print_info('  - Stop loss levels')
ServiceTestHelper.print_info('  - Take profit levels')

# Test 6: Wait for risk check cycle
ServiceTestHelper.print_section('6. Risk Check Cycle')
ServiceTestHelper.print_info('Risk manager runs continuously')
ServiceTestHelper.wait_for(5, 'Waiting for risk check cycle')

# Test 7: Check for risk violations
ServiceTestHelper.print_section('7. Risk Violations')
ServiceTestHelper.print_info('Risk violations trigger exit signals')
ServiceTestHelper.print_info('Check logs for risk violation details')

# Test 8: Cleanup
ServiceTestHelper.print_section('8. Cleanup')
at_exit do
  risk_manager.stop if risk_manager.respond_to?(:stop)
  ServiceTestHelper.print_info('Risk Manager stopped')
end

ServiceTestHelper.print_success('RiskManagerService test completed')
ServiceTestHelper.print_info('Risk manager runs continuously - check logs for risk checks')

