# frozen_string_literal: true

# Bind Orders.config to the appropriate gateway based on execution mode
Rails.application.config.to_prepare do
  Orders.config = if ExecutionMode.paper?
                   Paper::GatewayV2.new
                  else
                    Live::Gateway.new
                  end
end

# Define Orders.config accessor
module Orders
  class << self
    attr_accessor :config
  end
end

