# frozen_string_literal: true

module Research
  class FeatureImportance
    # Computes Pearson Correlation Coefficients between trade features and option MFE %.
    # @param trades [Array<Hash>] List of trades
    # @param strike_label [String] Option strike
    # @return [Hash] Feature correlations sorted by absolute strength
    def self.analyze(trades, strike_label: "ATM")
      return {} if trades.size <= 1

      # Outcome variable: ATM Option MFE %
      mfe_vals = trades.map { |t| t[:strikes][strike_label][:mfe_pct] }

      # Feature extraction mappings
      features = {
        gap_pct: ->(t) { t[:gap_pct] },
        or_width: ->(t) { t[:or_width] },
        atr: ->(t) { t[:atr] },
        adx: ->(t) { t[:adx] },
        rsi: ->(t) { t[:rsi] },
        vwap_dist: ->(t) { t[:vwap_dist] },
        first_candle_body_ratio: ->(t) { t[:first_candle_body_ratio] },
        first_candle_volume: ->(t) { t[:first_candle_volume] },
        ignition_velocity: ->(t) { t[:ignition] ? t[:ignition][:ignition_velocity] : 0.0 }
      }

      correlations = {}

      features.each do |name, extractor|
        x_vals = trades.map { |t| extractor.call(t) || 0.0 }
        
        # Pearson Correlation
        r = pearson_correlation(x_vals, mfe_vals)
        correlations[name] = r.nan? ? 0.0 : r.round(4)
      end

      # Sort by absolute correlation strength descending
      correlations.sort_by { |_, r| -r.abs }.to_h
    end

    private

    def self.pearson_correlation(x, y)
      n = x.size
      return 0.0 if n.zero?

      sum_x = x.sum
      sum_y = y.sum

      sum_xx = x.map { |val| val**2 }.sum
      sum_yy = y.map { |val| val**2 }.sum
      sum_xy = x.zip(y).map { |val_x, val_y| val_x * val_y }.sum

      numerator = (n * sum_xy) - (sum_x * sum_y)
      denominator = Math.sqrt(((n * sum_xx) - (sum_x**2)) * ((n * sum_yy) - (sum_y**2)))

      return 0.0 if denominator.zero?

      numerator / denominator
    end
  end
end
