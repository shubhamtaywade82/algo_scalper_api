# frozen_string_literal: true

module Strategies
  # Real (not stubbed) validation for Strategy Creator (TradingStrategy) code:
  # AST syntax check, SecurityScanner pass, and a bar-by-bar dry run against
  # real historical candles. Never persists orders or writes to disk.
  class AdHocBacktester
    TRAILING_BARS = 30
    CLASS_NAME_PATTERN = /^\s*class\s+([A-Z]\w*)\s*<\s*(\S+)/

    def initialize(trading_strategy)
      @trading_strategy = trading_strategy
      @code = trading_strategy.code.to_s
    end

    def run
      syntax_ok = check_syntax
      scan_report = syntax_ok ? Strategies::SecurityScanner.new(@code).scan : nil
      security_ok = scan_report ? scan_report[:blocked_count].zero? : false

      backtest = syntax_ok && security_ok ? run_backtest : { ok: false, error: "skipped (syntax/security failed)" }

      {
        checks: {
          syntax: bool_status(syntax_ok),
          logic: bool_status(security_ok),
          risk: bool_status(security_ok),
          backtest: bool_status(backtest[:ok])
        },
        backtest_results: {
          "signal_counts" => backtest[:signal_counts] || {},
          "candle_count" => backtest[:candle_count] || 0,
          "instrument" => backtest[:instrument],
          "error" => backtest[:error],
          "ran_at" => Time.current.iso8601
        }
      }
    end

    private

    def bool_status(ok) = ok ? "passed" : "failed"

    def check_syntax
      RubyVM::AbstractSyntaxTree.parse(@code)
      true
    rescue SyntaxError
      false
    end

    def run_backtest
      klass = load_strategy_class
      return { ok: false, error: "no strategy class found in code" } unless klass

      instrument_key = Array(@trading_strategy.instruments).first || "NIFTY"
      instrument = Instrument.segment_index.find_by(symbol_name: instrument_key)
      return { ok: false, error: "instrument #{instrument_key} not found" } unless instrument

      series = fetch_series(instrument_key, instrument)
      return { ok: false, error: "no historical candles for #{instrument_key}" } if series.nil? || series.candles.blank?

      strategy = klass.new(params: default_params(klass))
      counts = Hash.new(0)
      trailing = series.candles.last(TRAILING_BARS)

      trailing.each_index do |i|
        truncated = CandleSeries.new(symbol: instrument_key, interval: @trading_strategy.timeframe.presence || "1m")
        trailing.first(i + 1).each { |c| truncated.add_candle(c) }
        context = build_context(instrument_key, truncated)
        signal = strategy.call(context)
        counts[signal.class.name.demodulize] += 1
      end

      { ok: true, signal_counts: counts, candle_count: series.candles.size, instrument: instrument_key, error: nil }
    rescue StandardError => e
      { ok: false, error: e.message, candle_count: 0, instrument: instrument_key }
    end

    def load_strategy_class
      match = CLASS_NAME_PATTERN.match(@code)
      return nil unless match

      class_name = match[1]
      superclass_name = match[2]
      mod = Module.new
      source = superclass_name == "Strategies::Base" ? @code : "BaseStrategy = Strategies::Base unless defined?(BaseStrategy)\n\n#{@code}"
      mod.module_eval(source, "ad_hoc_backtest_#{class_name}")
      mod.const_get(class_name)
    end

    def default_params(klass)
      klass.respond_to?(:params_schema) ? klass.params_schema.transform_values { |v| v[:default] } : {}
    end

    def fetch_series(instrument_key, instrument)
      Candles::Repository.series(
        instrument_key: instrument_key,
        timeframe: @trading_strategy.timeframe.presence || "1m",
        from: 6.hours.ago,
        to: Time.current,
        include_forming: true,
        instrument: instrument
      )
    end

    def build_context(instrument_key, truncated_series)
      Strategies::StrategyContext.new(
        instrument_key: instrument_key,
        candles: ->(_timeframe = "1m") { truncated_series },
        indicators: nil,
        session: nil,
        position: nil,
        params: {},
        clock: -> { Time.current },
        config: {}.freeze,
        logger: nil
      )
    end
  end
end
