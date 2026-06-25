# frozen_string_literal: true

module Optimization
  class TradeAnalyzer
    class << self
      def call(tracker)
        return unless tracker.exited?
        return if tracker.trade_analytic.present?

        entry_price = tracker.entry_price.to_f
        exit_price = tracker.exit_price.to_f
        highest_price = tracker.highest_price.to_f
        lowest_price = tracker.lowest_price.to_f

        # Fallbacks if highest/lowest were not captured (e.g. fast exit)
        highest_price = [entry_price, exit_price, highest_price].max
        lowest_price = lowest_price.positive? ? [entry_price, exit_price, lowest_price].min : [entry_price, exit_price].min

        mfe = highest_price - entry_price
        mae = lowest_price - entry_price

        duration = if tracker.exited_at && tracker.created_at
                     (tracker.exited_at - tracker.created_at).to_i
                   else
                     0
                   end

        TradeAnalytic.create!(
          position_tracker: tracker,
          symbol: tracker.symbol,
          entry_price: entry_price,
          exit_price: exit_price,
          max_favorable_excursion: mfe,
          max_adverse_excursion: mae,
          duration_seconds: duration,
          strategy: tracker.entry_strategy,
          exit_reason: tracker.exit_reason,
          volatility: calculate_volatility(tracker)
        )
      rescue StandardError => e
        Rails.logger.error("[TradeAnalyzer] Failed to analyze trade #{tracker.id}: #{e.message}")
      end

      private

      def calculate_volatility(tracker)
        # Placeholder for actual volatility calculation if needed
        # Could use ATR of the underlying at entry time
        0.0
      end
    end
  end
end
