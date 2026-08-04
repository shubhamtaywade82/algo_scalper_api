# frozen_string_literal: true

module Orders
  # Slicer splits large orders into smaller slices based on index exchange freeze limits.
  class Slicer
    DEFAULT_FREEZE_LIMIT = 1800 # default NSE freeze quantity

    class << self
      def slice_quantity(index_key:, total_quantity:)
        qty = total_quantity.to_i
        return [] if qty <= 0

        limit = freeze_limit_for(index_key)
        return [qty] if qty <= limit || !enabled?

        slices = []
        while qty.positive?
          slice_qty = [qty, limit].min
          slices << slice_qty
          qty -= slice_qty
        end
        slices
      end

      def enabled?
        config[:enabled] != false
      end

      def delay_seconds
        ((config[:delay_ms] || 500).to_f / 1000.0).clamp(0.0, 5.0)
      end

      def freeze_limit_for(index_key)
        limits = config[:freeze_limits] || {}
        limit = limits[index_key.to_s.upcase] || limits[:default] || DEFAULT_FREEZE_LIMIT
        limit.to_i
      end

      private

      def config
        AlgoConfig.fetch.dig(:options_buying, :execution, :order_slicing) || {}
      rescue StandardError
        {}
      end
    end
  end
end
