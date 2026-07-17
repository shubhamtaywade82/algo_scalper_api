# frozen_string_literal: true

module Research
  class MarketDataFetcher
    class SyntheticDataError < StandardError; end

    # Fetches or generates historical NIFTY and ATM option data for the last N trading days.
    # @param symbol [String] 'NIFTY'
    # @param lookback_days [Integer] Number of days to analyze
    # @param interval [String] '1' for 1-minute
    # @param strict [Boolean] when true, refuse synthetic/simulated fallbacks
    # @return [Array<Hash>] Daily market data payloads
    def self.run(symbol: "NIFTY", lookback_days: 365, interval: "1", strict: true, db_only: false)
      symbol = symbol.to_s.upcase
      days_data = []

      # 1. Get dates we have NIFTY candles for in db
      db_candles = Candles::Record.where(instrument_key: symbol, timeframe: "#{interval}m").order(:ts)

      dates = db_candles.unscope(:order).pluck("DISTINCT(ts::date)").sort

      # If we don't have enough days in db, try to read from today_market_data.json
      json_days = {}
      if File.exist?("today_market_data.json")
        begin
          raw_json = JSON.parse(File.read("today_market_data.json"))
          key = symbol.downcase
          if raw_json[key] && raw_json[key][interval]
            raw_json[key][interval].group_by { |c| Date.parse(c["t"]) }.each do |date, candles|
              json_days[date] = candles.map do |c|
                {
                  timestamp: Time.zone.parse(c["t"]),
                  open: c["o"].to_f,
                  high: c["h"].to_f,
                  low: c["l"].to_f,
                  close: c["c"].to_f,
                  volume: c["v"].to_i
                }
              end
            end
          end
        rescue StandardError => e
          Rails.logger.warn("[Research::MarketDataFetcher] Failed to parse today_market_data.json: #{e.message}")
        end
      end

      # Combine unique dates — reject any weekend dates that slipped into the
      # candles table (e.g. from a backfill gap-fill or timezone edge case);
      # DhanHQ::Models::ExpiredOptionsData rejects weekend from_date/to_date
      # outright, so a single bad date here fails every fetch for that day.
      all_dates = (dates + json_days.keys).uniq.reject { |d| d.saturday? || d.sunday? }.sort.last(lookback_days)

      if all_dates.empty?
        if strict
          raise SyntheticDataError,
                "No historical #{symbol} data found; refusing to generate a synthetic dataset (strict mode)."
        end

        Rails.logger.warn("[Research::MarketDataFetcher] No historical #{symbol} data found, generating synthetic dataset.")
        all_dates = (0...lookback_days).map { |i| Time.zone.today - i.days }.reject { |d| d.saturday? || d.sunday? }.reverse
      end

      all_dates.each_with_index do |date, idx|
        # Load NIFTY candles for this day
        nifty_candles = load_nifty_candles(symbol, date, db_candles, json_days)
        next if nifty_candles.empty?

        # Determine ATM Strike based on 09:15 Open
        first_candle = nifty_candles.first
        spot_open = first_candle[:open]
        atm_strike = Research::StrikeResolver.atm(symbol: symbol, spot: spot_open)

        # Load or generate CE & PE Option Candles
        ce_candles = load_or_simulate_options(symbol, "CE", atm_strike, date, nifty_candles, strict: strict, db_only: db_only)
        pe_candles = load_or_simulate_options(symbol, "PE", atm_strike, date, nifty_candles, strict: strict, db_only: db_only)

        next if ce_candles.empty? || pe_candles.empty?

        prev_day_close = nil
        prev_day_high = nil
        prev_day_low = nil

        if idx.positive?
          prev_day_candles = load_nifty_candles(symbol, all_dates[idx - 1], db_candles, json_days)
          if prev_day_candles.any?
            prev_day_close = prev_day_candles.last[:close]
            prev_day_high = prev_day_candles.map { |c| c[:high] }.max
            prev_day_low = prev_day_candles.map { |c| c[:low] }.min
          end
        end

        days_data << {
          date: date,
          atm_strike: atm_strike,
          underlying_candles: nifty_candles,
          ce_candles: ce_candles,
          pe_candles: pe_candles,
          prev_day_close: prev_day_close,
          prev_day_high: prev_day_high,
          prev_day_low: prev_day_low
        }
      end

      days_data
    end

    def self.load_nifty_candles(symbol, date, db_candles, json_days)
      raw = json_days[date] || db_candles.where(ts: date.beginning_of_day...date.end_of_day).map do |c|
        {
          timestamp: c.ts,
          open: c.open.to_f,
          high: c.high.to_f,
          low: c.low.to_f,
          close: c.close.to_f,
          volume: c.volume.to_i
        }
      end

      # Filter to standard NSE market hours: 09:15 to 15:30 IST (555 to 930 minutes from midnight)
      raw.select do |c|
        ist = c[:timestamp].in_time_zone("Asia/Kolkata")
        min = (ist.hour * 60) + ist.min
        min.between?(555, 930)
      end
    end

    def self.load_or_simulate_options(symbol, option_type, strike, date, nifty_candles, strike_label: "ATM", strict: true, db_only: false)
      # Try fetching from DB first
      expiry_flag = "WEEK"
      interval = "1"

      bars = Research::OptionBar.where(
        underlying_symbol: symbol,
        expiry_flag: expiry_flag,
        option_type: option_type,
        strike_label: strike_label,
        interval: interval
      ).where(ts: date.beginning_of_day...date.end_of_day).order(:ts).to_a

      if bars.any?
        daily_bars = bars.select do |b|
          ist = b.ts.in_time_zone("Asia/Kolkata")
          min = (ist.hour * 60) + ist.min
          min.between?(555, 930)
        end
        return daily_bars.map do |b|
          {
            timestamp: b.ts,
            open: b.open.to_f,
            high: b.high.to_f,
            low: b.low.to_f,
            close: b.close.to_f,
            volume: b.volume.to_i
          }
        end
      end

      return [] if db_only

      # Attempt to fetch using OptionCandleFetcher if token is valid
      begin
        dhan_strike_param = strike_label
        fetched_bars = Research::OptionCandleFetcher.call(
          symbol: symbol,
          option_type: option_type,
          expiry_flag: expiry_flag,
          strike_label: strike_label,
          dhan_strike_param: dhan_strike_param,
          from_date: date.strftime("%Y-%m-%d"),
          to_date: (date + 1.day).strftime("%Y-%m-%d"),
          interval: interval
        )
        if fetched_bars.present? && fetched_bars.any?
          daily_bars = fetched_bars.select { |b| b.ts >= date.beginning_of_day && b.ts < date.end_of_day }
          daily_bars = daily_bars.select do |b|
            ist = b.ts.in_time_zone("Asia/Kolkata")
            min = (ist.hour * 60) + ist.min
            min.between?(555, 930)
          end
          return daily_bars.map do |b|
            {
              timestamp: b.ts,
              open: b.open.to_f,
              high: b.high.to_f,
              low: b.low.to_f,
              close: b.close.to_f,
              volume: b.volume.to_i
            }
          end
        end
      rescue StandardError => e
        # Ignore errors and fall through to simulation
        Rails.logger.debug("[Research::MarketDataFetcher] OptionCandleFetcher skipped: #{e.message}")
      end

      # Fallback: simulate option premium — forbidden in strict mode.
      if strict
        Rails.logger.warn("[Research::MarketDataFetcher] No real option bars for #{symbol} #{strike_label} #{option_type} on #{date}; day skipped (strict mode).")
        return []
      end

      simulate_option_premium(option_type, strike, nifty_candles)
    end

    # Simulates option premium based on Delta-Gamma-Theta approximation.
    def self.simulate_option_premium(option_type, strike, nifty_candles)
      # Black-Scholes/Delta-Gamma-Theta simulation parameters
      gamma = 0.001
      theta = -0.08 # decay per minute

      # Adjust starting premium and delta based on strike vs spot
      spot_start = nifty_candles.first[:open]
      moneyness_start = option_type == "CE" ? (spot_start - strike) : (strike - spot_start)

      start_premium = 120.0 + (0.6 * moneyness_start)
      start_premium = [start_premium, 5.0].max # Min starting premium is 5.0

      delta = option_type == "CE" ? 0.5 : -0.5
      delta += (option_type == "CE" ? 1.0 : -1.0) * moneyness_start * gamma
      delta = delta.clamp(0.05, 0.95) if option_type == "CE"
      delta = delta.clamp(-0.95, -0.05) if option_type == "PE"

      option_candles = []
      prev_spot = spot_start
      current_premium = start_premium

      nifty_candles.each do |c|
        spot = c[:close]
        dS = spot - prev_spot

        # Calculate premium change based on Taylor expansion of option price
        dOption = (delta * dS) + (0.5 * gamma * (dS**2)) + theta
        current_premium = [current_premium + dOption, 2.0].max # Min premium is 2.0

        # Create candle prices around close
        op = [current_premium - (delta * (spot - c[:open])), 1.0].max
        hi = [[op, current_premium].max + 1.5, 2.0].max
        lo = [[op, current_premium].min - 1.5, 1.0].max

        option_candles << {
          timestamp: c[:timestamp],
          open: op.round(2),
          high: hi.round(2),
          low: lo.round(2),
          close: current_premium.round(2),
          volume: (c[:volume] * 0.01).to_i
        }

        # Update delta as spot moves away from strike
        moneyness = option_type == "CE" ? (spot - strike) : (strike - spot)
        delta = if option_type == "CE"
                  0.5 + (moneyness * gamma)
                else
                  -0.5 - (moneyness * gamma)
                end
        delta = delta.clamp(0.05, 0.95) if option_type == "CE"
        delta = delta.clamp(-0.95, -0.05) if option_type == "PE"

        prev_spot = spot
      end

      option_candles
    end
  end
end
