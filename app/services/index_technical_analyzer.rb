# frozen_string_literal: true

require 'dhan_hq'

# Service for performing technical analysis on indices using DhanHQ TA modules
# Single configurable analyzer that adapts behavior based on index-specific configuration
# Integrates with existing signal generation workflow
class IndexTechnicalAnalyzer < ApplicationService
  include Concerns::DhanhqErrorHandler

  # === CONFIGURABLE BEHAVIOR STRATEGIES (Strategy pattern via config) ===
  ANALYSIS_STRATEGIES = {
    # Strategy name => {method: :symbol, default: value, index_specific: {}}
    timeframes: {
      method: :select_timeframes,
      default: [5, 15, 60],
      index_specific: {
        nifty: [5, 15, 60],
        sensex: [5, 15, 30, 60], # Sensex might benefit from 30min timeframe
        banknifty: [5, 15, 60] # Bank Nifty same as Nifty
      }
    },

    indicator_periods: {
      method: :configure_indicator_periods,
      default: {
        rsi: 14,
        adx: 14,
        macd_fast: 12,
        macd_slow: 26,
        macd_signal: 9,
        atr: 14
      },
      index_specific: {
        nifty: {
          rsi: 14,
          adx: 14,
          macd_fast: 12,
          macd_slow: 26,
          macd_signal: 9,
          atr: 14
        },
        sensex: {
          rsi: 14,
          adx: 14,
          macd_fast: 12,
          macd_slow: 26,
          macd_signal: 9,
          atr: 14
        },
        banknifty: {
          rsi: 14,
          adx: 14,
          macd_fast: 12,
          macd_slow: 26,
          macd_signal: 9,
          atr: 14
        }
      }
    },

    bias_thresholds: {
      method: :configure_bias_thresholds,
      default: {
        rsi_oversold: 30,
        rsi_overbought: 70,
        rsi_bullish_threshold: 40,
        rsi_bearish_threshold: 60,
        min_timeframes_for_signal: 2,
        confidence_base: 0.4
      },
      index_specific: {
        nifty: {
          rsi_oversold: 30,
          rsi_overbought: 70,
          rsi_bullish_threshold: 40,
          rsi_bearish_threshold: 60,
          min_timeframes_for_signal: 2,
          confidence_base: 0.4
        },
        sensex: {
          rsi_oversold: 25, # More sensitive for Sensex
          rsi_overbought: 75,
          rsi_bullish_threshold: 35,
          rsi_bearish_threshold: 65,
          min_timeframes_for_signal: 2,
          confidence_base: 0.5 # Higher base confidence for Sensex
        },
        banknifty: {
          rsi_oversold: 30,
          rsi_overbought: 70,
          rsi_bullish_threshold: 40,
          rsi_bearish_threshold: 60,
          min_timeframes_for_signal: 2,
          confidence_base: 0.4
        }
      }
    },

    api_settings: {
      method: :configure_api_settings,
      default: {
        throttle_seconds: 2.5,
        max_retries: 3,
        days_back: 30
      },
      index_specific: {
        nifty: {
          throttle_seconds: 2.5,
          max_retries: 3,
          days_back: 30
        },
        sensex: {
          throttle_seconds: 3.0, # Slightly slower for Sensex
          max_retries: 3,
          days_back: 30
        },
        banknifty: {
          throttle_seconds: 2.5,
          max_retries: 3,
          days_back: 30
        }
      }
    }
  }.freeze

  # Base index configuration (security IDs, segments, symbols)
  INDEX_BASE_CONFIG = {
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

  def initialize(index_symbol = :nifty, custom_config: {})
    @index_symbol = normalize_index_symbol(index_symbol)
    @custom_config = custom_config || {}
    @config = load_configuration
    @indicators = nil
    @bias_summary = nil
    @error = nil
  end

  # Main entry point following ApplicationService pattern
  # Accepts optional timeframes and days_back, but uses configured defaults if not provided
  def call(timeframes: nil, days_back: nil)
    return failure_result('DhanHQ credentials not configured') unless valid_credentials?

    # Use configured values if not provided, allow runtime override
    effective_timeframes = timeframes || @config[:timeframes]
    effective_days_back = days_back || @config[:api_settings][:days_back]

    begin
      compute_indicators(effective_timeframes, effective_days_back)
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

  # === CONFIGURATION MANAGEMENT ===

  def load_configuration
    # Start with base index configuration
    base_config = INDEX_BASE_CONFIG[@index_symbol] || INDEX_BASE_CONFIG[:nifty]

    # Merge with configuration from IndexConfigLoader if available
    index_configs = IndexConfigLoader.load_indices
    matching = index_configs.find { |cfg| cfg[:key].to_s.downcase == @index_symbol.to_s }

    if matching
      base_config = base_config.merge(
        security_id: (matching[:sid] || matching['sid']).to_s,
        exchange_segment: matching[:segment] || matching['segment'] || 'IDX_I',
        instrument: 'INDEX',
        symbol: (matching[:key] || matching['key']).to_s.upcase
      )
    end

    # Load behavior strategies
    ANALYSIS_STRATEGIES.each do |strategy_name, strategy_config|
      strategy_key = strategy_config[:method]
      index_specific = strategy_config[:index_specific][@index_symbol]
      base_config[strategy_key] = (@custom_config[strategy_key] || index_specific || strategy_config[:default]).dup
    end

    # Add convenience accessors
    base_config[:timeframes] = base_config[:select_timeframes]
    base_config[:indicator_periods] = base_config[:configure_indicator_periods]
    base_config[:bias_thresholds] = base_config[:configure_bias_thresholds]
    base_config[:api_settings] = base_config[:configure_api_settings]

    base_config
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
      # Use configured API settings
      api_settings = @config[:api_settings]
      ta = TA::TechnicalAnalysis.new(
        throttle_seconds: api_settings[:throttle_seconds],
        max_retries: api_settings[:max_retries]
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

    # Use configured indicator periods
    periods = @config[:indicator_periods]

    # Fetch OHLC data for each timeframe
    indicators_data = {}
    timeframes.each do |tf|
      begin
        ohlc = instrument.intraday_ohlc(interval: tf, days_back: days_back)
        next unless ohlc&.any?

        # Compute basic indicators using existing infrastructure with configured periods
        series = CandleSeries.new(symbol: instrument.symbol_name, interval: tf)
        ohlc.each { |candle| series.add_candle(candle) }

        indicators_data[tf] = {
          rsi: series.rsi(periods[:rsi]),
          adx: series.adx(periods[:adx]),
          macd: series.macd(periods[:macd_fast], periods[:macd_slow], periods[:macd_signal]),
          atr: series.atr(periods[:atr])
        }
      rescue StandardError => e
        log_error("Failed to compute indicators for #{tf}min: #{e.class} - #{e.message}")
      end
    end

    @indicators = indicators_data.present? ? indicators_data : nil
  end

  def generate_fallback_bias_summary
    # Generate a simple bias summary from fallback indicators using configured thresholds
    return nil unless @indicators&.any?

    thresholds = @config[:bias_thresholds]
    bullish_count = 0
    bearish_count = 0
    total_count = 0

    @indicators.each_value do |tf_data|
      next unless tf_data.is_a?(Hash)

      # Use configured RSI thresholds for bias determination
      rsi = tf_data[:rsi]
      if rsi
        bullish_count += 1 if rsi < thresholds[:rsi_bullish_threshold]
        bearish_count += 1 if rsi > thresholds[:rsi_bearish_threshold]
        total_count += 1
      end
    end

    # Require minimum timeframes for signal (configured)
    min_timeframes = thresholds[:min_timeframes_for_signal]
    return {
      meta: { source: :fallback, timeframes: @indicators.keys },
      summary: {
        bias: :neutral,
        confidence: 0.0,
        rationale: {
          rsi: "Insufficient timeframes for signal (need #{min_timeframes}, got #{total_count})",
          method: 'fallback_analysis'
        }
      }
    } if total_count < min_timeframes

    bias = if bullish_count > bearish_count && bullish_count > total_count / 2
             :bullish
           elsif bearish_count > bullish_count && bearish_count > total_count / 2
             :bearish
           else
             :neutral
           end

    # Calculate confidence with configured base
    base_confidence = thresholds[:confidence_base]
    agreement_ratio = (bullish_count + bearish_count).to_f / [total_count, 1].max
    confidence = [base_confidence + (agreement_ratio * (1.0 - base_confidence)), 1.0].min

    {
      meta: { source: :fallback, timeframes: @indicators.keys },
      summary: {
        bias: bias,
        confidence: confidence,
        rationale: {
          rsi: "RSI analysis across #{@indicators.keys.join(', ')}min timeframes " \
               "(bullish: #{bullish_count}, bearish: #{bearish_count})",
          method: 'fallback_analysis',
          thresholds: {
            bullish: thresholds[:rsi_bullish_threshold],
            bearish: thresholds[:rsi_bearish_threshold]
          }
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
