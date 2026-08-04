# frozen_string_literal: true

Rails.application.config.to_prepare do
  # registry for Orders.config
  module Orders
    class << self
      attr_accessor :config
    end
  end

  paper_mode =
    begin
      AlgoConfig.fetch.dig(:paper_trading, :enabled)
    rescue StandardError
      true
    end

  gateway =
    if paper_mode
      Orders::GatewayPaper.new
    else
      Orders::GatewayLive.new
    end

  Orders.config = Orders::Config.new(gateway: gateway)

  Rails.logger.info("[Orders] Gateway initialized → #{gateway.class.name}")
end
