# frozen_string_literal: true

module Research
  # Classifies option premium price paths (09:15 to 09:30 IST) into distinct
  # behavioral regimes (e.g. Straight Expansion, Spike and Decay, Post-Open Collapse,
  # Compression, Whipsaw) to study market dynamics beyond binary win/loss targets.
  class PremiumTaxonomyClassifier
    # Classifies a 15-minute option premium series.
    # @param option_candles [Array<Hash>] 1-min option candles for the first 15m (09:15 to 09:30)
    # @param mfe_pct [Float] Maximum Favorable Excursion %
    # @param mae_pct [Float] Maximum Adverse Excursion %
    # @return [Symbol] The classified pattern: :straight_expansion, :spike_and_decay, :post_open_collapse, :whipsaw, :compression, :neutral
    def self.classify(option_candles, mfe_pct, mae_pct)
      return :neutral if option_candles.blank? || option_candles.size < 2

      entry_price = option_candles.first[:open].to_f
      return :neutral if entry_price <= 0

      # Find peak price and index in the 15-candle series
      peak_price = entry_price
      peak_idx = 0
      option_candles.each_with_index do |c, i|
        if c[:high].to_f > peak_price
          peak_price = c[:high].to_f
          peak_idx = i
        end
      end

      # Calculate drawdown after the peak and end-of-period return
      lowest_post_peak = option_candles[peak_idx..].map { |c| c[:low].to_f }.min || peak_price
      drawdown_from_peak = peak_price.positive? ? ((peak_price - lowest_post_peak) / peak_price) * 100.0 : 0.0
      end_price = option_candles.last[:close].to_f
      end_return = ((end_price - entry_price) / entry_price) * 100.0

      # Apply taxonomy criteria
      if mfe_pct >= 40.0 && drawdown_from_peak < 20.0 && peak_idx >= 10
        :straight_expansion # Pattern A: Strong late expansion with low retrace
      elsif mfe_pct >= 40.0 && drawdown_from_peak >= 30.0 && peak_idx <= 5 && end_return <= -20.0
        :spike_and_decay # Pattern B: Fast early spike followed by heavy decay
      elsif mfe_pct >= 30.0 && mae_pct <= -25.0
        :whipsaw # Pattern E: High volatility in both directions
      elsif peak_idx.zero? && end_return < -30.0
        :post_open_collapse # Pattern C: Opening price is the peak, then collapses
      elsif mfe_pct < 20.0 && mae_pct > -20.0
        :compression # Pattern D: Stagnant premium range
      else
        :neutral
      end
    end
  end
end
