# frozen_string_literal: true

Rails.application.config.to_prepare do
  module Orders
    class << self
      attr_accessor :config
    end
  end

  paper_enabled =
    begin
      AlgoConfig.fetch.dig(:paper_trading, :enabled) == true
    rescue
      true
    end

  gateway = if paper_enabled
              Orders::GatewayPaper.new
            else
              Orders::GatewayLive.new
            end

  # Set structured config, not raw gateway
  Orders.config = Orders::Config.new(gateway: gateway)

  Rails.logger.info("[Orders] Using #{gateway.class.name}")
end
