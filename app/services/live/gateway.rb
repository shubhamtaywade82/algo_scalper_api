# frozen_string_literal: true

# @deprecated Use Orders::GatewayLive for live trading. This class delegates to GatewayLive
#   and exists only for backward compatibility. Live orders use Orders::GatewayLive only.
#   See config/initializers/orders_gateway.rb and docs/architecture/design_pattern_improvements.md.
module Live
  class Gateway < Orders::Gateway
    delegate :place_market, :exit_market, :flat_position, :position, :cancel_order, :wallet_snapshot, to: :@delegate

    def initialize
      @delegate = Orders::GatewayLive.new
      Rails.logger.warn('[Live::Gateway] DEPRECATED: Use Orders::GatewayLive. Live::Gateway will be removed in a future release.')
    end
  end
end
