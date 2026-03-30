# frozen_string_literal: true

module Indicators
  # ML Adaptive SuperTrend [nemesis]
  # Based on Pine Script v6 Indicator by shubhamtaywade82
  #
  # This indicator adaptively adjusts the SuperTrend multiplier by clustering
  # volatility (ATR) into three regimes: High, Medium, and Low.
  class MlAdaptiveSupertrend < ApplicationService
    attr_reader :series, :atr_len, :factor, :training_period, :p_high, :p_mid, :p_low

    def initialize(series:, config: {})
      @series = series
      # Map config keys from user provided ones if available
      @atr_len = (config[:atr_len] || 10).to_i
      @factor = (config[:factor] || 1.0).to_f
      @training_period = (config[:training_period] || 100).to_i

      # Volatility percentiles
      @p_high = (config[:highvol] || 0.75).to_f
      @p_mid = (config[:midvol] || 0.5).to_f
      @p_low = (config[:lowvol] || 0.25).to_f
    end

    def call
      highs = extract_series(:high)
      lows = extract_series(:low)
      closes = extract_series(:close)

      return empty_result if highs.empty? || lows.empty? || closes.empty?

      size = closes.size
      atr = calculate_rma_atr(highs, lows, closes, atr_len)

      # Adaptive clustering
      upper_vol = rolling_highest(atr, training_period)
      lower_vol = rolling_lowest(atr, training_period)

      # Results arrays
      super_trend = Array.new(size)
      direction = Array.new(size) # -1 Bullish, 1 Bearish
      regimes = Array.new(size) # 0: High, 1: Medium, 2: Low
      assigned_atr = Array.new(size)

      # Bands
      upper_band = Array.new(size)
      lower_band = Array.new(size)

      size.times do |i|
        # Wait until we have enough data for ATR and rolling min/max
        if i < atr_len || atr[i].nil? || upper_vol[i].nil? || lower_vol[i].nil?
          direction[i] = nil
          next
        end

        # Calculate dynamic centroids
        hv = lower_vol[i] + ((upper_vol[i] - lower_vol[i]) * p_high)
        mv = lower_vol[i] + ((upper_vol[i] - lower_vol[i]) * p_mid)
        lv = lower_vol[i] + ((upper_vol[i] - lower_vol[i]) * p_low)

        # Clustering: find nearest centroid
        dist_h = (atr[i] - hv).abs
        dist_m = (atr[i] - mv).abs
        dist_l = (atr[i] - lv).abs

        # cluster = vdist_a < vdist_b and vdist_a < vdist_c ? 0 : vdist_b < vdist_c ? 1 : 2
        # cluster == 0 ? hvNew : cluster == 1 ? mvNew : lvNew
        cluster = if dist_h < dist_m && dist_h < dist_l
                    0
                  elsif dist_m < dist_l
                    1
                  else
                    2
                  end

        regimes[i] = cluster
        a_atr = case cluster
                when 0 then hv
                when 1 then mv
                else lv
                end
        assigned_atr[i] = a_atr

        # Pine SuperTrend Core Logic
        hl2 = (highs[i] + lows[i]) / 2.0

        # basic bands
        b_upper = hl2 + (factor * a_atr)
        b_lower = hl2 - (factor * a_atr)

        # Initialize or trailing logic
        if i.zero? || upper_band[i - 1].nil? || lower_band[i - 1].nil?
          upper_band[i] = b_upper
          lower_band[i] = b_lower
          direction[i] = (closes[i] > b_upper ? -1 : 1)
        else
          prev_upper = upper_band[i - 1]
          prev_lower = lower_band[i - 1]
          prev_close = closes[i - 1]
          prev_dir = direction[i - 1]

          # Filtering bands
          upper_band[i] = b_upper < prev_upper || prev_close > prev_upper ? b_upper : prev_upper
          lower_band[i] = b_lower > prev_lower || prev_close < prev_lower ? b_lower : prev_lower

          # Direction logic
          # prevSuperTrend is either upper_band or lower_band depending on dir
          prev_st = (prev_dir == -1 ? prev_lower : prev_upper)

          if prev_st == prev_upper
            direction[i] = (closes[i] > upper_band[i] ? -1 : 1)
          else
            direction[i] = (closes[i] < lower_band[i] ? 1 : -1)
          end
        end

        super_trend[i] = (direction[i] == -1 ? lower_band[i] : upper_band[i])
      end

      {
        super_trend: super_trend,
        direction: direction,
        regimes: regimes,
        assigned_atr: assigned_atr,
        last_index: size - 1
      }
    end

    private

    def empty_result
      { super_trend: [], direction: [], regimes: [], assigned_atr: [], last_index: -1 }
    end

    def extract_series(type)
      if series.respond_to?("#{type}s")
        series.send("#{type}s")
      elsif series.respond_to?(:candles)
        series.candles.map(&type)
      else
        []
      end
    end

    # Relative Moving Average (Pine's ta.atr uses this)
    # alpha = 1 / length
    def calculate_rma_atr(highs, lows, closes, length)
      size = closes.size
      tr = Array.new(size)
      atr = Array.new(size)

      size.times do |i|
        if i.zero?
          tr[i] = highs[i] - lows[i]
        else
          tr[i] = [
            highs[i] - lows[i],
            (highs[i] - closes[i - 1]).abs,
            (lows[i] - closes[i - 1]).abs
          ].max
        end
      end

      rma_sum = 0.0
      size.times do |i|
        if i < length - 1
          rma_sum += tr[i]
          atr[i] = nil
        elsif i == length - 1
          rma_sum += tr[i]
          atr[i] = rma_sum / length
        else
          atr[i] = ((atr[i - 1] * (length - 1)) + tr[i]) / length.to_f
        end
      end

      atr
    end

    def rolling_highest(source, length)
      size = source.size
      results = Array.new(size)

      size.times do |i|
        if i < length - 1
          results[i] = nil
        else
          window = source[(i - length + 1)..i].compact
          results[i] = window.empty? ? nil : window.max
        end
      end

      results
    end

    def rolling_lowest(source, length)
      size = source.size
      results = Array.new(size)

      size.times do |i|
        if i < length - 1
          results[i] = nil
        else
          window = source[(i - length + 1)..i].compact
          results[i] = window.empty? ? nil : window.min
        end
      end

      results
    end
  end
end
