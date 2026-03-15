# frozen_string_literal: true

module Orders
  module Commands
    # Cancels a pending or open broker order.
    #
    # Used when an entry order is placed but the position has not yet been
    # activated (e.g. DhanHQ order is pending and we want to cancel before fill).
    #
    # Usage:
    #   cmd = CancelOrderCommand.new(
    #     gateway:  Orders.config.gateway,
    #     tracker:  tracker,
    #     order_id: tracker.order_no
    #   )
    #   result = cmd.call
    #   result.success?  # => true
    class CancelOrderCommand < BaseCommand
      def initialize(gateway:, tracker:, order_id:, **opts)
        super(gateway: gateway, tracker: tracker, **opts)
        @order_id = order_id
      end

      protected

      def validate
        base = super
        return base if base

        return failure('missing_order_id') if @order_id.blank?

        nil
      end

      def execute
        response = gateway.cancel_order(@order_id)

        if response.is_a?(Hash) && response[:success]
          success(order_id: @order_id, raw: response)
        else
          failure('cancel_rejected', payload: { order_id: @order_id, raw: response })
        end
      end
    end
  end
end
