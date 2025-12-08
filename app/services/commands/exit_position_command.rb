# frozen_string_literal: true

module Commands
  # Command for exiting positions
  # Provides audit trail and ensures proper position closure
  class ExitPositionCommand < BaseCommand
    attr_reader :tracker, :exit_reason, :exit_price

    def initialize(tracker:, exit_reason:, exit_price: nil, metadata: {})
      super(metadata: metadata)
      @tracker = tracker
      @exit_reason = exit_reason.to_s
      @exit_price = exit_price
    end

    protected

    def perform_execution
      validate_tracker

      # Get exit price if not provided
      resolved_exit_price = @exit_price || resolve_exit_price

      # Execute exit via gateway
      gateway = Orders.config
      result = gateway.exit_market(@tracker)

      if result && (result == true || result[:success] == true)
        # Mark tracker as exited
        @tracker.mark_exited!(
          exit_price: resolved_exit_price,
          exit_reason: @exit_reason
        )

        # Emit exit event
        Core::EventBus.instance.publish(:exit_triggered, {
          tracker_id: @tracker.id,
          order_no: @tracker.order_no,
          exit_reason: @exit_reason,
          exit_price: resolved_exit_price
        })

        success_result(data: {
          tracker_id: @tracker.id,
          exit_price: resolved_exit_price,
          exit_reason: @exit_reason
        })
      else
        failure_result("Exit failed: #{result.inspect}")
      end
    rescue StandardError => e
      Rails.logger.error("[Commands::ExitPositionCommand] Execution failed: #{e.class} - #{e.message}")
      failure_result(e.message)
    end

    private

    def validate_tracker
      raise ArgumentError, 'Tracker is required' unless @tracker
      raise ArgumentError, 'Tracker already exited' if @tracker.exited?
      raise ArgumentError, 'Tracker must be active' unless @tracker.active?
    end

    def resolve_exit_price
      # Try to get LTP from cache
      ltp = Live::TickCache.ltp(@tracker.segment, @tracker.security_id)
      return BigDecimal(ltp.to_s) if ltp.present?

      # Fallback to entry price (for paper trading)
      @tracker.entry_price || BigDecimal(0)
    end
  end
end
