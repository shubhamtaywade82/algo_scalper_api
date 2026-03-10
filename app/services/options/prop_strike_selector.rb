# frozen_string_literal: true

module Options
  # Professional strike-selection model used by prop traders
  # Optimizes for convexity, liquidity, and institutional flow
  # Refined to match exact institutional variable weights
  class PropStrikeSelector
    MAX_DISTANCE_PCT = 0.01 # 1% distance from spot max

    def initialize(spot:)
      @spot = spot.to_f
    end

    # Scores a candidate strike based on professional variables
    # @param option [Hash] Candidate option data
    # @param flow_score [Float] Score from FlowAnalyzer
    # @param gamma_pressure [Float] Score from GammaRampDetector
    # @param history [Hash] Historical stats (avg_volume, avg_oi) from FlowAnalyzer
    # @return [Float] Total institutional score (0.0 to 1.0+)
    def score(option, flow_score: 1.0, gamma_pressure: 0.0, history: nil)
      return 0.0 if @spot.zero? || option[:ltp].to_f.zero?

      # 1. Delta Score (0.35 weight)
      d_score = delta_score(option[:delta])
      
      # 2. Liquidity Score (0.30 weight)
      l_score = liquidity_score(option, history)
      
      # 3. Distance Score (0.20 weight)
      dist_score = distance_score(option[:strike])
      
      # 4. Flow Score (0.15 weight)
      f_score = flow_score_normalized(flow_score)

      # Professional Strike Score Formula
      base_score = (d_score * 0.35) +
                   (l_score * 0.30) +
                   (dist_score * 0.20) +
                   (f_score * 0.15)

      # Apply Gamma Ramp Multiplier for explosive potential
      base_score * (1.0 + (gamma_pressure * 0.5))
    end

    private

    def delta_score(delta)
      return 0.0 unless delta
      # delta_score = 1 - abs(delta - 0.5) -> Optimal at 0.50 delta
      1.0 - (delta.to_f.abs - 0.5).abs
    end

    def liquidity_score(option, history)
      avg_vol = history&.dig(:avg_volume)&.to_f || option[:volume].to_f
      avg_oi = history&.dig(:avg_oi)&.to_f || option[:oi].to_f
      
      # Ratio calculation as per institutional model
      volume_ratio = avg_vol.positive? ? option[:volume].to_f / avg_vol : 1.0
      oi_ratio = avg_oi.positive? ? option[:oi].to_f / avg_oi : 1.0
      
      # Normalize ratios (cap at 2.0 to prevent outlier dominance)
      v_score = [volume_ratio / 2.0, 1.0].min
      o_score = [oi_ratio / 2.0, 1.0].min
      
      # spread_score = 1 - s.spread
      spread = option[:spread].to_f
      s_score = [1.0 - (spread * 10.0), 0.0].max # High penalty for > 10% spread

      # liquidity_score = volume_ratio * 0.5 + oi_ratio * 0.3 + spread_score * 0.2
      (v_score * 0.5) + (o_score * 0.3) + (s_score * 0.2)
    end

    def distance_score(strike)
      distance = (strike.to_f - @spot).abs / @spot
      return 0.0 if distance > MAX_DISTANCE_PCT

      # distance_score = 1 - (distance_from_spot / max_distance)
      1.0 - (distance / MAX_DISTANCE_PCT)
    end

    def flow_score_normalized(flow_score)
      # Normalize flow score around 1.0
      [[flow_score / 2.0, 1.0].min, 0.0].max
    end
  end
end
