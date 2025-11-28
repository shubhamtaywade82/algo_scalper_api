# frozen_string_literal: true

module Indicators
  # Trend Duration Indicator
  # Uses HMA (Hull Moving Average) to detect trend direction and duration
  # Tracks historical trend durations to forecast probable trend length
  class TrendDurationIndicator < BaseIndicator
    def initialize(series:, config: {})
      super
      @hma_length = config[:hma_length] || 20
      @trend_length = config[:trend_length] || 5 # Bars to confirm trend
      @samples = config[:samples] || 10 # Number of historical durations to track
      @bullish_durations = []
      @bearish_durations = []
      @trend_count = 0
      @current_trend = nil
      @hma_series = []
      @last_hma = nil
    end

    def min_required_candles
      # Need enough candles for HMA calculation
      # Step 1: Calculate raw HMA (requires @hma_length candles)
      # Step 2: Calculate final HMA from raw HMA series (requires sqrt(@hma_length) raw HMA values)
      # So we need: @hma_length (for raw HMA) + sqrt(@hma_length) (for final WMA)
      sqrt_l = Math.sqrt(@hma_length).ceil
      @hma_length + sqrt_l
    end

    def ready?(index)
      index >= min_required_candles
    end

    def calculate_at(index)
      return nil unless ready?(index)
      return nil unless trading_hours?(series.candles[index])

      # Create partial series up to current index
      partial_series = create_partial_series(index)
      return nil if partial_series.nil?

      # Calculate HMA for all candles up to index
      hma_values = calculate_hma_series(partial_series)
      return nil if hma_values.empty? || hma_values.size < @trend_length

      current_hma = hma_values.last
      @last_hma = current_hma

      # Detect trend direction
      trend_direction = detect_trend(hma_values)
      return nil if trend_direction == :neutral

      # Update trend duration tracking
      update_trend_duration(trend_direction)

      # Calculate probable duration
      probable_duration = calculate_probable_duration(trend_direction)

      # Determine signal direction and confidence
      direction = trend_direction == :bullish ? :bullish : :bearish
      confidence = calculate_confidence(trend_direction, probable_duration)

      {
        value: {
          hma: current_hma,
          trend_direction: trend_direction,
          real_length: @trend_count,
          probable_length: probable_duration,
          slope: trend_direction == :bullish ? 'up' : 'down'
        },
        direction: direction,
        confidence: confidence
      }
    end

    private

    def create_partial_series(index)
      partial_series = CandleSeries.new(symbol: series.symbol, interval: series.interval)
      series.candles[0..index].each { |candle| partial_series.add_candle(candle) }
      partial_series
    end

    def calculate_hma_series(partial_series)
      closes = partial_series.closes
      return [] if closes.size < min_required_candles

      half = (@hma_length / 2).floor
      sqrt_l = Math.sqrt(@hma_length).floor

      # Step 1: Calculate raw HMA series (2 * WMA(half) - WMA(full))
      raw_hma_series = []
      closes.each_with_index do |_close, idx|
        next if idx < @hma_length - 1

        window = closes[0..idx]
        wma_half = calculate_wma(window, half)
        wma_full = calculate_wma(window, @hma_length)

        next unless wma_half && wma_full

        raw_hma = 2 * wma_half - wma_full
        raw_hma_series << raw_hma
      end

      return [] if raw_hma_series.empty?

      # Step 2: Calculate final HMA by applying WMA to raw HMA series
      hma_values = []
      raw_hma_series.each_with_index do |_raw, idx|
        next if idx < sqrt_l - 1

        raw_window = raw_hma_series[0..idx]
        final_hma = calculate_wma(raw_window, sqrt_l)
        hma_values << final_hma if final_hma
      end

      hma_values
    end

    def calculate_hma(values, length)
      # This method is kept for backward compatibility but calculate_hma_series is preferred
      half = (length / 2).floor
      sqrt_l = Math.sqrt(length).floor

      return nil if values.size < length

      wma_half = calculate_wma(values, half)
      wma_full = calculate_wma(values, length)

      return nil unless wma_half && wma_full

      raw_hma = 2 * wma_half - wma_full

      # For single point calculation, we need accumulated raw HMA values
      # This is a simplified version - use calculate_hma_series for accurate results
      return raw_hma if values.size < length + sqrt_l

      # If we have enough data, calculate final WMA
      # This requires building raw HMA series first, which is done in calculate_hma_series
      nil
    end

    def calculate_wma(values, period)
      return nil if values.size < period

      # Weighted Moving Average: weights are 1, 2, 3, ..., period
      weights = (1..period).to_a
      weighted_sum = 0.0
      weight_sum = 0.0

      values.last(period).each_with_index do |value, idx|
        weight = weights[idx]
        weighted_sum += value * weight
        weight_sum += weight
      end

      return nil if weight_sum.zero?

      weighted_sum / weight_sum
    end

    def detect_trend(hma_values)
      return :neutral if hma_values.size < @trend_length

      # Check last trend_length bars for consistent direction
      recent_hma = hma_values.last(@trend_length)

      # Check if rising (each value > previous)
      is_rising = recent_hma.each_cons(2).all? { |a, b| b > a }

      # Check if falling (each value < previous)
      is_falling = recent_hma.each_cons(2).all? { |a, b| b < a }

      return :bullish if is_rising
      return :bearish if is_falling

      :neutral
    end

    def update_trend_duration(new_trend)
      # If trend changed, save previous trend duration
      if @current_trend && @current_trend != new_trend
        if @current_trend == :bullish
          @bullish_durations << @trend_count
          @bullish_durations.shift if @bullish_durations.size > @samples
        else
          @bearish_durations << @trend_count
          @bearish_durations.shift if @bearish_durations.size > @samples
        end
        @trend_count = 0
      end

      @current_trend = new_trend
      @trend_count += 1 if new_trend != :neutral
    end

    def calculate_probable_duration(trend_direction)
      durations = trend_direction == :bullish ? @bullish_durations : @bearish_durations

      return @trend_count if durations.empty?

      # Calculate average of historical durations
      durations.sum.to_f / durations.size
    end

    def calculate_confidence(trend_direction, probable_duration)
      base = 50

      # Higher confidence if trend is established
      base += 20 if @trend_count >= @trend_length

      # Higher confidence if current duration matches probable duration
      if probable_duration > 0
        duration_ratio = @trend_count.to_f / probable_duration
        if duration_ratio >= 0.8 && duration_ratio <= 1.2
          base += 15 # Trend is in expected range
        elsif duration_ratio < 0.5
          base += 10 # Early in trend, more room to run
        end
      end

      # Higher confidence if we have historical data
      durations = trend_direction == :bullish ? @bullish_durations : @bearish_durations
      base += 10 if durations.size >= 5

      [base, 100].min
    end
  end
end
