# frozen_string_literal: true

module Orders
  # Decides if an order adjustment is necessary based on analyzed recommendations
  class Adjuster
    class << self
      def adjust_sl(tracker:, recommended_sl:, reason:)
        return false if tracker.nil? || !tracker.active?
        return false if recommended_sl.nil? || recommended_sl <= 0

        # Get current SL from ActiveCache
        position_data = Positions::ActiveCache.instance.get_by_tracker_id(tracker.id)
        current_sl = position_data&.sl_price.to_f

        # Only adjust if recommended SL is higher than current SL (only moves upward)
        if recommended_sl > current_sl
          Orders::Executor.update_sl(tracker: tracker, sl_price: recommended_sl, reason: reason)
          true
        else
          false
        end
      end
    end
  end
end
