# frozen_string_literal: true

module Options
  # Detects rapid expansion in option premiums relative to index moves
  # Formula: delta_acceleration = (option_return) / (index_return)
  class DeltaAccelerationDetector
    def initialize(index_prices:, option_prices:, volumes:, oi:)
      @index_prices = Array(index_prices).map(&:to_f)
      @option_prices = Array(option_prices).map(&:to_f)
      @volumes = Array(volumes).map(&:to_f)
      @oi_history = Array(oi).map(&:to_f)
    end

    def signal
      return :none unless enough_data?

      ratio = delta_ratio
      vol_ratio = volume_ratio

      # Professional Thresholds:
      # ratio > 12: Very strong acceleration
      # ratio > 8: Moderate acceleration
      # vol_ratio > 1.5: High volume participation

      if ratio > 12 && vol_ratio > 1.5 && oi_rising?
        :strong
      elsif ratio > 8 && vol_ratio > 1.5 && oi_rising?
        :moderate
      else
        :none
      end
    end

    def delta_ratio
      return 0.0 unless enough_data?

      # Calculate returns between last two points
      idx_ret = (@index_prices[-1] - @index_prices[-2]) / @index_prices[-2]
      opt_ret = (@option_prices[-1] - @option_prices[-2]) / @option_prices[-2]

      # Handle flat index moves (prevent division by zero)
      return 0.0 if idx_ret.abs < 0.0001

      # Directional check: acceleration only counts if both move in same direction
      # (Buying calls on index up move, or puts on index down move)
      return 0.0 if (idx_ret * opt_ret).negative?

      (opt_ret / idx_ret).abs
    end

    private

    def enough_data?
      @index_prices.size >= 2 && @option_prices.size >= 2 && @volumes.any? && @oi_history.size >= 2
    end

    def volume_ratio
      return 1.0 if @volumes.empty?

      # Use last 20 for average, compare current to average
      avg = @volumes.last(20).sum / @volumes.last(20).size.to_f
      return 1.0 if avg.zero?

      @volumes.last / avg
    end

    def oi_rising?
      @oi_history[-1] > @oi_history[-2]
    end
  end
end
