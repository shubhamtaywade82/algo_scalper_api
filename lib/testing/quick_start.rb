# frozen_string_literal: true

# Quick Start Script for Service Testing
# Run this in Rails console: load 'lib/testing/quick_start.rb'

Rails.logger.debug { "\n#{'=' * 80}" }
Rails.logger.debug '  SERVICE TESTING QUICK START'
Rails.logger.debug '=' * 80
Rails.logger.debug "\nLoading Service Test Runner..."
Rails.logger.debug "\n"

# Load the main test runner
load 'lib/testing/service_test_runner.rb'

Rails.logger.debug { "\n#{'=' * 80}" }
Rails.logger.debug '  QUICK START COMMANDS'
Rails.logger.debug '=' * 80
Rails.logger.debug "\n1. Check all service status:"
Rails.logger.debug '   show_service_status'
Rails.logger.debug "\n2. Check active positions:"
Rails.logger.debug '   show_active_positions'
Rails.logger.debug "\n3. Test individual services:"
Rails.logger.debug '   test_tick_cache'
Rails.logger.debug '   test_market_feed_hub'
Rails.logger.debug '   test_risk_manager_service'
Rails.logger.debug "\n4. Test all services:"
Rails.logger.debug '   test_all_services'
Rails.logger.debug "\n5. Monitor logs:"
Rails.logger.debug '   monitor_logs(30)  # Monitor for 30 seconds'
Rails.logger.debug { "\n#{'=' * 80}" }
Rails.logger.debug "\n"
