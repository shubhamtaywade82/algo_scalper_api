# frozen_string_literal: true

module Research
  class ReplayEngine
    # Replays a day minute-by-minute to generate trade execution metrics without lookahead leakage.
    # @param day_data [Hash] Daily data containing underlying_candles, prev_day_* info
    # @param symbol [String] NIFTY
    # @param target_points [Numeric] Target points for ORB continuation
    # @return [Array<Hash>] List of executed trades on this day
    def self.run(day_data, symbol: "NIFTY", target_points: 50.0)
      candles = day_data[:underlying_candles]
      return [] if candles.size < 15

      date = day_data[:date]
      executed_trades = []

      # Range variables
      or_high = nil
      or_low = nil

      # State machine variables
      in_trade = false
      active_trade = nil

      # Step minute-by-minute
      candles.each_with_index do |c, idx|
        # 1. Opening range formation (first 15 minutes)
        if idx < 15
          next
        elsif idx == 15
          opening_candles = candles.first(15)
          or_high = opening_candles.map { |x| x[:high] }.max
          or_low = opening_candles.map { |x| x[:low] }.min
        end

        # 2. Check for entry signal if not in trade
        if in_trade
          # Update trade state at current index
          trade_completed = true

          active_trade[:strikes_state].each_value do |str|
            next if str[:exited]

            opt_candles = str[:option_candles]
            opt_c = opt_candles[idx]
            next if opt_c.nil?

            # Set entry price at entry index
            if str[:entry_price].nil?
              str[:entry_price] = opt_c[:open]
              str[:peak_price] = opt_c[:open]
            end

            # Update peak
            str[:peak_price] = [str[:peak_price], opt_c[:high]].max

            # Compute current return
            current_return = str[:entry_price].positive? ? ((opt_c[:close] - str[:entry_price]) / str[:entry_price]) * 100.0 : 0.0

            # Exit rule evaluation: check trailing stop or exhaustion
            pes, = Research::OptionExpansionAnalyzer.send(:calculate_pes, idx, opt_candles, candles, active_trade[:breakout_type], str[:entry_price], str[:peak_price])

            # Trigger exit if PES >= 75 or standard stop hit (e.g. -20% or market close)
            if pes >= 75 || current_return <= -20.0 || idx == candles.size - 1
              str[:exited] = true
              str[:exit_time] = opt_c[:timestamp]
              str[:exit_price] = opt_c[:close]
              str[:return_pct] = current_return
            else
              trade_completed = false
            end
          end

          # If all strikes are exited or at close, conclude the trade opportunity
          if trade_completed
            # Compute underlying max continuation/MFE
            post_und = candles[active_trade[:entry_index]..idx]
            und_entry = active_trade[:underlying_entry_price]

            if active_trade[:breakout_type] == :bullish
              und_highest = post_und.map { |x| x[:high] }.max || und_entry
              active_trade[:max_continuation] = und_highest - und_entry
            else
              und_lowest = post_und.map { |x| x[:low] }.min || und_entry
              active_trade[:max_continuation] = und_entry - und_lowest
            end

            # Clean and package strikes payload
            opp_strikes = {}
            active_trade[:strikes_state].each do |label, str|
              opp_strikes[label] = {
                entry_price: str[:entry_price],
                peak_price: str[:peak_price],
                mfe_pct: str[:entry_price].positive? ? ((str[:peak_price] - str[:entry_price]) / str[:entry_price]) * 100.0 : 0.0,
                exits: {
                  hybrid_divergence: {
                    return_pct: str[:return_pct],
                    capture_efficiency: str[:peak_price] > str[:entry_price] ? (str[:exit_price] - str[:entry_price]) / (str[:peak_price] - str[:entry_price]) : 0.0
                  }
                }
              }
            end

            executed_trades << {
              date: active_trade[:date],
              breakout_type: active_trade[:breakout_type],
              entry_time: active_trade[:entry_time],
              underlying_entry_price: active_trade[:underlying_entry_price],
              or_high: active_trade[:or_high],
              or_low: active_trade[:or_low],
              or_width: active_trade[:or_width],
              max_continuation: active_trade[:max_continuation],
              strikes: opp_strikes
            }

            in_trade = false
            active_trade = nil
          end
        else
          breakout_type = nil
          if c[:close] > or_high
            breakout_type = :bullish
          elsif c[:close] < or_low
            breakout_type = :bearish
          end

          if breakout_type
            # Entry execution happens at the open of the next minute (idx + 1)
            entry_idx = idx + 1
            break if entry_idx >= candles.size

            entry_candle = candles[entry_idx]

            # Resolve strikes at entry spot
            spot_open = entry_candle[:open]
            option_type = breakout_type == :bullish ? "CE" : "PE"
            candidates = Research::StrikeResolver.candidates(symbol: symbol, spot: spot_open, option_type: option_type)

            # Initialize trade state
            in_trade = true
            active_trade = {
              date: date,
              breakout_type: breakout_type,
              entry_time: entry_candle[:timestamp],
              entry_index: entry_idx,
              underlying_entry_price: entry_candle[:open],
              or_high: or_high,
              or_low: or_low,
              or_width: or_high - or_low,
              gap_pct: day_data[:gap_pct] || 0.0,
              is_inside_day: day_data[:is_inside_day] || false,
              days_to_expiry: day_data[:days_to_expiry] || 4,
              day_of_week: date.strftime("%A"),
              strikes_state: candidates.to_h do |cand|
                               [cand[:strike_label], {
                  actual_strike: cand[:actual_strike],
                  option_candles: Research::MarketDataFetcher.load_or_simulate_options(
                    symbol, option_type, cand[:actual_strike], date, candles, strike_label: cand[:strike_label]
                  ),
                  entry_price: nil,
                  peak_price: nil,
                  exited: false,
                  exit_time: nil,
                  exit_price: nil,
                  return_pct: 0.0
                }]
                             end
            }
          end

          # 3. Manage active trade minute-by-minute
        end
      end

      executed_trades
    end
  end
end
