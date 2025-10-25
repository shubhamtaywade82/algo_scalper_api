# frozen_string_literal: true

# Test helper to ensure trading services are stopped
RSpec.configure do |config|
  config.before(:suite) do
    # Ensure all trading services are stopped before running tests
    Rails.logger.info("[TestHelper] Ensuring trading services are stopped for test suite")

    begin
      Live::MarketFeedHub.instance.stop! if Live::MarketFeedHub.instance.running?
      Live::OrderUpdateHandler.instance.stop! if Live::OrderUpdateHandler.instance.respond_to?(:running?) && Live::OrderUpdateHandler.instance.running?
      Live::OhlcPrefetcherService.instance.stop! if Live::OhlcPrefetcherService.instance.running?
      Signal::Scheduler.instance.stop! if Signal::Scheduler.instance.respond_to?(:running?) && Signal::Scheduler.instance.running?
      Live::RiskManagerService.instance.stop! if Live::RiskManagerService.instance.running?
      Live::AtmOptionsService.instance.stop! if Live::AtmOptionsService.instance.running?
      Live::MockDataService.instance.stop! if Live::MockDataService.instance.respond_to?(:running?) && Live::MockDataService.instance.running?
    rescue StandardError => e
      Rails.logger.warn("[TestHelper] Error stopping services: #{e.message}")
    end
  end

  config.after(:suite) do
    # Clean up any remaining services after test suite
    Rails.logger.info("[TestHelper] Cleaning up trading services after test suite")

    begin
      Live::MarketFeedHub.instance.stop! if Live::MarketFeedHub.instance.running?
      Live::OrderUpdateHandler.instance.stop! if Live::OrderUpdateHandler.instance.respond_to?(:running?) && Live::OrderUpdateHandler.instance.running?
      Live::OhlcPrefetcherService.instance.stop! if Live::OhlcPrefetcherService.instance.running?
      Signal::Scheduler.instance.stop! if Signal::Scheduler.instance.respond_to?(:running?) && Signal::Scheduler.instance.running?
      Live::RiskManagerService.instance.stop! if Live::RiskManagerService.instance.running?
      Live::AtmOptionsService.instance.stop! if Live::AtmOptionsService.instance.running?
      Live::MockDataService.instance.stop! if Live::MockDataService.instance.respond_to?(:running?) && Live::MockDataService.instance.running?
    rescue StandardError => e
      Rails.logger.warn("[TestHelper] Error cleaning up services: #{e.message}")
    end
  end
end
