# frozen_string_literal: true

# Bind Orders.config to Live::Gateway for live trading
Rails.application.config.to_prepare do
  Orders.config = Live::Gateway.new
end

# Define Orders.config accessor
module Orders
  class << self
    attr_accessor :config
  end
end

