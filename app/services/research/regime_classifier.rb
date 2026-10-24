# frozen_string_literal: true

module Research
  class RegimeClassifier
    # Classifies the market regime for a day.
    # @param day_data [Hash] Pre-computed day features
    # @return [Hash] Dictionary of market regime flags
    def self.classify(day_data)
      # 1. Volatility Regime (Proxy using ATR % of index price at open)
      vol_regime = :normal
      atr = day_data[:atr]
      open_price = day_data[:underlying_candles]&.first&.[](:open) || 25_000.0

      if atr && open_price.positive?
        atr_pct = (atr / open_price) * 100.0
        if atr_pct > 1.0
          vol_regime = :high_volatility
        elsif atr_pct < 0.5
          vol_regime = :low_volatility
        end
      end

      # 2. Expiry Proximity Regime
      # Thursdays are expiry days (4)
      days_to_expiry = day_data[:days_to_expiry] || 4
      expiry_regime = days_to_expiry <= 1 ? :near_expiry : :far_expiry

      # 3. Gap Regime
      gap_pct = day_data[:gap_pct] || 0.0
      gap_regime = gap_pct.abs > 0.4 ? :large_gap : :small_gap

      # 4. Trend Regime (using previous day direction and close position)
      trend_regime = :mean_reverting
      prev_close = day_data[:prev_day_close]
      prev_high = day_data[:prev_day_high]
      prev_low = day_data[:prev_day_low]

      if prev_close && prev_high && prev_low && (prev_high - prev_low).positive?
        # If prev close was near the extremes, yesterday was trending
        close_pct_range = (prev_close - prev_low) / (prev_high - prev_low)
        if close_pct_range > 0.8 || close_pct_range < 0.2
          trend_regime = :trending
        end
      end

      {
        volatility: vol_regime,
        expiry: expiry_regime,
        gap: gap_regime,
        trend: trend_regime
      }
    end
  end
end
