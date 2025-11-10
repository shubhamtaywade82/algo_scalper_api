# app/services/backtest_service.rb
# frozen_string_literal: true

class BacktestService
  attr_reader :instrument, :interval, :days_back, :strategy_class, :results

  def initialize(symbol:, interval: '5', days_back: 90, strategy: SimpleMomentumStrategy)
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

    instrument_event('instrument_ready', instrument_code: @instrument.instrument_code, segment: @instrument.segment)
    instrument_event('initialized', strategy: strategy_name)
  end

  def self.run(symbol:, interval: '5', days_back: 90, strategy: SimpleMomentumStrategy)
    service = new(symbol: symbol, interval: interval, days_back: days_back, strategy: strategy)
    service.execute
    service
  end

  def execute
    instrument_event('execute.start')
    Rails.logger.info("[Backtest] Starting backtest for #{instrument.symbol_name}")

    # Fetch historical OHLC data
    ohlc_data = instrument_event('ohlc.fetch') { fetch_ohlc_data }
    return { error: 'No OHLC data available' } if ohlc_data.blank?

    instrument_event('ohlc.received', candles: ohlc_data.size)

    # Create CandleSeries
    series = instrument_event('series.build', raw_candles: ohlc_data.size) { build_candle_series(ohlc_data) }
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

    wins = @results.select { |r| r[:pnl_percent] > 0 }
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
    return puts 'No trades executed' if s.empty?

    separator = '=' * 60
    divider = '-' * 60

    puts "\n#{separator}"
    puts "BACKTEST RESULTS: #{instrument.symbol_name}"
    puts separator
    puts "Period: Last #{days_back} days | Interval: #{interval} min"
    puts divider
    puts "Total Trades:      #{s[:total_trades]}"
    puts "Winning Trades:    #{s[:winning_trades]} (#{s[:win_rate]}%)"
    puts "Losing Trades:     #{s[:losing_trades]}"
    puts divider
    puts "Avg Win:           +#{s[:avg_win_percent]}%"
    puts "Avg Loss:          #{s[:avg_loss_percent]}%"
    puts "Max Win:           +#{s[:max_win]}%"
    puts "Max Loss:          #{s[:max_loss]}%"
    puts divider
    puts "Total P&L:         #{'+' if s[:total_pnl_percent] > 0}#{s[:total_pnl_percent]}%"
    puts "Expectancy:        #{'+' if s[:expectancy] > 0}#{s[:expectancy]}% per trade"
    puts "#{separator}\n"
  end

  private

  def fetch_ohlc_data
    to_date = Date.today - 1.day
    from_date = to_date - @days_back.days

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

  def simulate_trading(series, strategy)
    open_position = nil
    i = 0

    while i < series.candles.size
      candle = series.candles[i]

      # Check exit first if position is open
      if open_position
        exit_result = check_exit(open_position, candle, i, series)
        if exit_result
          @results << exit_result
          open_position = nil
          instrument_event('trade.exited', exit_result)
        end
      end

      # Check entry if no position
      if open_position.nil?
        signal = strategy.generate_signal(i)
        open_position = enter_position(signal, candle, i) if signal
      end

      i += 1
    end

    # Close any remaining position at end
    return unless open_position

    last_candle = series.candles.last
    exit_result = force_exit(open_position, last_candle, series.candles.size - 1, 'end_of_data')
    @results << exit_result
    instrument_event('trade.exited', exit_result.merge(force_exit: true))
  end

  def enter_position(signal, candle, index)
    position = {
      signal_type: signal[:type], # :ce or :pe
      entry_index: index,
      entry_time: candle.timestamp,
      entry_price: candle.close, # Simulate entry at close of signal candle
      stop_loss: calculate_stop_loss(candle.close, signal[:type]),
      target: calculate_target(candle.close, signal[:type]),
      trailing_activated: false,
      trailing_stop: nil
    }
    instrument_event('trade.entered', position)
    position
  end

  def calculate_stop_loss(entry_price, signal_type)
    if signal_type == :ce
      entry_price * 0.70 # -30%
    else
      entry_price * 1.30 # +30% (for PE, price going up is a loss)
    end
  end

  def calculate_target(entry_price, signal_type)
    if signal_type == :ce
      entry_price * 1.50 # +50%
    else
      entry_price * 0.50 # -50% (for PE, price going down is profit)
    end
  end

  def check_exit(position, candle, index, _series)
    current_price = candle.close
    entry_price = position[:entry_price]
    signal_type = position[:signal_type]

    # Calculate P&L %
    pnl_percent = if signal_type == :ce
                    ((current_price - entry_price) / entry_price * 100)
                  else # :pe
                    ((entry_price - current_price) / entry_price * 100)
                  end

    # Check target hit
    target_hit =
      (signal_type == :ce && current_price >= position[:target]) ||
      (signal_type == :pe && current_price <= position[:target])
    return build_exit_result(position, candle, index, pnl_percent, 'target') if target_hit

    # Check stop loss
    stop_loss_hit =
      (signal_type == :ce && current_price <= position[:stop_loss]) ||
      (signal_type == :pe && current_price >= position[:stop_loss])
    return build_exit_result(position, candle, index, pnl_percent, 'stop_loss') if stop_loss_hit

    # Activate trailing stop at 40% profit
    if pnl_percent >= 40 && !position[:trailing_activated]
      position[:trailing_activated] = true
      position[:trailing_stop] = current_price * (signal_type == :ce ? 0.90 : 1.10) # Trail by 10%
    end

    # Update trailing stop
    if position[:trailing_activated]
      if signal_type == :ce
        new_trailing = current_price * 0.90
        position[:trailing_stop] = [position[:trailing_stop], new_trailing].max

        # Check trailing stop hit
        if current_price <= position[:trailing_stop]
          return build_exit_result(position, candle, index, pnl_percent, 'trailing_stop')
        end
      else # :pe
        new_trailing = current_price * 1.10
        position[:trailing_stop] = [position[:trailing_stop], new_trailing].min

        # Check trailing stop hit
        if current_price >= position[:trailing_stop]
          return build_exit_result(position, candle, index, pnl_percent, 'trailing_stop')
        end
      end
    end

    # Time-based exit (3:20 PM)
    if candle.timestamp.hour >= 15 && candle.timestamp.min >= 20
      return build_exit_result(position, candle, index, pnl_percent, 'time_exit')
    end

    nil # No exit
  end

  def force_exit(position, candle, index, reason)
    current_price = candle.close
    entry_price = position[:entry_price]
    signal_type = position[:signal_type]

    pnl_percent = if signal_type == :ce
                    ((current_price - entry_price) / entry_price * 100)
                  else
                    ((entry_price - current_price) / entry_price * 100)
                  end

    build_exit_result(position, candle, index, pnl_percent, reason)
  end

  def build_exit_result(position, candle, index, pnl_percent, exit_reason)
    result = {
      signal_type: position[:signal_type],
      entry_time: position[:entry_time],
      entry_price: position[:entry_price],
      exit_time: candle.timestamp,
      exit_price: candle.close,
      pnl_percent: pnl_percent.round(2),
      exit_reason: exit_reason,
      bars_held: index - position[:entry_index]
    }
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
