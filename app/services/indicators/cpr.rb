# frozen_string_literal: true

module Indicators
  class Cpr < ApplicationService
    attr_reader :high, :low, :close, :narrow_threshold, :wide_threshold

    def initialize(high:, low:, close:, narrow_threshold: nil, wide_threshold: nil)
      @high = high.to_f
      @low = low.to_f
      @close = close.to_f
      @narrow_threshold = narrow_threshold || ENV.fetch('CPR_NARROW_THRESHOLD', '0.25').to_f
      @wide_threshold = wide_threshold || ENV.fetch('CPR_WIDE_THRESHOLD', '0.60').to_f
    end

    def call
      pivot = ((high + low + close) / 3.0).round(2)
      bc = ((high + low) / 2.0).round(2)
      tc = ((2.0 * pivot) - bc).round(2)

      top_central = [tc, bc].max.round(2)
      bottom_central = [tc, bc].min.round(2)
      width = (top_central - bottom_central).round(2)
      width_pct = pivot.positive? ? ((width / pivot) * 100.0).round(4) : 0.0

      width_type = if width_pct < narrow_threshold
                     :narrow
                   elsif width_pct > wide_threshold
                     :wide
                   else
                     :normal
                   end

      {
        pivot: pivot,
        top_central: top_central,
        bottom_central: bottom_central,
        width: width,
        width_pct: width_pct,
        width_type: width_type
      }
    end
  end
end
