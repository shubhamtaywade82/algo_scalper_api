# frozen_string_literal: true

module Entries
  module Guards
    # Selling requires SPAN + exposure margin (5-20x the premium), not just the
    # premium itself — this fails fast if even a single lot wouldn't fit the
    # configured margin budget. try_enter still caps the final lot count against
    # the same budget once quantity is known (this guard runs before sizing).
    class MarginLimitGuard
      class << self
        include BaseGuard

        DEFAULT_MAX_MARGIN_USAGE_PCT = 50.0

        def call(context)
          return PASS unless context[:position_side].to_s == 'short'

          pick = context[:pick]
          index_cfg = context[:index_cfg]
          lot_size = pick[:lot_size] || Trading::LotCalculator.lot_size_for(index_cfg[:key].to_s.upcase)
          price = pick[:ltp] || context[:ltp]
          return PASS unless lot_size.to_i.positive? && price.to_f.positive?

          margin_for_one_lot = margin_adapter.margin_for(
            segment: pick[:segment] || index_cfg[:segment],
            security_id: pick[:security_id],
            quantity: lot_size.to_i,
            price: price
          )
          return PASS if margin_for_one_lot.nil? # margin API unavailable — fail open, sizing cap still applies later

          budget = max_margin_budget
          if margin_for_one_lot > budget
            { blocked: "margin: 1 lot needs ₹#{margin_for_one_lot.to_f.round}, budget is ₹#{budget.to_f.round}" }
          else
            PASS
          end
        rescue StandardError => e
          Rails.logger.warn("[MarginLimitGuard] Error: #{e.class} - #{e.message}")
          PASS
        end

        def margin_adapter
          @margin_adapter ||= Adapters::Margin::DhanMarginAdapter.new
        end

        def max_margin_budget
          used = current_margin_used
          available = Capital::Allocator.available_cash
          (available * BigDecimal(max_usage_pct.to_s) / 100) - used
        end

        private

        def config
          AlgoConfig.fetch.dig(:risk, :margin_limit_guard) || {}
        rescue StandardError
          {}
        end

        def max_usage_pct
          (config[:max_margin_usage_pct] || DEFAULT_MAX_MARGIN_USAGE_PCT).to_f
        end

        def current_margin_used
          PositionTracker.where(status: %w[active trailing], position_side: 'short').sum(:margin_required)
        end
      end
    end
  end
end
