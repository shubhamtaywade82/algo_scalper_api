# frozen_string_literal: true

Rails.application.config.to_prepare do
  # registry for Orders.config
  module Orders
    class << self
      attr_accessor :config
    end
  end

  gateway = Orders::GatewayFactory.build

  Orders.config = Orders::Config.new(gateway: gateway)

  Rails.logger.info("[Orders] Gateway initialized → #{gateway.class.name}")
end
