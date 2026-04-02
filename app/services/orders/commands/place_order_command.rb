# frozen_string_literal: true

module Orders
  module Commands
    # Places a market entry order via the configured gateway.
    #
    # Encapsulates all placement parameters and validates them before touching
    # the broker. No tracker is required at call time — the tracker is created
    # by EntryGuard AFTER the order is successfully placed.
    #
    # Keyword args match the gateway interface exactly:
    #   gateway.place_market(side:, segment:, security_id:, qty:, meta: {})
    #
    # Usage:
    #   result = PlaceOrderCommand.new(
    #     gateway:     Orders.config.gateway,
    #     side:        :buy,
    #     segment:     'NSE_FNO',
    #     security_id: '12345',
    #     qty:         50,
    #     meta:        { client_order_id: '...', ltp: 245.5, symbol: 'NIFTY26JAN245CE' }
    #   ).call
    #   result.success?              # => true
    #   result.payload[:order_id]    # => "DHAN123"
    class PlaceOrderCommand < BaseCommand
      VALID_SIDES = %w[buy sell BUY SELL].freeze

      # tracker is optional here — it does not exist yet at placement time
      def initialize(gateway:, side:, segment:, security_id:, qty:, meta: {}, tracker: nil, **)
        super(gateway: gateway, tracker: tracker, **)
        @side        = side.to_s
        @segment     = segment
        @security_id = security_id
        @qty         = SafeNumeric.to_non_negative_integer(qty)
        @meta        = meta || {}
      end

      protected

      def validate
        return failure('missing_gateway') unless gateway

        return failure('invalid_side', payload: { side: @side }) unless VALID_SIDES.include?(@side)
        return failure('missing_segment') if @segment.blank?
        return failure('missing_security_id') if @security_id.blank?
        return failure('invalid_quantity', payload: { qty: @qty }) unless @qty.positive?

        nil
      end

      def execute
        response = gateway.place_market(
          side: @side.upcase,
          segment: @segment,
          security_id: @security_id,
          qty: @qty,
          meta: @meta
        )

        if response.is_a?(Hash) && (response[:success] || response[:paper])
          success(
            order_id: response[:order_id],
            paper: response[:paper],
            raw: response
          )
        else
          failure('broker_rejected', payload: { raw: response })
        end
      end
    end
  end
end
