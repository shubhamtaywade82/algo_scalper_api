# frozen_string_literal: true

module OptionsBuying
  # Detects high-OI concentration strikes (Gamma Walls) to avoid trading into them.
  class GammaWallDetector
    def initialize(index_key)
      @index_key = index_key.to_s.upcase
    end

    def walls
      analyzer = Options::DerivativeChainAnalyzer.new(index_key: @index_key)
      spot = analyzer.spot_ltp
      return { ce: nil, pe: nil } unless spot&.positive?

      # Get top 50 candidates in both directions to find walls
      ce_candidates = analyzer.select_candidates(limit: 50, direction: :bullish).select { |c| c[:type] == 'CE' }
      pe_candidates = analyzer.select_candidates(limit: 50, direction: :bearish).select { |c| c[:type] == 'PE' }

      {
        ce: find_wall(ce_candidates),
        pe: find_wall(pe_candidates)
      }
    end

    # Returns false if spot is within the buffer percentage of a gamma wall in the trade direction
    def safe_to_enter?(spot_price, direction)
      return true unless spot_price&.positive?

      current_walls = walls
      wall = direction == :bullish ? current_walls[:ce] : current_walls[:pe]
      return true unless wall

      buffer = spot_price * buffer_pct

      if direction == :bullish
        # Spot shouldn't be too close BELOW the CE wall
        # Example: CE wall at 45000. Spot 44900 -> buffer 225. (45000 - 44900) = 100 < 225 => UNSAFE
        distance = wall - spot_price
        distance.positive? ? distance > buffer : true
      else
        # Spot shouldn't be too close ABOVE the PE wall
        distance = spot_price - wall
        distance.positive? ? distance > buffer : true
      end
    end

    private

    def config
      Mode.config[:gamma_wall] || {}
    end

    def oi_multiplier
      (config[:oi_multiplier] || 2.0).to_f
    end

    def buffer_pct
      (config[:buffer_pct] || 0.005).to_f
    end

    def find_wall(candidates)
      with_oi = candidates.select { |c| c[:oi].to_i.positive? }
      return nil if with_oi.empty?

      median_oi = calculate_median(with_oi.map { |c| c[:oi].to_i })
      wall_threshold = median_oi * oi_multiplier

      # Find strikes with OI > threshold, then pick the one nearest to spot
      walls = with_oi.select { |c| c[:oi].to_i >= wall_threshold }
      return nil if walls.empty?

      # Find max OI among the valid walls
      max_oi_candidate = walls.max_by { |c| c[:oi].to_i }
      max_oi_candidate[:strike].to_f
    end

    def calculate_median(array)
      sorted = array.sort
      len = sorted.length
      (sorted[(len - 1) / 2] + sorted[len / 2]) / 2.0
    end
  end
end
