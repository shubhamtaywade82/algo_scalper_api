# frozen_string_literal: true

require 'dhan_hq'

# Service for performing technical analysis on indices using DhanHQ TA modules
# Integrates with existing signal generation workflow
class IndexTechnicalAnalyzer < ApplicationService
  include Concerns::DhanhqErrorHandler

  # Configuration mapping for major indices
  INDEX_CONFIG = {
    nifty: {
      security_id: '13',
      exchange_segment: 'IDX_I',
      instrument: 'INDEX',
      symbol: 'NIFTY'
    },
    sensex: {
      security_id: '51',
      exchange_segment: 'IDX_I',
      instrument: 'INDEX',
      symbol: 'SENSEX'
    },
    banknifty: {
      security_id: '25',
      exchange_segment: 'IDX_I',
      instrument: 'INDEX',
      symbol: 'BANKNIFTY'
    }
  }.freeze

  DEFAULT_TIMEFRAMES = [5, 15, 60].freeze
  DEFAULT_DAYS_BACK = 30

  attr_reader :index_symbol, :config, :indicators, :bias_summary, :error

  def initialize(index_symbol = :nifty)
    @index_symbol = normalize_index_symbol(index_symbol)
    @config = load_index_config
    @indicators = nil
    @bias_summary = nil
    @error = nil
  end

  # Main entry point following ApplicationService pattern
  def call(timeframes: DEFAULT_TIMEFRAMES, days_back: DEFAULT_DAYS_BACK)
    return failure_result('DhanHQ credentials not configured') unless valid_credentials?

    begin
      compute_indicators(timeframes, days_back)
      generate_bias_summary
      success_result
    rescue StandardError => e
      handle_analysis_error(e)
      failure_result(e.message)
    end
  end

  # Get simplified signal for integration with signal engine
  def signal
    return :neutral unless @bias_summary

    bias = @bias_summary.dig(:summary, :bias).to_s
    case bias
    when 'bullish', 'strong_bullish'
      :bullish
    when 'bearish', 'strong_bearish'
      :bearish
    else
      :neutral
    end
  end

  # Get confidence score (0.0 to 1.0)
  def confidence
    @bias_summary&.dig(:summary, :confidence).to_f
  end

  # Get rationale for AI context
  def rationale
    @bias_summary&.dig(:summary, :rationale) || {}
  end

  # Comprehensive analysis result
  def result
    {
      index: @index_symbol,
      symbol: @config[:symbol],
      signal: signal,
      confidence: confidence,
      indicators: @indicators,
      bias_summary: @bias_summary,
      timestamp: Time.current,
      error: @error
    }
  end

  # Check if analysis was successful
  def success?
    @error.nil? && @bias_summary.present?
  end

  private

  def normalize_index_symbol(symbol)
    symbol.to_s.downcase.to_sym
  end

  def load_index_config
    # Try to get config from INDEX_CONFIG first
    config = INDEX_CONFIG[@index_symbol]
    return config if config

    # Fallback: try to load from IndexConfigLoader
    index_configs = IndexConfigLoader.load_indices
    matching = index_configs.find { |cfg| cfg[:key].to_s.downcase == @index_symbol.to_s }

    if matching
      {
        security_id: matching[:sid] || matching['sid'],
        exchange_segment: matching[:segment] || matching['segment'] || 'IDX_I',
        instrument: 'INDEX',
        symbol: matching[:key] || matching['key']
      }
    else
      # Default to NIFTY if not found
      INDEX_CONFIG[:nifty]
    end
  end

  def valid_credentials?
    client_id = ENV['DHANHQ_CLIENT_ID'] || ENV['CLIENT_ID']
    access_token = ENV['DHANHQ_ACCESS_TOKEN'] || ENV['ACCESS_TOKEN']

    unless client_id && access_token
      @error = 'DhanHQ credentials not configured'
      return false
    end

    true
  end

  def compute_indicators(timeframes, days_back)
    # Check if DhanHQ TA modules are available
    unless dhanhq_ta_available?
      log_warn('DhanHQ TA modules not available - using fallback analysis')
      return compute_fallback_indicators(timeframes, days_back)
    end

    begin
      # Initialize TA client with throttling
      ta = TA::TechnicalAnalysis.new(
        throttle_seconds: 2.5,
        max_retries: 3
      )

      # Fetch and compute indicators
      @indicators = ta.compute(
        exchange_segment: @config[:exchange_segment],
        instrument: @config[:instrument],
        security_id: @config[:security_id],
        intervals: timeframes,
        days_back: days_back
      )

      log_info("Computed indicators for #{@config[:symbol]} across #{timeframes.join(', ')}min timeframes")
    rescue NameError, NoMethodError => e
      log_warn("DhanHQ TA module not available: #{e.message} - using fallback")
      compute_fallback_indicators(timeframes, days_back)
    rescue StandardError => e
      error_info = Concerns::DhanhqErrorHandler.handle_dhanhq_error(e, context: 'technical_analysis')
      raise e if error_info[:token_expired]
      compute_fallback_indicators(timeframes, days_back)
    end
  end

  def generate_bias_summary
    return unless @indicators

    # Check if DhanHQ Analysis module is available
    if dhanhq_analysis_available?
      begin
        analyzer = DhanHQ::Analysis::MultiTimeframeAnalyzer.new(data: @indicators)
        @bias_summary = analyzer.call
        log_info("Generated bias summary: #{@bias_summary.dig(:summary, :bias)}")
      rescue NameError, NoMethodError => e
        log_warn("DhanHQ Analysis module not available: #{e.message} - using fallback")
        @bias_summary = generate_fallback_bias_summary
      end
    else
      @bias_summary = generate_fallback_bias_summary
    end
  end

  def compute_fallback_indicators(timeframes, days_back)
    # Fallback: Use existing instrument-based OHLC fetching
    # This ensures the service works even if DhanHQ TA modules aren't available
    log_info("Using fallback indicator computation for #{@config[:symbol]}")

    index_configs = IndexConfigLoader.load_indices
    matching = index_configs.find { |cfg| cfg[:key].to_s.upcase == @config[:symbol].to_s }

    return nil unless matching

    instrument = IndexInstrumentCache.instance.get_or_fetch(matching)
    return nil unless instrument

    # Fetch OHLC data for each timeframe
    indicators_data = {}
    timeframes.each do |tf|
      begin
        ohlc = instrument.intraday_ohlc(interval: tf, days_back: days_back)
        next unless ohlc&.any?

        # Compute basic indicators using existing infrastructure
        series = CandleSeries.new(symbol: instrument.symbol_name, interval: tf)
        ohlc.each { |candle| series.add_candle(candle) }

        indicators_data[tf] = {
          rsi: series.rsi(14),
          adx: series.adx(14),
          macd: series.macd(12, 26, 9),
          atr: series.atr(14)
        }
      rescue StandardError => e
        log_error("Failed to compute indicators for #{tf}min: #{e.class} - #{e.message}")
      end
    end

    @indicators = indicators_data.present? ? indicators_data : nil
  end

  def generate_fallback_bias_summary
    # Generate a simple bias summary from fallback indicators
    return nil unless @indicators&.any?

    bullish_count = 0
    bearish_count = 0
    total_count = 0

    @indicators.each_value do |tf_data|
      next unless tf_data.is_a?(Hash)

      # Simple RSI-based bias
      rsi = tf_data[:rsi]
      if rsi
        bullish_count += 1 if rsi < 40
        bearish_count += 1 if rsi > 60
        total_count += 1
      end
    end

    bias = if bullish_count > bearish_count && bullish_count > total_count / 2
             :bullish
           elsif bearish_count > bullish_count && bearish_count > total_count / 2
             :bearish
           else
             :neutral
           end

    confidence = [(bullish_count + bearish_count).to_f / [total_count, 1].max, 1.0].min

    {
      meta: { source: :fallback, timeframes: @indicators.keys },
      summary: {
        bias: bias,
        confidence: confidence,
        rationale: {
          rsi: "RSI analysis across #{@indicators.keys.join(', ')}min timeframes",
          method: 'fallback_analysis'
        }
      }
    }
  end

  def dhanhq_ta_available?
    defined?(TA) && TA.const_defined?(:TechnicalAnalysis)
  end

  def dhanhq_analysis_available?
    defined?(DhanHQ) && DhanHQ.const_defined?(:Analysis) &&
      DhanHQ::Analysis.const_defined?(:MultiTimeframeAnalyzer)
  end

  def handle_analysis_error(error)
    error_info = Concerns::DhanhqErrorHandler.handle_dhanhq_error(error, context: 'index_technical_analysis')
    @error = error.message
    log_error("Technical analysis failed: #{error.class} - #{error.message}")
  end

  def success_result
    { success: true, result: result }
  end

  def failure_result(message)
    @error = message
    { success: false, error: message, result: result }
  end
end
