# frozen_string_literal: true

Rails.application.config.to_prepare do
  module Orders
    class << self
      attr_accessor :config
    end
  end

  gateway = Orders::GatewayFactory.build

  # Set structured config, not raw gateway
  Orders.config = Orders::Config.new(gateway: gateway)

  paper = AlgoConfig.fetch.dig(:paper_trading, :enabled)
  Rails.logger.info(
    "[Orders] Using #{gateway.class.name} (paper_trading.enabled=#{paper}; " \
    "set LIVE_TRADING=true for live broker execution)"
  )
end
