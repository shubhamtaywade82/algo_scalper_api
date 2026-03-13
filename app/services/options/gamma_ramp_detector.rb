# frozen_string_literal: true

module Options
  # Detects Gamma Ramps (OI clusters near spot price) for explosive option moves
  class GammaRampDetector
    attr_reader :chain_data, :index_key, :expiry_date, :spot_price

    def initialize(index_key:, expiry_date:, chain_data:)
      @index_key = index_key.to_s.upcase
      @expiry_date = expiry_date
      @chain_data = chain_data
      @spot_price = chain_data[:last_price].to_f
    end

    # Identifies the strike with the strongest gamma ramp potential
    # @return [Hash, nil]
    def ramp_strike(direction:)
      return nil unless @chain_data && @chain_data[:oc] && @spot_price.positive?

      type = direction == :bullish ? 'ce' : 'pe'
      
      # 1. Find strike with Max OI (OI cluster)
      # Focus only on the requested side
      strikes_data = @chain_data[:oc].map do |strike, data|
        option = data[type]
        next nil unless option
        { strike: strike.to_f, oi: option['oi'].to_i, volume: option['volume'].to_i, data: option }
      end.compact

      return nil if strikes_data.empty?

      # Find OI peak
      oi_peak = strikes_data.max_by { |s| s[:oi] }
      return nil unless oi_peak && oi_peak[:oi].positive?

      # 2. Distance check (Price approaching cluster)
      distance = (spot_price - oi_peak[:strike]).abs
      
      # Institutional threshold: distance within 100 points for NIFTY/BANKNIFTY/SENSEX
      return nil if distance > 100

      # 3. Volume confirmation (Activity rising)
      # Check if current volume is significant compared to typical (handled by higher level logic or score)
      
      oi_peak
    end

    # Calculates a gamma pressure score for the current index state
    # @return [Float] 0.0 to 1.0+
    def gamma_pressure_score(direction:)
      strike = ramp_strike(direction: direction)
      return 0.0 unless strike

      # Higher score if price is closer to the OI cluster
      distance = (spot_price - strike[:strike]).abs
      proximity_score = [1.0 - (distance / 100.0), 0.0].max
      
      # Higher score if OI is massive
      oi_intensity = [strike[:oi] / 1_000_000.0, 1.0].min # Scale relative to 1M OI
      
      (proximity_score * 0.6) + (oi_intensity * 0.4)
    end
  end
end
