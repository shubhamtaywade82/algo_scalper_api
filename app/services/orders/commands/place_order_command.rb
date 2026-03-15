# frozen_string_literal: true

module Orders
  module Commands
    # Places a market entry order via the configured gateway.
    #
    # Encapsulates the side / segment / security_id / quantity parameters
    # so the caller doesn't need to know the gateway's method signature.
    # All input validation happens in #validate before the broker call.
    #
    # Usage:
    #   cmd = PlaceOrderCommand.new(
    #     gateway:     Orders.config.gateway,
    #     tracker:     tracker,
    #     side:        :buy,
    #     segment:     'NSE_FNO',
    #     security_id: '12345',
    #     quantity:    50,
    #     meta:        { index_key: 'NIFTY' }
    #   )
    #   result = cmd.call
    #   result.success?              # => true
    #   result.payload[:order_id]    # => "DHAN123"
    class PlaceOrderCommand < BaseCommand
      VALID_SIDES = %w[buy sell BUY SELL].freeze

      def initialize(gateway:, tracker:, side:, segment:, security_id:, quantity:, meta: {}, **opts)
        super(gateway: gateway, tracker: tracker, **opts)
        @side        = side.to_s
        @segment     = segment
        @security_id = security_id
        @quantity    = quantity.to_i
        @meta        = meta || {}
      end

      protected

      def validate
        base = super
        return base if base

        return failure('invalid_side', payload: { side: @side }) unless VALID_SIDES.include?(@side)
        return failure('missing_segment') if @segment.blank?
        return failure('missing_security_id') if @security_id.blank?
        return failure('invalid_quantity', payload: { quantity: @quantity }) unless @quantity.positive?

        nil
      end

      def execute
        response = gateway.place_market(
          @side.upcase,
          @segment,
          @security_id,
          @quantity,
          @meta
        )

        if response.is_a?(Hash) && response[:success]
          success(
            order_id: response[:order_id],
            paper:    response[:paper],
            raw:      response
          )
        else
          failure('broker_rejected', payload: { raw: response })
        end
      end
    end
  end
end
