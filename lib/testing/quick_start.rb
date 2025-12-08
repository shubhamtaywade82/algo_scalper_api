# frozen_string_literal: true

# Quick Start Script for Service Testing
# Run this in Rails console: load 'lib/testing/quick_start.rb'

puts "\n" + "=" * 80
puts "  SERVICE TESTING QUICK START"
puts "=" * 80
puts "\nLoading Service Test Runner..."
puts "\n"

# Load the main test runner
load 'lib/testing/service_test_runner.rb'

puts "\n" + "=" * 80
puts "  QUICK START COMMANDS"
puts "=" * 80
puts "\n1. Check all service status:"
puts "   show_service_status"
puts "\n2. Check active positions:"
puts "   show_active_positions"
puts "\n3. Test individual services:"
puts "   test_tick_cache"
puts "   test_market_feed_hub"
puts "   test_risk_manager_service"
puts "\n4. Test all services:"
puts "   test_all_services"
puts "\n5. Monitor logs:"
puts "   monitor_logs(30)  # Monitor for 30 seconds"
puts "\n" + "=" * 80
puts "\n"

