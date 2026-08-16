# frozen_string_literal: true

module Orders
  # Centralizes gateway creation so paper vs live selection lives in one place.
  # Use GatewayFactory.build in initializers and when a fresh gateway is needed (e.g. tests).
  class GatewayFactory
    class << self
      # @param paper_mode [Boolean, nil] When nil, derived from AlgoConfig paper_trading.enabled
      # @return [Orders::Gateway]
      def build(paper_mode: nil)
        use_paper = paper_mode.nil? ? paper_mode_from_config : paper_mode
        use_paper ? Orders::GatewayPaper.new : Orders::GatewayLive.new
      end

      def selected_gateway
        Orders.config&.gateway || build
      end

      private

      def paper_mode_from_config
        AlgoConfig.fetch.dig(:paper_trading, :enabled) == true
      rescue StandardError
        true
      end
    end
  end
end
