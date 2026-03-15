# frozen_string_literal: true

module Orders
  module Commands
    # Places a market exit order for an active position via the gateway.
    #
    # Requires the tracker to be in :active status and a client_order_id
    # for idempotent retry semantics (DhanHQ deduplicates on COID).
    #
    # Usage:
    #   cmd = ExitOrderCommand.new(
    #     gateway:         Orders.config.gateway,
    #     tracker:         tracker,
    #     client_order_id: tracker.exit_coid,
    #     reason:          'stop_loss'
    #   )
    #   result = cmd.call
    #   result.success?              # => true
    #   result.payload[:exit_price]  # => BigDecimal("245.50")
    class ExitOrderCommand < BaseCommand
      def initialize(gateway:, tracker:, client_order_id:, reason: nil, **opts)
        super(gateway: gateway, tracker: tracker, **opts)
        @client_order_id = client_order_id
        @reason          = reason
      end

      protected

      def validate
        base = super
        return base if base

        unless tracker.active?
          return failure('not_active', payload: { status: tracker.status })
        end

        return failure('missing_client_order_id') if @client_order_id.blank?

        nil
      end

      def execute
        response = gateway.exit_market(tracker, client_order_id: @client_order_id)

        if exit_successful?(response)
          success(
            exit_price: response[:exit_price],
            order_id:   response[:order_id],
            paper:      response[:paper],
            reason:     @reason,
            raw:        response
          )
        else
          failure('broker_rejected', payload: { raw: response })
        end
      end

      private

      def exit_successful?(response)
        response.is_a?(Hash) && (response[:success] || response[:paper])
      end
    end
  end
end
