# frozen_string_literal: true

# Test helper to ensure trading services are stopped
RSpec.configure do |config|
  config.before(:suite) do
    # Ensure all trading services are stopped before running tests
    # Rails.logger.info('[TestHelper] Ensuring trading services are stopped for test suite')

    begin
      Live::MarketFeedHub.instance.stop! if Live::MarketFeedHub.instance.running?
      if Live::OrderUpdateHandler.instance.respond_to?(:running?) && Live::OrderUpdateHandler.instance.running?
        Live::OrderUpdateHandler.instance.stop!
      end
      if Signal::Scheduler.instance.respond_to?(:running?) && Signal::Scheduler.instance.running?
        Signal::Scheduler.instance.stop!
      end
      Live::RiskManagerService.instance.stop! if Live::RiskManagerService.instance.running?
      if defined?(Live::AtmOptionsService)
        atm_service = Live::AtmOptionsService.instance
        atm_service.stop! if atm_service.respond_to?(:running?) && atm_service.running?
      end
      if Live::MockDataService.instance.respond_to?(:running?) && Live::MockDataService.instance.running?
        Live::MockDataService.instance.stop!
      end
      if defined?(Live::PnlUpdaterService) && Live::PnlUpdaterService.instance.respond_to?(:running?) && Live::PnlUpdaterService.instance.running?
        Live::PnlUpdaterService.instance.stop!
      end
    rescue StandardError => e
      # Rails.logger.warn("[TestHelper] Error stopping services: #{e.message}")
    end
  end

  config.after(:suite) do
    # Clean up any remaining services after test suite
    # Rails.logger.info('[TestHelper] Cleaning up trading services after test suite')

    begin
      Live::MarketFeedHub.instance.stop! if Live::MarketFeedHub.instance.running?
      if Live::OrderUpdateHandler.instance.respond_to?(:running?) && Live::OrderUpdateHandler.instance.running?
        Live::OrderUpdateHandler.instance.stop!
      end
      if Signal::Scheduler.instance.respond_to?(:running?) && Signal::Scheduler.instance.running?
        Signal::Scheduler.instance.stop!
      end
      Live::RiskManagerService.instance.stop! if Live::RiskManagerService.instance.running?
      if defined?(Live::AtmOptionsService)
        atm_service = Live::AtmOptionsService.instance
        atm_service.stop! if atm_service.respond_to?(:running?) && atm_service.running?
      end
      if Live::MockDataService.instance.respond_to?(:running?) && Live::MockDataService.instance.running?
        Live::MockDataService.instance.stop!
      end
      if defined?(Live::PnlUpdaterService) && Live::PnlUpdaterService.instance.respond_to?(:running?) && Live::PnlUpdaterService.instance.running?
        Live::PnlUpdaterService.instance.stop!
      end
    rescue StandardError => e
      # Rails.logger.warn("[TestHelper] Error cleaning up services: #{e.message}")
    end
  end
end
