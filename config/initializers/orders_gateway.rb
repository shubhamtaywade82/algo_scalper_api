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

  Rails.logger.info("[Orders] Using #{gateway.class.name}")
end
