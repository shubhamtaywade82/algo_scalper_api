# frozen_string_literal: true

module Backtest
  # Same two-phase engine/exit-simulation as OptionsBuyingBacktester, but entry decisions
  # come from a real Strategies::Base plugin (pinned Strategies::Version) instead of the
  # hand-rolled CPR+Choppiness+Vortex+MFI scan. See #evaluate_signal for the parity seam —
  # simulate_trade/build_entry/simulate!/summary/CSV export are untouched, inherited as-is.
  #
  # v1 scope: entry-side parity only. context.position/indicators/session are nil — no
  # shipped strategy reads them today, and MAX_TRADES_PER_DAY=1 means no strategy is ever
  # called mid-position anyway. Exit simulation still comes from the parent's SL/target/
  # giveback/time-stop logic, not Live::ExitEngine.
  class StrategyBacktester < OptionsBuyingBacktester
    def self.call(symbol:, strategy_version:, days_back: 90, params: {}, trading_type: :options, entry_interval: '5')
      service = new(symbol: symbol, days_back: days_back, params: params, trading_type: trading_type, entry_interval: entry_interval)
      service.send(:init_strategy!, strategy_version)
      service.execute
      service
    end

    # Inherited cache key has no strategy-version component — would silently ignore the pin.
    def self.for_sweep(*)
      raise NotImplementedError, 'StrategyBacktester does not support for_sweep (no version in cache key)'
    end

    def summary
      super.merge(
        strategy_slug: @strategy_version.strategy_record.slug,
        strategy_version: @strategy_version.version,
        min_confidence: @min_confidence
      )
    end

    private

    def init_strategy!(strategy_version)
      @strategy_version = strategy_version
      @strategy_class = Strategies::Loader.load_version(strategy_version)
      @strategy_instance = @strategy_class.new(params: strategy_params)
      @min_confidence = (AlgoConfig.fetch.dig(:strategy_platform, :min_confidence) || 0.6).to_f
    end

    def strategy_params
      @strategy_class.params_schema.transform_values { |v| v[:default] }
    end

    # Memoized lazily — @series_1m is only set partway through the parent's #collect_entries
    # (right before the day loop that eventually calls #evaluate_signal), so it isn't available
    # at construction time. By the time #evaluate_signal first runs, it's populated.
    def context_adapter
      @context_adapter ||= StrategyContextAdapter.new(series_1m: @series_1m, symbol: @symbol)
    end

    # Overrides parent's evaluate_signal (options_buying_backtester.rb:378-435). Same
    # return contract: nil, or { type:, price:, reason: } — build_entry needs zero changes.
    def evaluate_signal(candles, _cpr, _vp, current_candle)
      return nil if candles.size < 2
      return nil if current_candle.timestamp.in_time_zone('Asia/Kolkata').hour >= LATEST_ENTRY_HOUR

      cutoff = current_candle.timestamp + @entry_interval.to_i.minutes
      signal = @strategy_instance.call(context_adapter.build(cutoff: cutoff, params: strategy_params))
      map_signal(signal, current_candle)
    end

    def map_signal(signal, current_candle)
      return nil unless signal.respond_to?(:buy_call?) && (signal.buy_call? || signal.buy_put?)
      return nil if signal.respond_to?(:confidence) && signal.confidence < @min_confidence

      bullish = signal.buy_call?
      type = if @trading_type == :futures
               bullish ? :long : :short
             else
               bullish ? :ce : :pe
             end
      {
        type: type,
        price: current_candle.close,
        reason: "#{@strategy_version.strategy_record.slug}@v#{@strategy_version.version} #{signal.reason} conf=#{signal.confidence}"
      }
    end
  end
end
