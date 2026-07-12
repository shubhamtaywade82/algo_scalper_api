# frozen_string_literal: true

require 'date'
require 'json'
require_relative '../utils/logger'

module Backtest
  # Options Backtesting Engine
  # Simulates intraday trades with Spot-based signaling and 1m Option-based execution
  class OptionsBacktestEngine
    # Trade states
    STATES = {
      idle: 'IDLE',
      signal_detected: 'SIGNAL_DETECTED',
      position_open: 'POSITION_OPEN'
    }.freeze

    # Constants
    STT_RATE = 0.0005
    MARGIN_REQUIREMENT = 0.30
    MIN_STOP_LOSS_PCT = 0.015
    DEFAULT_POSITION_SIZE_PCT = 0.025
    NSE_CLOSE_TIME = 15 * 3600 + 15 * 60 # 3:15 PM IST
    ENTRY_BUFFER_SECONDS = 2 * 60

    def initialize(capital:, logger: nil)
      @capital = capital.to_f
      @logger = logger || Utils::Logger
      @state = STATES[:idle]
      @trades = []
      @current_position = nil
      @equity = capital.to_f
      @peak_equity = capital.to_f
    end

    # @param symbol [String]
    # @param spot_bars [Array] Strategy-interval bars for signaling
    # @param option_bars [Array] 1m bars for execution
    # @param strategy [BaseStrategy]
    # @param interval [Integer] Spot interval in minutes
    def backtest(symbol:, spot_bars:, option_bars:, strategy:, interval: 5)
      validate_bars(spot_bars, option_bars)
      
      @logger.info("system.backtest_start", symbol: symbol, spot_count: spot_bars.size, opt_count: option_bars.size)
      
      interval_seconds = interval.to_i * 60
      last_processed_spot_idx = -1

      option_bars.each do |opt_bar|
        # 1. Synchronize: Find the latest CLOSED spot bar
        # A spot bar starting at T is closed at T + interval_seconds
        current_spot_idx = find_latest_closed_spot_idx(spot_bars, opt_bar[:timestamp], interval_seconds)
        
        if current_spot_idx > last_processed_spot_idx
          # New spot candle(s) closed! Update strategy.
          (last_processed_spot_idx + 1..current_spot_idx).each do |idx|
            strategy.add_bar(spot_bars[idx])
          end
          last_processed_spot_idx = current_spot_idx
          
          # Check for new signal if idle
          if @state == STATES[:idle]
            check_for_signal(opt_bar, symbol, strategy)
          end
        end

        # 2. Process FSM logic on 1m bars
        process_execution_bar(opt_bar, symbol, strategy)
      end

      # Close any open position at end
      close_position_at_market(option_bars.last, symbol) if @current_position

      generate_report
    end

    private

    def find_latest_closed_spot_idx(spot_bars, current_time, interval_seconds)
      # We want the highest index 'i' such that spot_bars[i][:timestamp] + interval_seconds <= current_time
      idx = spot_bars.index { |b| b[:timestamp] + interval_seconds > current_time }
      idx ? idx - 1 : spot_bars.size - 1
    end

    def process_execution_bar(bar, symbol, strategy)
      current_time_seconds = bar[:timestamp].to_i % 86400

      # Auto-exit at market close
      if current_time_seconds >= NSE_CLOSE_TIME
        close_position_at_market(bar, symbol) if @current_position
        return
      end

      case @state
      when STATES[:signal_detected]
        execute_entry(bar, symbol)
      when STATES[:position_open]
        manage_open_position(bar, symbol, strategy)
      end
    end

    def check_for_signal(bar, symbol, strategy)
      signal = strategy.signal
      return unless signal && signal[:action] == 'BUY'

      @logger.info("strategy.signal_detected", time: format_time(bar[:timestamp]), action: signal[:action], symbol: symbol)
      @state = STATES[:signal_detected]
      @current_position = {
        symbol: symbol,
        signal: signal,
        entry_trigger_time: bar[:timestamp]
      }
    end

    def execute_entry(bar, symbol)
      signal = @current_position[:signal]
      entry_price = bar[:open] # Enter at Open of the 1m candle following the signal
      
      position_size_amount = @equity * DEFAULT_POSITION_SIZE_PCT
      quantity = (position_size_amount / entry_price).floor
      
      if quantity <= 0
        @state = STATES[:idle]
        @current_position = nil
        return
      end

      direction = signal[:direction] || 'LONG'
      stop_loss = calculate_stop_loss(entry_price, direction)
      stop_loss_distance = (entry_price - stop_loss).abs

      # Regulatory costs
      contract_value = entry_price * quantity
      stt = contract_value * STT_RATE
      margin_required = contract_value * MARGIN_REQUIREMENT
      
      if (margin_required + stt) > @equity
        @state = STATES[:idle]
        @current_position = nil
        return
      end

      @current_position.merge!(
        state: STATES[:position_open],
        entry_price: entry_price,
        quantity: quantity,
        stop_loss: stop_loss,
        tp: entry_price * 1.20, # 20% target
        stt_entry: stt,
        margin_required: margin_required,
        entry_time: bar[:timestamp]
      )

      @equity -= (margin_required + stt)
      @logger.info("trade.entry", time: format_time(bar[:timestamp]), symbol: symbol, price: entry_price, qty: quantity)
      @state = STATES[:position_open]
    end

    def manage_open_position(bar, symbol, strategy)
      pos = @current_position
      
      # 1. Check Stop Loss (using 1m High/Low)
      if bar[:low] <= pos[:stop_loss]
        realize_pnl(pos[:stop_loss], symbol, bar, 'STOP_LOSS')
        return
      end

      # 2. Check Profit Target
      if bar[:high] >= pos[:tp]
        realize_pnl(pos[:tp], symbol, bar, 'TARGET')
        return
      end

      # 3. Strategy Exit
      if strategy.signal[:action] == 'SELL'
        realize_pnl(bar[:close], symbol, bar, 'STRATEGY_EXIT')
        return
      end

      # 4. Theta/Time Buffer
      time_elapsed = bar[:timestamp].to_i - pos[:entry_time].to_i
      if time_elapsed >= ENTRY_BUFFER_SECONDS && bar[:close] < pos[:entry_price] * 0.98
        realize_pnl(bar[:close], symbol, bar, 'THETA_DECAY')
      end
    end

    def realize_pnl(exit_price, symbol, bar, reason)
      pos = @current_position
      stt_exit = (exit_price * pos[:quantity]) * STT_RATE
      
      gross_pnl = (exit_price - pos[:entry_price]) * pos[:quantity]
      net_pnl = gross_pnl - (pos[:stt_entry] + stt_exit)
      pnl_pct = (net_pnl / (pos[:entry_price] * pos[:quantity])) * 100

      @equity += pos[:margin_required] + gross_pnl - stt_exit
      @peak_equity = [@peak_equity, @equity].max

      @trades << {
        symbol: symbol,
        entry_price: pos[:entry_price].to_f,
        exit_price: exit_price.to_f,
        quantity: pos[:quantity],
        entry_time: pos[:entry_time],
        exit_time: bar[:timestamp],
        pnl: net_pnl.to_f.round(2),
        pnl_pct: pnl_pct.to_f.round(2),
        status: net_pnl.positive? ? 'WIN' : 'LOSS',
        reason: reason
      }

      @logger.info("trade.exit", time: format_time(bar[:timestamp]), symbol: symbol, price: exit_price, pnl: net_pnl.round(2), reason: reason)
      @state = STATES[:idle]
      @current_position = nil
    end

    def close_position_at_market(bar, symbol)
      realize_pnl(bar[:close], symbol, bar, 'MARKET_CLOSE')
    end

    def calculate_stop_loss(price, dir)
      dir == 'SHORT' ? price * (1 + MIN_STOP_LOSS_PCT) : price * (1 - MIN_STOP_LOSS_PCT)
    end

    def validate_bars(spot, opt)
      raise ArgumentError, "Spot or Option bars missing" if spot.empty? || opt.empty?
    end

    def generate_report
      total_trades = @trades.length
      wins = @trades.count { |t| t[:status] == 'WIN' }
      total_pnl = @trades.sum { |t| t[:pnl].to_f }
      
      {
        summary: {
          total_trades: total_trades,
          win_rate: total_trades.positive? ? "#{(wins.to_f / total_trades * 100).round(2)}%" : "0%",
          total_pnl: "₹#{total_pnl.round(2)}",
          total_pnl_val: total_pnl.round(2),
          total_pnl_pct: "#{((total_pnl / (@equity - total_pnl)) * 100).round(2)}%",
          starting_capital: "₹#{(@equity - total_pnl).round(2)}",
          ending_capital: "₹#{@equity.round(2)}",
          max_drawdown: "#{calculate_max_drawdown.round(2)}%",
          drawdown: calculate_max_drawdown.round(2),
          sharpe_ratio: calculate_sharpe_ratio.round(2),
          profit_factor: calculate_profit_factor.round(2)
        },
        trades: @trades
      }
    end

    def calculate_profit_factor
      profits = @trades.select { |t| t[:pnl] > 0 }.sum { |t| t[:pnl] }
      losses = @trades.select { |t| t[:pnl] < 0 }.sum { |t| t[:pnl] }.abs
      return profits.positive? ? 99.0 : 0.0 if losses.zero?
      profits / losses
    end

    def calculate_max_drawdown
      return 0.0 if @trades.empty?
      curve = [@capital]; @trades.each { |t| curve << curve.last + t[:pnl] }
      max_peak = curve.first; max_dd = 0.0
      curve.each { |e| max_peak = [max_peak, e].max; dd = (max_peak - e) / max_peak; max_dd = [max_dd, dd].max }
      max_dd * 100
    end

    def calculate_sharpe_ratio
      return 0.0 if @trades.size < 2
      returns = @trades.map { |t| t[:pnl_pct] }
      avg = returns.sum / returns.size.to_f
      sd = Math.sqrt(returns.map { |r| (r - avg)**2 }.sum / (returns.size - 1))
      sd.zero? ? 0.0 : (avg / sd) * Math.sqrt(252)
    end

    def format_time(ts)
      Time.at(ts.to_i).strftime('%H:%M:%S')
    end
  end
end
