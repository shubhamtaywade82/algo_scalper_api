# frozen_string_literal: true

module Backtest
  # Option premium simulation (CE/PE) extracted for reuse by {BacktestService} and {Backtest::SmcReplayRunner}.
  class OptionTradeSimulator
    def initialize(instrument:)
      @instrument = instrument
    end

    # @param signal [Hash] must include :type (:ce or :pe)
    # @return [Hash, nil] position hash or nil if no option data
    def enter_position(signal, candle, index)
      signal_type = signal[:type]
      option_data = fetch_option_series(signal_type, candle.timestamp)
      return if option_data.blank?

      entry_premium = fetch_premium_price(option_data, candle.timestamp)

      {
        signal_type: signal_type,
        entry_index: index,
        entry_time: candle.timestamp,
        entry_price: entry_premium,
        option_data: option_data,
        stop_loss: calculate_stop_loss(entry_premium, signal_type),
        target: calculate_target(entry_premium, signal_type)
      }
    end

    def check_exit(position, candle, index, _series)
      current_price = fetch_premium_price(position[:option_data], candle.timestamp)
      entry_price = position[:entry_price]
      signal_type = position[:signal_type]

      pnl_percent = if signal_type == :ce
                      ((current_price - entry_price) / entry_price * 100)
                    else
                      ((entry_price - current_price) / entry_price * 100)
                    end

      target_hit =
        (signal_type == :ce && current_price >= position[:target]) ||
        (signal_type == :pe && current_price <= position[:target])
      return build_exit_result(position, candle, index, pnl_percent, 'target') if target_hit

      stop_loss_hit =
        (signal_type == :ce && current_price <= position[:stop_loss]) ||
        (signal_type == :pe && current_price >= position[:stop_loss])
      return build_exit_result(position, candle, index, pnl_percent, 'stop_loss') if stop_loss_hit

      if pnl_percent >= 40 && !position[:trailing_activated]
        position[:trailing_activated] = true
        position[:trailing_stop] = current_price * (signal_type == :ce ? 0.90 : 1.10)
      end

      if position[:trailing_activated]
        if signal_type == :ce
          new_trailing = current_price * 0.90
          position[:trailing_stop] = [position[:trailing_stop], new_trailing].max
          if current_price <= position[:trailing_stop]
            return build_exit_result(position, candle, index, pnl_percent, 'trailing_stop')
          end
        else
          new_trailing = current_price * 1.10
          position[:trailing_stop] = [position[:trailing_stop], new_trailing].min
          if current_price >= position[:trailing_stop]
            return build_exit_result(position, candle, index, pnl_percent, 'trailing_stop')
          end
        end
      end

      if candle.timestamp.hour >= 15 && candle.timestamp.min >= 20
        return build_exit_result(position, candle, index, pnl_percent, 'time_exit')
      end

      nil
    end

    def force_exit(position, candle, index, reason)
      current_price = fetch_premium_price(position[:option_data], candle.timestamp)
      entry_price = position[:entry_price]
      signal_type = position[:signal_type]

      pnl_percent = if signal_type == :ce
                      ((current_price - entry_price) / entry_price * 100)
                    else
                      ((entry_price - current_price) / entry_price * 100)
                    end

      build_exit_result(position, candle, index, pnl_percent, reason)
    end

    # One trade from entry bar to exit (same semantics as {BacktestService} loop).
    def simulate_trade(series:, entry_index:, signal_type:)
      signal = { type: signal_type }
      candle = series.candles[entry_index]
      position = enter_position(signal, candle, entry_index)
      return nil if position.blank?

      ((entry_index + 1)...series.candles.size).each do |j|
        c = series.candles[j]
        hit = check_exit(position, c, j, series)
        return hit.merge(exit_bar_index: j) if hit
      end

      last_idx = series.candles.size - 1
      last = series.candles[last_idx]
      force_exit(position, last, last_idx, 'end_of_data').merge(exit_bar_index: last_idx)
    end

    private

    def fetch_option_series(type, date)
      fetcher = Options::ExpiredFetcher.call(symbol: @instrument.symbol_name, expiry_flag: 'WEEK', date: date)
      fetcher[type]
    rescue StandardError => e
      Rails.logger.error("[OptionTradeSimulator] fetch_option_series failed: #{e.message}")
      []
    end

    def fetch_premium_price(option_data, ts)
      return 0.0 if option_data.blank?

      bar = option_data.min_by { |b| (b[:timestamp] - ts).abs }
      bar[:close].to_f
    end

    def calculate_stop_loss(entry_price, signal_type)
      if signal_type == :ce
        entry_price * 0.70
      else
        entry_price * 1.30
      end
    end

    def calculate_target(entry_price, signal_type)
      if signal_type == :ce
        entry_price * 1.50
      else
        entry_price * 0.50
      end
    end

    def build_exit_result(position, candle, index, pnl_percent, exit_reason)
      {
        signal_type: position[:signal_type],
        entry_time: position[:entry_time],
        entry_price: position[:entry_price],
        exit_time: candle.timestamp,
        exit_price: candle.close,
        pnl_percent: pnl_percent.round(2),
        exit_reason: exit_reason,
        bars_held: index - position[:entry_index],
        exit_bar_index: index
      }
    end
  end
end
