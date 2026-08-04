# app/services/backtest_service.rb
# frozen_string_literal: true

class BacktestService
  attr_reader :instrument, :interval, :days_back, :strategy_class, :results

  def initialize(symbol:, interval: '5', days_back: 90, strategy: SupertrendBacktestStrategy)
    @interval = interval
    @days_back = days_back
    @strategy_class = strategy
    @results = []

    ActiveSupport::Notifications.instrument('backtest.instrument_lookup', symbol: symbol) do
      @instrument = Instrument.segment_index.find_by(symbol_name: symbol)
    end

    unless @instrument
      ActiveSupport::Notifications.instrument('backtest.instrument_missing', symbol: symbol)
      raise "Instrument #{symbol} not found"
    end

    @option_sim = Backtest::OptionTradeSimulator.new(instrument: @instrument)

    instrument_event('instrument_ready', instrument_code: @instrument.instrument_code, segment: @instrument.segment)
    instrument_event('initialized', strategy: strategy_name)
  end

  def self.run(symbol:, interval: '5', days_back: 90, strategy: SupertrendBacktestStrategy)
    service = new(symbol: symbol, interval: interval, days_back: days_back, strategy: strategy)
    service.execute
    service
  end

  # Standard entry-point alias — prefer `.call` across all service objects
  singleton_class.send(:alias_method, :call, :run)

  def execute
    instrument_event('execute.start')
    Rails.logger.info("[Backtest] Starting backtest for #{instrument.symbol_name}")

    # Fetch historical OHLC data
    ohlc_data = instrument_event('ohlc.fetch') { fetch_ohlc_data }
    return { error: 'No OHLC data available' } if ohlc_data.blank?

    instrument_event('ohlc.received', candles: ohlc_data.size)

    # Create CandleSeries
    series = instrument_event('series.build', raw_candles: ohlc_data.size) { build_candle_series(ohlc_data) }
    @series = series
    return { error: 'Failed to build candle series' } if series.candles.empty?

    instrument_event('series.ready', candles: series.candles.size)

    # Initialize strategy
    strategy = instrument_event('strategy.initialize') { instantiate_strategy(series) }
    instrument_event('strategy.ready', strategy_class: strategy.class.name)

    # Simulate bar-by-bar
    instrument_event('simulation.run', candles: series.candles.size) { simulate_trading(series, strategy) }

    Rails.logger.info("[Backtest] Completed: #{@results.size} trades")
    instrument_event('execute.complete', trades: @results.size)
    instrument_event('execute.no_trades') if @results.empty?
    self
  end

  def summary
    return {} if @results.empty?

    wins = @results.select { |r| r[:pnl_percent].positive? }
    losses = @results.select { |r| r[:pnl_percent] <= 0 }
    trade_count = @results.size
    win_total_percent = wins.sum { |w| w[:pnl_percent] }
    loss_total_percent = losses.sum { |l| l[:pnl_percent] }
    total_pnl_percent = @results.sum { |r| r[:pnl_percent] }

    {
      total_trades: trade_count,
      winning_trades: wins.size,
      losing_trades: losses.size,
      win_rate: (wins.size.to_f / trade_count * 100).round(2),
      avg_win_percent: wins.any? ? (win_total_percent / wins.size.to_f).round(2) : 0,
      avg_loss_percent: losses.any? ? (loss_total_percent / losses.size.to_f).round(2) : 0,
      total_pnl_percent: total_pnl_percent.round(2),
      expectancy: (total_pnl_percent / trade_count.to_f).round(2),
      max_win: wins.any? ? wins.max_by { |w| w[:pnl_percent] }[:pnl_percent].round(2) : 0,
      max_loss: losses.any? ? losses.min_by { |l| l[:pnl_percent] }[:pnl_percent].round(2) : 0,
      trades: @results
    }
  end

  def print_summary
    s = summary
    return Rails.logger.debug 'No trades executed' if s.empty?

    separator = '=' * 60
    divider = '-' * 60

    Rails.logger.debug { "\n#{separator}" }
    Rails.logger.debug { "BACKTEST RESULTS: #{instrument.symbol_name}" }
    Rails.logger.debug separator
    Rails.logger.debug { "Period: Last #{days_back} days | Interval: #{interval} min" }
    Rails.logger.debug divider
    Rails.logger.debug { "Total Trades:      #{s[:total_trades]}" }
    Rails.logger.debug { "Winning Trades:    #{s[:winning_trades]} (#{s[:win_rate]}%)" }
    Rails.logger.debug { "Losing Trades:     #{s[:losing_trades]}" }
    Rails.logger.debug divider
    Rails.logger.debug { "Avg Win:           +#{s[:avg_win_percent]}%" }
    Rails.logger.debug { "Avg Loss:          #{s[:avg_loss_percent]}%" }
    Rails.logger.debug { "Max Win:           +#{s[:max_win]}%" }
    Rails.logger.debug { "Max Loss:          #{s[:max_loss]}%" }
    Rails.logger.debug divider
    Rails.logger.debug { "Total P&L:         #{'+' if s[:total_pnl_percent].positive?}#{s[:total_pnl_percent]}%" }
    Rails.logger.debug { "Expectancy:        #{'+' if s[:expectancy].positive?}#{s[:expectancy]}% per trade" }
    Rails.logger.debug { "#{separator}\n" }
  end

  private

  def fetch_ohlc_data
    to_date = Time.zone.today - 1.day
    from_date = to_date - @days_back.days
    # Adjust from_date back if it's a weekend
    from_date -= 1.day while from_date.saturday? || from_date.sunday?

    @instrument.intraday_ohlc(
      interval: @interval,
      from_date: from_date.to_s,
      to_date: to_date.to_s,
      days: @days_back
    )
  rescue StandardError => e
    Rails.logger.error("[Backtest] Failed to fetch OHLC: #{e.message}")
    nil
  end

  def build_candle_series(ohlc_data)
    series = CandleSeries.new(symbol: @instrument.symbol_name, interval: @interval)
    series.load_from_raw(ohlc_data)
    series
  end

  # ----------------------------- UPDATED SECTION -----------------------------
  def simulate_trading(series, strategy)
    open_position = nil
    i = 0

    while i < series.candles.size
      candle = series.candles[i]

      if open_position
        exit_result = check_exit(open_position, candle, i, series)
        if exit_result
          @results << exit_result
          open_position = nil
          instrument_event('trade.exited', exit_result)
        end
      end

      if open_position.nil?
        signal = strategy.generate_signal(i)
        open_position = enter_position(signal, candle, i) if signal
      end

      i += 1
    end

    return unless open_position

    last_candle = series.candles.last
    exit_result = force_exit(open_position, last_candle, series.candles.size - 1, 'end_of_data')
    @results << exit_result
  end

  def enter_position(signal, candle, index)
    option_data = fetch_option_series(signal[:type], candle.timestamp)
    return if option_data.blank?

    entry_premium = fetch_premium_price(option_data, candle.timestamp)

    position = {
      signal_type: signal[:type],
      entry_index: index,
      entry_time: candle.timestamp,
      entry_price: entry_premium,
      option_data: option_data,
      stop_loss: calculate_stop_loss(entry_premium, signal[:type]),
      target: calculate_target(entry_premium, signal[:type])
    }

    instrument_event('trade.entered', position)
    position
  end

  # removed duplicate check_exit (option-premium based) to avoid method redefinition

  # ------------------------- NEW METHODS --------------------------

  def fetch_option_series(type, date)
    fetcher = Options::ExpiredFetcher.call(symbol: @instrument.symbol_name, expiry_flag: 'WEEK', date: date)
    fetcher[type]
  rescue StandardError => e
    Rails.logger.error("[Backtest] fetch_option_series failed: #{e.message}")
    []
  end

  def fetch_premium_price(option_data, ts)
    # get closest timestamp bar
    return 0.0 if option_data.blank?

    bar = option_data.min_by { |b| (b[:timestamp] - ts).abs }
    bar[:close].to_f
  end

    last_candle = series.candles.last
    exit_result = option_force_exit(open_position, last_candle, series.candles.size - 1, 'end_of_data')
    @results << exit_result
  end

  def option_enter_position(signal, candle, index)
    position = @option_sim.enter_position(signal, candle, index)
    instrument_event('trade.entered', position) if position
    position
  end

  def option_check_exit(position, candle, index, series)
    result = @option_sim.check_exit(position, candle, index, series)
    instrument_event('trade.exit_evaluated', result) if result
    result
  end

  def option_force_exit(position, candle, index, reason)
    result = @option_sim.force_exit(position, candle, index, reason)
    instrument_event('trade.exit_evaluated', result)
    result
  end

  def instrument_event(event, extra_payload = {}, &)
    payload = base_payload.merge(extra_payload)
    if block_given?
      ActiveSupport::Notifications.instrument("backtest.#{event}", payload, &)
    else
      ActiveSupport::Notifications.instrument("backtest.#{event}", payload)
    end
  end

  def instantiate_strategy(series)
    if @strategy_class.respond_to?(:call)
      # It's a proc/lambda - call it with series
      @strategy_class.call(series)
    else
      # It's a class - instantiate it
      @strategy_class.new(series: series)
    end
  end

  def strategy_name
    if @strategy_class.respond_to?(:call)
      # For procs/lambdas, use a generic name
      # The actual strategy class name will be available after instantiation
      'CustomStrategy'
    else
      @strategy_class.name
    end
  end

  def base_payload
    {
      symbol: instrument&.symbol_name,
      instrument_id: instrument&.id,
      interval: interval,
      days_back: days_back,
      strategy: strategy_name
    }.compact
  end
end
