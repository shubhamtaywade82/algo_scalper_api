# frozen_string_literal: true

module Orders
  class AdaptiveTrailing
    TRAILS = {
      low: 0.15,
      normal: 0.25,
      high: 0.35
    }.freeze

    def initialize(highest:, regime:)
      @highest = highest.to_f
      @regime = regime || :normal
    end

    def stop
      trail_pct = TRAILS[@regime] || TRAILS[:normal]
      (@highest * (1 - trail_pct)).round(2)
    end
  end
end
