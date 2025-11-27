# frozen_string_literal: true

module Commands
  # Command for placing market orders
  # Provides audit trail, retry logic, and order tracking
  class PlaceMarketOrderCommand < BaseCommand
    attr_reader :side, :segment, :security_id, :qty, :client_order_id, :product_type, :order_response

    def initialize(side:, segment:, security_id:, qty:, client_order_id: nil, product_type: 'INTRADAY', metadata: {})
      super(metadata: metadata)
      @side = side.to_s.upcase
      @segment = segment.to_s
      @security_id = security_id.to_s
      @qty = qty.to_i
      @client_order_id = client_order_id || generate_client_order_id
      @product_type = product_type.to_s
      @order_response = nil
      @order_id = nil
    end

    def undoable?
      true # Orders can potentially be cancelled
    end

    protected

    def perform_execution
      validate_parameters

      result = case @side
               when 'BUY'
                 place_buy_order
               when 'SELL'
                 place_sell_order
               else
                 return failure_result("Invalid side: #{@side}")
               end

      if result[:success]
        @order_response = result[:data]
        @order_id = extract_order_id(result[:data])
        success_result(data: result[:data])
      else
        result
      end
    rescue StandardError => e
      Rails.logger.error("[Commands::PlaceMarketOrderCommand] Execution failed: #{e.class} - #{e.message}")
      failure_result(e.message)
    end

    def perform_undo
      return failure_result('No order ID to cancel') unless @order_id

      # Attempt to cancel the order
      # Note: DhanHQ may not support cancellation for filled orders
      cancel_result = cancel_order(@order_id)

      if cancel_result[:success]
        success_result(data: { cancelled_order_id: @order_id })
      else
        failure_result("Failed to cancel order: #{cancel_result[:error]}")
      end
    rescue StandardError => e
      Rails.logger.error("[Commands::PlaceMarketOrderCommand] Undo failed: #{e.class} - #{e.message}")
      failure_result(e.message)
    end

    private

    def validate_parameters
      unless Orders::Placer::VALID_TRADABLE_SEGMENTS.include?(@segment)
        raise ArgumentError, "Invalid segment: #{@segment}"
      end

      raise ArgumentError, 'Quantity must be positive' unless @qty.positive?
      raise ArgumentError, 'Security ID is required' if @security_id.blank?
    end

    def place_buy_order
      order = Orders::Placer.buy_market!(
        seg: @segment,
        sid: @security_id,
        qty: @qty,
        client_order_id: @client_order_id,
        product_type: @product_type
      )

      if order
        success_result(data: { order: order, order_id: extract_order_id(order) })
      else
        failure_result('Order placement returned nil')
      end
    end

    def place_sell_order
      order = Orders::Placer.sell_market!(
        seg: @segment,
        sid: @security_id,
        qty: @qty,
        client_order_id: @client_order_id
      )

      if order
        success_result(data: { order: order, order_id: extract_order_id(order) })
      else
        failure_result('Order placement returned nil')
      end
    end

    def cancel_order(order_id)
      # Placeholder for order cancellation
      # Would need to implement DhanHQ order cancellation API
      Rails.logger.warn("[Commands::PlaceMarketOrderCommand] Order cancellation not yet implemented for order #{order_id}")
      failure_result('Order cancellation not implemented')
    end

    def extract_order_id(order_response)
      return nil unless order_response

      if order_response.respond_to?(:order_id)
        order_response.order_id
      elsif order_response.is_a?(Hash)
        order_response[:order_id] || order_response['order_id'] || order_response[:order_no] || order_response['order_no']
      elsif order_response.respond_to?(:[])
        order_response[:order_id] || order_response[:order_no] || order_response.order_id
      end
    end

    def generate_client_order_id
      timestamp = Time.current.to_i.to_s[-6..]
      "CMD-#{@side[0..2]}-#{@security_id}-#{timestamp}"
    end
  end
end
