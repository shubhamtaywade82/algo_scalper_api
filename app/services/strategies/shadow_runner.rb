# frozen_string_literal: true

module Strategies
  # Shadow-mode harness for Phase 2.
  #
  # Runs alongside the frozen {Signal::Scheduler} / {Signal::Engine} without
  # modifying them. For each index cycle, it builds a {StrategyContext} and
  # invokes the strategy plugin, then logs how the plugin's decision compares
  # to the engine's decision (read from the last {TradingSignal}).
  #
  # No trading happens through the plugin — all signals are logged with
  # +outcome: "shadow"+ .
  class ShadowRunner
    PERIOD = 30 # seconds, matches Signal::Scheduler::DEFAULT_PERIOD

    def initialize(strategy:, instruments:, context_builder: nil)
      @strategy = strategy
      @instruments = instruments
      @context_builder = context_builder || ContextBuilder.new
      @running = false
    end

    def start
      return if @running

      @running = true
      @thread = Thread.new { run_loop }
      Rails.logger.info("[Strategies::ShadowRunner] started for #{@strategy.class.name}")
    end

    def stop
      @running = false
      @thread&.kill
      Rails.logger.info("[Strategies::ShadowRunner] stopped")
    end

    def running? = @running

    private

    def run_loop
      while @running
        cycle_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        run_cycle
        sleep_time = PERIOD - (Process.clock_gettime(Process::CLOCK_MONOTONIC) - cycle_start)
        sleep(sleep_time) if sleep_time.positive?
      end
    rescue StandardError => e
      Rails.logger.error("[Strategies::ShadowRunner] loop error: #{e.class} - #{e.message}")
      @running = false
    end

    def run_cycle
      @instruments.each do |instrument_key|
        instrument = find_instrument(instrument_key)
        next unless instrument
        next unless TradingSession::Service.market_open?

        evaluate(instrument)
      rescue StandardError => e
        Rails.logger.warn("[Strategies::ShadowRunner] error for #{instrument_key}: #{e.message}")
      end
    end

    def evaluate(instrument)
      context = @context_builder.build(
        instrument: instrument,
        strategy: @strategy,
        params: resolve_params,
        config: {}
      )

      signal = @strategy.call(context)

      engine_signal = TradingSignal.where(index_key: instrument.symbol_name)
                                   .order(created_at: :desc)
                                   .first

      log_comparison(instrument.symbol_name, signal, engine_signal)
    rescue StandardError => e
      Rails.logger.warn("[Strategies::ShadowRunner] #{instrument.symbol_name} crash: #{e.message}")
    end

    def log_comparison(instrument_key, plugin_signal, engine_signal)
      plugin_action = action_label(plugin_signal)
      engine_action = engine_signal ? engine_signal.direction : "none"

      if plugin_action == engine_action || (plugin_action == "hold" && engine_action == "avoid")
        Rails.logger.debug("[ShadowRunner] #{instrument_key} MATCH plugin=#{plugin_action} engine=#{engine_action}")
      else
        Rails.logger.info("[ShadowRunner] #{instrument_key} DIFF  plugin=#{plugin_action} engine=#{engine_action} " \
                          "reason=#{plugin_signal.reason}")
      end
    end

    def action_label(signal)
      case signal
      when Signals::BuyCall then "bullish"
      when Signals::BuyPut then "bearish"
      when Signals::Exit then "exit"
      else "hold"
      end
    end

    def find_instrument(key)
      Instrument.find_by(symbol_name: key) ||
        Instrument.find_by(trading_symbol: key)
    end

    def resolve_params
      @strategy.class.params_schema.transform_values { |v| v[:default] }

    end
  end
end
