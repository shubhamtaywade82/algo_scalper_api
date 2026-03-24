# frozen_string_literal: true

module Backtest
  # Historical replay: prefix {CandleSeries} per bar, {Smc::TradingSignalContract}-aligned entries,
  # optional {Smc::SmcPermissionResolver} labels, optional option premium simulation via {OptionTradeSimulator}.
  class SmcReplayRunner < ApplicationService
    attr_reader :instrument, :series_5m, :series_15m, :series_60m, :spot_rows, :option_trades

    def initialize(
      symbol:,
      days_back: 90,
      forward_horizon: 12,
      min_bars: 25,
      include_permission: true,
      permission_mode: 'strict',
      simulate_options: false
    )
      @symbol = symbol.to_s.strip.upcase
      @days_back = days_back
      @forward_horizon = forward_horizon
      @min_bars = min_bars
      @include_permission = include_permission
      @permission_mode = permission_mode
      @simulate_options = simulate_options
      @spot_rows = []
      @option_trades = []
      @last_result = nil
    end

    def call
      return @last_result if @last_result

      @instrument = Instrument.segment_index.find_by(symbol_name: @symbol)
      unless @instrument
        @last_result = error_result('Instrument not found')
        return @last_result
      end

      @series_5m = fetch_series(Smc::BiasEngine::LTF_INTERVAL)
      @series_15m = fetch_series(Smc::BiasEngine::MTF_INTERVAL)
      @series_60m = fetch_series(Smc::BiasEngine::HTF_INTERVAL)

      if @series_5m.blank? || @series_5m.candles.empty?
        @last_result = error_result('No 5m OHLC data')
        return @last_result
      end
      if @series_15m.blank? || @series_15m.candles.empty?
        @last_result = error_result('No 15m OHLC data')
        return @last_result
      end

      @option_sim = OptionTradeSimulator.new(instrument: @instrument) if @simulate_options

      candles = @series_5m.candles
      next_entry_index = @min_bars

      (@min_bars...candles.size).each do |i|
        next if i < next_entry_index

        prefix_5 = prefix_series(@series_5m, i)
        t_i = candles[i].timestamp
        prefix_15 = prefix_15m_upto(@series_15m, t_i)

        contract = Smc::TradingSignalContract.build(
          series_5m: prefix_5,
          series_15m: prefix_15,
          symbol: @symbol,
          ltp: candles[i].close
        )
        entry = contract[:entry]

        permission = @include_permission ? compute_permission(prefix_5, prefix_15, t_i) : nil

        next unless entry

        spot = spot_forward_metrics(candles, i, @forward_horizon, entry.action)
        row = {
          bar_index: i,
          timestamp: t_i,
          action: entry.action,
          reason: entry.reason,
          rr: entry.rr,
          permission: permission
        }
        row.merge!(spot) if spot
        @spot_rows << row

        next unless @option_sim

        opt_type = entry_action_to_option_type(entry.action)
        next unless opt_type

        trade = @option_sim.simulate_trade(series: @series_5m, entry_index: i, signal_type: opt_type)
        @option_trades << trade if trade
        next_entry_index = trade[:exit_bar_index] + 1 if trade
      end

      @last_result = {
        symbol: @symbol,
        days_back: @days_back,
        bars: candles.size,
        spot_rows: @spot_rows,
        spot_summary: summarize_spot,
        option_trades: @option_trades,
        options_summary: summarize_options
      }
      @last_result
    end

    def print_summary(io: $stdout)
      r = @last_result || call
      return io.puts(r[:error]) if r[:error]

      io.puts "SMC replay: #{r[:symbol]} | days_back=#{r[:days_back]} | bars=#{r[:bars]}"
      io.puts "Spot signals: #{r[:spot_summary][:count]} | win_rate=#{r[:spot_summary][:directional_win_rate]}%"
      r[:spot_rows].last(20).each { |row| io.puts row.inspect }
      io.puts "Options trades: #{r[:options_summary][:total_trades]} | win_rate=#{r[:options_summary][:win_rate]}%" if @simulate_options
    end

    private

    def error_result(msg)
      {
        error: msg,
        spot_rows: [],
        option_trades: [],
        spot_summary: { count: 0, directional_win_rate: 0.0, avg_horizon_return_pct: 0.0 },
        options_summary: { total_trades: 0, win_rate: 0.0, expectancy: 0.0, trades: [] }
      }
    end

    def fetch_range
      to_date = Time.zone.today - 1.day
      to_date -= 1.day while to_date.saturday? || to_date.sunday?
      from_date = to_date - @days_back.days
      from_date -= 1.day while from_date.saturday? || from_date.sunday?
      [from_date, to_date]
    end

    def fetch_series(interval)
      from_date, to_date = fetch_range
      raw = @instrument.intraday_ohlc(
        interval: interval,
        from_date: from_date.to_s,
        to_date: to_date.to_s,
        days: @days_back
      )
      return nil if raw.blank?

      series = CandleSeries.new(symbol: @instrument.symbol_name, interval: interval)
      series.load_from_raw(raw)
      series
    rescue StandardError => e
      Rails.logger.error("[SmcReplayRunner] OHLC fetch failed: #{e.class} - #{e.message}")
      nil
    end

    def prefix_series(series, end_index)
      subset = series.candles[0..end_index]
      build_series_copy(series.symbol, series.interval, subset)
    end

    def prefix_15m_upto(series_15m, t_cutoff)
      subset = series_15m.candles.select { |c| c.timestamp <= t_cutoff }
      build_series_copy(series_15m.symbol, series_15m.interval, subset)
    end

    def prefix_60m_upto(series_60m, t_cutoff)
      subset = series_60m&.candles&.select { |c| c.timestamp <= t_cutoff } || []
      build_series_copy(series_60m.symbol, series_60m.interval, subset)
    end

    def build_series_copy(symbol, interval, candles)
      s = CandleSeries.new(symbol: symbol, interval: interval)
      candles.each { |c| s.candles << c }
      s
    end

    def compute_permission(prefix_5, prefix_15, t_i)
      return nil unless @series_60m&.candles&.any?

      p60 = prefix_60m_upto(@series_60m, t_i)
      return nil if p60.candles.size < 2

      htf = Smc::Context.new(p60)
      mtf = Smc::Context.new(prefix_15)
      ltf = Smc::Context.new(prefix_5)

      smc_hash = Smc::PermissionSnapshot.from_contexts(htf: htf, mtf: mtf, ltf: ltf)
      return nil if smc_hash.blank?

      avrz = Smc::AvrzStateResolver.resolve(symbol: @symbol, ltf_series: prefix_5)
      Smc::SmcPermissionResolver.resolve(
        smc_result: smc_hash,
        avrz_result: { state: avrz },
        mode: @permission_mode
      )
    rescue StandardError => e
      Rails.logger.warn("[SmcReplayRunner] permission snapshot failed: #{e.message}")
      nil
    end

    def spot_forward_metrics(candles, i, horizon, action)
      last_j = [i + horizon, candles.size - 1].min
      return nil if i + 1 > last_j

      future = candles[(i + 1)..last_j]
      return nil if future.blank?

      entry = candles[i].close
      highs = future.map(&:high)
      lows = future.map(&:low)
      mfe_up = ((highs.max - entry) / entry * 100.0).round(4)
      mfe_down = ((entry - lows.min) / entry * 100.0).round(4)
      last_ret = ((future.last.close - entry) / entry * 100.0).round(4)

      win = case action.to_s
            when 'BUY_CE' then last_ret.positive?
            when 'BUY_PE' then last_ret.negative?
            end

      {
        forward_horizon_bars: future.size,
        mfe_up_pct: mfe_up,
        mfe_down_pct: mfe_down,
        horizon_return_pct: last_ret,
        directional_win: win
      }
    end

    def entry_action_to_option_type(action)
      case action.to_s
      when 'BUY_CE' then :ce
      when 'BUY_PE' then :pe
      end
    end

    def summarize_spot
      rows = @spot_rows
      return { count: 0, directional_win_rate: 0.0, avg_horizon_return_pct: 0.0 } if rows.empty?

      wins = rows.count { |r| r[:directional_win] == true }
      denom = rows.count { |r| !r[:directional_win].nil? }
      wr = denom.positive? ? (wins.to_f / denom * 100).round(2) : 0.0
      avg_ret = (rows.sum { |r| r[:horizon_return_pct].to_f } / rows.size).round(4)

      { count: rows.size, directional_win_rate: wr, avg_horizon_return_pct: avg_ret }
    end

    def summarize_options
      trades = @option_trades
      return { total_trades: 0, win_rate: 0.0, expectancy: 0.0, trades: [] } if trades.empty?

      wins = trades.select { |t| t[:pnl_percent].positive? }
      tc = trades.size
      {
        total_trades: tc,
        winning_trades: wins.size,
        losing_trades: tc - wins.size,
        win_rate: (wins.size.to_f / tc * 100).round(2),
        total_pnl_percent: trades.sum { |t| t[:pnl_percent] }.round(2),
        expectancy: (trades.sum { |t| t[:pnl_percent] } / tc).round(2),
        trades: trades
      }
    end
  end
end
