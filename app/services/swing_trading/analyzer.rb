# frozen_string_literal: true

module SwingTrading
  class Analyzer < ApplicationService
    # Configuration constants
    DEFAULT_SWING_TIMEFRAME = '15' # 15-minute candles for swing trading
    DEFAULT_LONG_TERM_TIMEFRAME = '60' # 1-hour candles for long-term
    MIN_CONFIDENCE_SCORE = 0.6 # Minimum confidence to generate recommendation
    DEFAULT_HOLD_DAYS_SWING = 3 # Default hold duration for swing trades
    DEFAULT_HOLD_DAYS_LONG_TERM = 15 # Default hold duration for long-term trades
    RISK_REWARD_RATIO_MIN = 2.0 # Minimum risk-reward ratio
    STOP_LOSS_PCT = 0.03 # 3% stop loss
    TAKE_PROFIT_PCT = 0.06 # 6% take profit (2:1 RR)

    def initialize(watchlist_item:, recommendation_type: 'swing')
      @watchlist_item = watchlist_item
      @recommendation_type = recommendation_type.to_s
      @instrument = find_or_create_instrument
    end

    def call
      return error_result('Instrument not found') unless @instrument
      return error_result('Insufficient data') unless sufficient_data?

      analysis = perform_technical_analysis
      return error_result('No valid signal') unless analysis[:signal] == :buy || analysis[:signal] == :sell

      volume_analysis = analyze_volume
      confidence_score = calculate_confidence(analysis, volume_analysis)

      return error_result('Confidence too low') if confidence_score < MIN_CONFIDENCE_SCORE

      recommendation = build_recommendation(analysis, volume_analysis, confidence_score)
      success_result(recommendation)
    rescue StandardError => e
      Rails.logger.error("[SwingTrading::Analyzer] Error analyzing #{@watchlist_item.symbol_name}: #{e.class} - #{e.message}")
      Rails.logger.error("[SwingTrading::Analyzer] Backtrace: #{e.backtrace.first(5).join(', ')}")
      error_result("Analysis failed: #{e.message}")
    end

    private

    def find_or_create_instrument
      instrument = Instrument.find_by(
        security_id: @watchlist_item.security_id,
        segment: @watchlist_item.segment
      )

      return instrument if instrument

      # Try to find by symbol if security_id doesn't match
      Instrument.find_by(
        symbol_name: @watchlist_item.symbol_name,
        segment: @watchlist_item.segment
      )
    end

    def sufficient_data?
      series = fetch_candle_series
      return false unless series&.candles&.any?

      # Need at least 50 candles for reliable analysis
      series.candles.size >= 50
    end

    def fetch_candle_series
      timeframe = @recommendation_type == 'long_term' ? DEFAULT_LONG_TERM_TIMEFRAME : DEFAULT_SWING_TIMEFRAME

      # Fetch intraday data with more days for swing/long-term analysis
      days_back = @recommendation_type == 'long_term' ? 30 : 10
      raw_data = @instrument.intraday_ohlc(interval: timeframe, days: days_back)

      return nil unless raw_data&.is_a?(Array) && raw_data.any?

      # Convert raw data to format expected by CandleSeries
      normalized_data = raw_data.map do |bar|
        {
          timestamp: parse_timestamp(bar['start_Time'] || bar['startTime'] || bar['time'] || bar['timestamp']),
          open: bar['open'] || bar[:open],
          high: bar['high'] || bar[:high],
          low: bar['low'] || bar[:low],
          close: bar['close'] || bar[:close],
          volume: bar['volume'] || bar[:volume] || 0
        }
      end

      # Create CandleSeries and load data
      series = CandleSeries.new(symbol: @instrument.symbol_name, interval: timeframe)
      series.load_from_raw(normalized_data)

      series
    rescue StandardError => e
      Rails.logger.error("[SwingTrading::Analyzer] Failed to fetch candle series: #{e.message}")
      Rails.logger.error("[SwingTrading::Analyzer] Backtrace: #{e.backtrace.first(3).join(', ')}")
      nil
    end

    def parse_timestamp(timestamp_value)
      return Time.current if timestamp_value.nil?

      case timestamp_value
      when Time, DateTime
        timestamp_value
      when String
        Time.zone.parse(timestamp_value) || Time.parse(timestamp_value)
      when Integer
        Time.zone.at(timestamp_value)
      else
        Time.current
      end
    rescue StandardError
      Time.current
    end

    def perform_technical_analysis
      series = fetch_candle_series
      return { signal: :avoid } unless series&.candles&.any?

      current_index = series.candles.size - 1
      analysis = {}

      # 1. Supertrend Analysis
      supertrend_cfg = { period: 10, multiplier: 3.0 }
      st_service = Indicators::Supertrend.new(series: series, **supertrend_cfg)
      st_result = st_service.call
      analysis[:supertrend] = {
        trend: st_result[:trend],
        value: st_result[:last_value],
        direction: st_result[:trend] == :bullish ? :buy : (st_result[:trend] == :bearish ? :sell : :avoid)
      }

      # 2. ADX Analysis
      adx_period = 14
      adx_value = @instrument.adx(adx_period, interval: series.interval)
      analysis[:adx] = {
        value: adx_value,
        strength: adx_strength(adx_value)
      }

      # 3. RSI Analysis
      rsi_value = series.rsi(14)
      rsi_result = if rsi_value
                     {
                       value: rsi_value,
                       direction: rsi_value < 30 ? :buy : (rsi_value > 70 ? :sell : :neutral),
                       confidence: calculate_rsi_confidence(rsi_value)
                     }
                   else
                     { value: nil, direction: :neutral, confidence: 0 }
                   end
      analysis[:rsi] = rsi_result

      # 4. MACD Analysis
      macd_array = series.macd(12, 26, 9)
      macd_result = if macd_array && macd_array.size >= 3
                      macd_line = macd_array[0] || 0
                      signal_line = macd_array[1] || 0
                      histogram = macd_array[2] || 0
                      {
                        value: { macd: macd_line, signal: signal_line, histogram: histogram },
                        direction: macd_line > signal_line ? :buy : (macd_line < signal_line ? :sell : :neutral),
                        confidence: calculate_macd_confidence(macd_line, signal_line, histogram)
                      }
                    else
                      { value: nil, direction: :neutral, confidence: 0 }
                    end
      analysis[:macd] = macd_result

      # 5. Determine overall signal
      signal = determine_signal(analysis)
      analysis[:signal] = signal
      analysis[:series] = series

      analysis
    end

    def adx_strength(adx_value)
      return 'weak' if adx_value < 20
      return 'moderate' if adx_value < 40
      return 'strong' if adx_value < 60

      'very_strong'
    end

    def determine_signal(analysis)
      signals = []
      weights = {}

      # Supertrend has highest weight
      if analysis[:supertrend][:direction] != :avoid
        signals << analysis[:supertrend][:direction]
        weights[analysis[:supertrend][:direction]] = 0.4
      end

      # ADX strength check
      if analysis[:adx][:strength] == 'strong' || analysis[:adx][:strength] == 'very_strong'
        # ADX confirms trend strength but doesn't give direction
        # Use supertrend direction if ADX is strong
        if analysis[:supertrend][:direction] != :avoid
          weights[analysis[:supertrend][:direction]] = (weights[analysis[:supertrend][:direction]] || 0) + 0.2
        end
      end

      # RSI confirmation
      if analysis[:rsi][:direction] != :neutral
        signals << analysis[:rsi][:direction]
        weights[analysis[:rsi][:direction]] = (weights[analysis[:rsi][:direction]] || 0) + 0.2
      end

      # MACD confirmation
      if analysis[:macd][:direction] != :neutral
        signals << analysis[:macd][:direction]
        weights[analysis[:macd][:direction]] = (weights[analysis[:macd][:direction]] || 0) + 0.2
      end

      # Determine final signal based on weighted votes
      return :avoid if signals.empty? || weights.empty?

      buy_weight = weights[:buy] || 0
      sell_weight = weights[:sell] || 0

      # Need at least 0.5 total weight to generate signal
      return :avoid if (buy_weight + sell_weight) < 0.5

      # Return direction with higher weight
      buy_weight > sell_weight ? :buy : :sell
    end

    def analyze_volume
      series = fetch_candle_series
      return {} unless series&.candles&.any?

      candles = series.candles
      recent_candles = candles.last(20) # Last 20 candles
      historical_candles = candles.first([candles.size - 20, 50].min) # Previous 50 candles

      return {} if recent_candles.empty? || historical_candles.empty?

      # Calculate average volumes
      recent_volumes = recent_candles.map { |c| c.volume.to_i }.reject(&:zero?)
      historical_volumes = historical_candles.map { |c| c.volume.to_i }.reject(&:zero?)

      return {} if recent_volumes.empty? || historical_volumes.empty?

      avg_recent_volume = recent_volumes.sum.to_f / recent_volumes.size
      avg_historical_volume = historical_volumes.sum.to_f / historical_volumes.size

      current_volume = candles.last.volume.to_i
      volume_ratio = avg_historical_volume.positive? ? (avg_recent_volume / avg_historical_volume) : 1.0

      # Determine volume trend
      volume_trend = if volume_ratio > 1.5
                       'increasing'
                     elsif volume_ratio < 0.7
                       'decreasing'
                     else
                       'stable'
                     end

      {
        avg_volume: avg_recent_volume.round(0),
        current_volume: current_volume,
        volume_ratio: volume_ratio.round(2),
        trend: volume_trend,
        avg_historical_volume: avg_historical_volume.round(0)
      }
    rescue StandardError => e
      Rails.logger.error("[SwingTrading::Analyzer] Volume analysis failed: #{e.message}")
      {}
    end

    def calculate_confidence(analysis, volume_analysis)
      base_confidence = 0.5
      confidence_factors = []

      # ADX strength factor (0-0.2)
      case analysis[:adx][:strength]
      when 'very_strong'
        confidence_factors << 0.2
      when 'strong'
        confidence_factors << 0.15
      when 'moderate'
        confidence_factors << 0.1
      else
        confidence_factors << 0.05
      end

      # RSI confidence factor (0-0.15)
      if analysis[:rsi][:confidence]
        confidence_factors << (analysis[:rsi][:confidence] * 0.15)
      end

      # MACD confidence factor (0-0.15)
      if analysis[:macd][:confidence]
        confidence_factors << (analysis[:macd][:confidence] * 0.15)
      end

      # Volume confirmation factor (0-0.1)
      if volume_analysis[:trend] == 'increasing'
        confidence_factors << 0.1
      elsif volume_analysis[:trend] == 'stable'
        confidence_factors << 0.05
      end

      total_confidence = base_confidence + confidence_factors.sum
      [total_confidence, 1.0].min # Cap at 1.0
    end

    def build_recommendation(analysis, volume_analysis, confidence_score)
      series = analysis[:series]
      last_candle = series.candles.last
      current_price = last_candle.close.to_f

      # Calculate entry, stop loss, and take profit
      direction = analysis[:signal]
      entry_price = current_price

      if direction == :buy
        stop_loss = entry_price * (1 - STOP_LOSS_PCT)
        take_profit = entry_price * (1 + TAKE_PROFIT_PCT)
      else # :sell (short)
        stop_loss = entry_price * (1 + STOP_LOSS_PCT)
        take_profit = entry_price * (1 - TAKE_PROFIT_PCT)
      end

      # Calculate quantity and allocation
      allocation_result = calculate_allocation(entry_price, confidence_score)
      quantity = allocation_result[:quantity]
      allocation_pct = allocation_result[:allocation_pct]

      # Determine hold duration
      hold_duration_days = @recommendation_type == 'long_term' ? DEFAULT_HOLD_DAYS_LONG_TERM : DEFAULT_HOLD_DAYS_SWING

      # Build reasoning
      reasoning = build_reasoning(analysis, volume_analysis, confidence_score)

      {
        watchlist_item_id: @watchlist_item.id,
        symbol_name: @watchlist_item.symbol_name,
        segment: @watchlist_item.segment,
        security_id: @watchlist_item.security_id,
        recommendation_type: @recommendation_type,
        direction: direction.to_s,
        entry_price: entry_price.round(2),
        stop_loss: stop_loss.round(2),
        take_profit: take_profit.round(2),
        quantity: quantity,
        allocation_pct: allocation_pct,
        hold_duration_days: hold_duration_days,
        confidence_score: confidence_score.round(4),
        technical_analysis: {
          supertrend: {
            trend: analysis[:supertrend][:trend]&.to_s,
            value: analysis[:supertrend][:value]
          },
          adx: {
            value: analysis[:adx][:value],
            strength: analysis[:adx][:strength]
          },
          rsi: {
            value: analysis[:rsi][:value],
            direction: analysis[:rsi][:direction]&.to_s,
            confidence: analysis[:rsi][:confidence]
          },
          macd: {
            value: analysis[:macd][:value],
            direction: analysis[:macd][:direction]&.to_s,
            confidence: analysis[:macd][:confidence]
          },
          trend: analysis[:supertrend][:trend]&.to_s
        },
        volume_analysis: volume_analysis,
        reasoning: reasoning,
        analysis_timestamp: Time.current,
        expires_at: Time.current + hold_duration_days.days
      }
    end

    def calculate_allocation(entry_price, confidence_score)
      # Use capital allocator logic adapted for swing trading
      available_capital = Capital::Allocator.available_cash.to_f
      return { quantity: 0, allocation_pct: 0 } if available_capital <= 0

      # Base allocation percentage based on recommendation type
      base_allocation_pct = @recommendation_type == 'long_term' ? 5.0 : 10.0

      # Adjust based on confidence score
      confidence_multiplier = confidence_score
      allocation_pct = (base_allocation_pct * confidence_multiplier).round(2)

      # Cap allocation at 20% for swing, 15% for long-term
      max_allocation = @recommendation_type == 'long_term' ? 15.0 : 20.0
      allocation_pct = [allocation_pct, max_allocation].min

      # Calculate quantity based on allocation
      allocation_amount = (available_capital * allocation_pct / 100.0)
      quantity = (allocation_amount / entry_price).to_i

      # Ensure minimum quantity of 1
      quantity = [quantity, 1].max

      { quantity: quantity, allocation_pct: allocation_pct }
    end

    def calculate_rsi_confidence(rsi_value)
      return 0 if rsi_value.nil?

      # Higher confidence when RSI is more extreme
      if rsi_value < 30 || rsi_value > 70
        0.8
      elsif rsi_value < 40 || rsi_value > 60
        0.6
      else
        0.4
      end
    end

    def calculate_macd_confidence(macd_line, signal_line, histogram)
      return 0 if macd_line.nil? || signal_line.nil?

      # Higher confidence when MACD and signal diverge significantly
      divergence = (macd_line - signal_line).abs
      histogram_strength = histogram.abs

      base_confidence = divergence > 0 ? 0.6 : 0.3
      histogram_bonus = histogram_strength > 0 ? 0.2 : 0

      [base_confidence + histogram_bonus, 1.0].min
    end

    def build_reasoning(analysis, volume_analysis, confidence_score)
      reasons = []
      direction = analysis[:signal] == :buy ? 'BUY' : 'SELL'

      reasons << "#{direction} signal generated based on technical analysis:"

      # Supertrend
      if analysis[:supertrend][:trend]
        reasons << "- Supertrend indicates #{analysis[:supertrend][:trend]} trend"
      end

      # ADX
      if analysis[:adx][:strength]
        reasons << "- ADX shows #{analysis[:adx][:strength]} trend strength (#{analysis[:adx][:value]&.round(2)})"
      end

      # RSI
      if analysis[:rsi][:value]
        rsi_direction = analysis[:rsi][:direction] == :buy ? 'bullish' : (analysis[:rsi][:direction] == :sell ? 'bearish' : 'neutral')
        reasons << "- RSI is #{rsi_direction} (#{analysis[:rsi][:value]&.round(2)})"
      end

      # MACD
      if analysis[:macd][:direction] != :neutral
        macd_direction = analysis[:macd][:direction] == :buy ? 'bullish' : 'bearish'
        reasons << "- MACD shows #{macd_direction} momentum"
      end

      # Volume
      if volume_analysis[:trend]
        reasons << "- Volume trend is #{volume_analysis[:trend]} (ratio: #{volume_analysis[:volume_ratio]})"
      end

      reasons << "- Confidence score: #{(confidence_score * 100).round(1)}%"
      reasons << "- Recommended hold duration: #{@recommendation_type == 'long_term' ? DEFAULT_HOLD_DAYS_LONG_TERM : DEFAULT_HOLD_DAYS_SWING} days"

      reasons.join("\n")
    end

    def success_result(data)
      { success: true, data: data }
    end

    def error_result(message)
      { success: false, error: message }
    end
  end
end
