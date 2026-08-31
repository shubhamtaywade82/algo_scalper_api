# frozen_string_literal: true

module Backtest
  # Option premium simulation (CE/PE) extracted for reuse by {BacktestService} and {Backtest::SmcReplayRunner}.
  #
  # ## Same-strike filter
  # DhanHQ's expired-options 'ATM' endpoint returns a *rolling composite* — the ATM strike
  # re-resolves per bar as spot drifts, so a single day's series can flip between adjacent
  # strikes multiple times.  A real position holds ONE strike from entry to exit, so exit
  # simulation must only look at bars that still quote the entry_strike.
  #
  # This was a silent bug: without the filter, the simulator would splice across strikes,
  # producing unrealistically smooth premium paths.  Fixed to mirror the approach in
  # {OptionsBuyingBacktester#same_strike_bars}.
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

      entry_bar = nearest_bar(option_data, candle.timestamp)
      return if entry_bar.nil? || entry_bar[:close].to_f <= 0

      entry_premium = entry_bar[:close].to_f
      entry_strike  = entry_bar[:strike]

      {
        signal_type: signal_type,
        entry_index: index,
        entry_time: candle.timestamp,
        entry_price: entry_premium,
        entry_strike: entry_strike,
        option_data: option_data,
        stop_loss: calculate_stop_loss(entry_premium, signal_type),
        target: calculate_target(entry_premium, signal_type)
      }
    end

    def check_exit(position, candle, index, _series)
      # Filter to only same-strike bars to avoid following the rolling ATM splice
      same_strike = same_strike_bars(position)
      current_price = fetch_premium_price(same_strike, candle.timestamp)
      # If no same-strike bar is available near this timestamp, skip bar
      return nil if current_price.zero?

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
      return build_exit_result(position, candle, index, pnl_percent, current_price, 'target') if target_hit

      stop_loss_hit =
        (signal_type == :ce && current_price <= position[:stop_loss]) ||
        (signal_type == :pe && current_price >= position[:stop_loss])
      return build_exit_result(position, candle, index, pnl_percent, current_price, 'stop_loss') if stop_loss_hit

      if pnl_percent >= 40 && !position[:trailing_activated]
        position[:trailing_activated] = true
        position[:trailing_stop] = current_price * (signal_type == :ce ? 0.90 : 1.10)
      end

      if position[:trailing_activated]
        if signal_type == :ce
          new_trailing = current_price * 0.90
          position[:trailing_stop] = [position[:trailing_stop], new_trailing].max
          if current_price <= position[:trailing_stop]
            return build_exit_result(position, candle, index, pnl_percent, current_price, 'trailing_stop')
          end
        else
          new_trailing = current_price * 1.10
          position[:trailing_stop] = [position[:trailing_stop], new_trailing].min
          if current_price >= position[:trailing_stop]
            return build_exit_result(position, candle, index, pnl_percent, current_price, 'trailing_stop')
          end
        end
      end

      if candle.timestamp.hour >= 15 && candle.timestamp.min >= 20
        return build_exit_result(position, candle, index, pnl_percent, current_price, 'time_exit')
      end

      nil
    end

    def force_exit(position, candle, index, reason)
      same_strike = same_strike_bars(position)
      current_price = fetch_premium_price(same_strike, candle.timestamp)
      current_price = position[:entry_price] * 0.5 if current_price.zero?
      entry_price = position[:entry_price]
      signal_type = position[:signal_type]

      pnl_percent = if signal_type == :ce
                      ((current_price - entry_price) / entry_price * 100)
                    else
                      ((entry_price - current_price) / entry_price * 100)
                    end

      build_exit_result(position, candle, index, pnl_percent, current_price, reason)
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

    # DhanHQ's expired-options 'ATM' series re-resolves the strike per bar as spot drifts —
    # it's a rolling composite, not one contract's continuous price. A real position holds
    # ONE strike from entry to exit, so we must filter to only bars quoting entry_strike.
    def same_strike_bars(position)
      return [] if position[:option_data].blank? || position[:entry_strike].blank?

      position[:option_data].select { |b| b[:strike].to_i == position[:entry_strike].to_i }
    end

    def fetch_option_series(type, date)
      fetcher = Options::ExpiredFetcher.call(symbol: @instrument.symbol_name, expiry_flag: 'WEEK', date: date)
      fetcher[type]
    rescue StandardError => e
      Rails.logger.error("[OptionTradeSimulator] fetch_option_series failed: #{e.message}")
      []
    end

    def nearest_bar(option_data, ts)
      return nil if option_data.blank?

      option_data.min_by { |b| (b[:timestamp] - ts).abs }
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

    def build_exit_result(position, candle, index, pnl_percent, exit_price, exit_reason)
      {
        signal_type: position[:signal_type],
        entry_time: position[:entry_time],
        entry_price: position[:entry_price],
        exit_time: candle.timestamp,
        exit_price: exit_price,
        pnl_percent: pnl_percent.round(2),
        exit_reason: exit_reason,
        bars_held: index - position[:entry_index],
        exit_bar_index: index
      }
    end
  end
end
