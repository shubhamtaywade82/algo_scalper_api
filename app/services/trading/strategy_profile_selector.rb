# frozen_string_literal: true

module Trading
  # Maps composed regime snapshot to a frozen strategy profile for the position lifecycle.
  # Profiles drive trailing/risk tuning via tracker.meta — never switch mid-trade.
  class StrategyProfileSelector
    PROFILES = %i[
      trend_aggressive
      trend_controlled
      range_stand_down
      stand_down
    ].freeze

    def self.select(snapshot)
      snap = snapshot
      return :stand_down unless snap

      case snap.structure
      when :bullish_trend, :bearish_trend
        aggressive_floor = profile_threshold(:aggressive_min_score, 80)
        controlled_floor = profile_threshold(:controlled_min_score, 60)

        if snap.conviction_score >= aggressive_floor && snap.strength == :strong
          :trend_aggressive
        elsif snap.conviction_score >= controlled_floor
          :trend_controlled
        else
          :stand_down
        end
      when :range, :chop
        :range_stand_down
      else
        :stand_down
      end
    end

    def self.profile_threshold(key, default)
      v = AlgoConfig.fetch.dig(:market_context, :strategy_profiles, key)
      v.nil? ? default : v.to_i
    rescue StandardError
      default
    end
  end
end
