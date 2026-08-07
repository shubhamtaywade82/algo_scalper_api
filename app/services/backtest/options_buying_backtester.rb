# frozen_string_literal: true

module Backtest
  # Two-phase backtester: `collect_entries` does the expensive part (fetch index/option data
  # from the live DhanHQ API, run the 5-indicator signal scan) exactly once per symbol.
  # `simulate!`/`resimulate` replay exit management (SL/target/giveback/time-stop) against the
  # already-collected entries in pure memory — no network calls — so parameter sweeps don't
  # re-fetch the same data hundreds of times. `execute` runs both phases for the common case.
  class OptionsBuyingBacktester
    TRADING_START = '09:15'
    TRADING_END   = '15:15'
    MAX_TRADES_PER_DAY = 1
    LATEST_ENTRY_HOUR = 14 # No entries after 2:00 PM IST

    # NOT independently validated — see PR/conversation notes. Every hand-picked variant of
    # the giveback/time-stop numbers underperformed the no-giveback baseline on one NIFTY/90d
    # sample; these are just the defaults `execute` uses absent an explicit `params:` override.
    # Use `for_sweep` + `resimulate` to search this space properly instead of hand-tuning.
    DEFAULT_PARAMS = {
      stop_loss_pct: 0.35,           # exit if premium falls to this fraction of entry
      target_pct: 1.80,              # exit if premium rises to this multiple of entry
      giveback_activation_pct: 15.0, # % gain from entry before the HWM ratchet arms
      giveback_pct: 0.10,            # max pullback off HWM allowed once armed
      max_hold_minutes: 60           # time-stop if giveback never arms within this long
    }.freeze

    # ponytail: flat approximation (brokerage + STT + a slippage buffer), not a real cost
    # model — good enough to stop reporting frictionless P&L. Refine per-broker if this
    # backtest starts driving real allocation decisions.
    BROKERAGE_PER_LEG = 20.0 # ₹ flat, entry + exit = 2 legs
    STT_SELL_PCT      = 0.000_625 # 0.0625% STT on sell-side premium turnover (options)
    SLIPPAGE_POINTS   = 1.0 # per leg, against the fill price

    # DhanHQ's intraday endpoint (DH-905) caps a single request at 90 calendar days, and
    # rejects a from_date/to_date that isn't itself a trading day. @days_back is trading days,
    # so beyond ~60 it needs more calendar span than one request allows — fetch in windows.
    MAX_FETCH_SPAN_DAYS = 89
    RAW_CANDLE_FIELDS = %w[open high low close volume timestamp].freeze

    TRADING_TYPES = %i[options futures].freeze

    attr_reader :symbol, :days_back, :trade_log, :daily_log, :instrument, :params, :raw_entries, :trading_type

    def initialize(symbol:, days_back: 90, params: {}, trading_type: :options, entry_interval: '5')
      @symbol = symbol.to_s.upcase
      @trading_type = trading_type.to_sym
      raise "trading_type must be one of #{TRADING_TYPES}" unless TRADING_TYPES.include?(@trading_type)

      @entry_interval = entry_interval.to_s
      @days_back = days_back
      @instrument = Instrument.segment_index.find_by(symbol_name: @symbol)
      raise "Instrument #{@symbol} not found" unless @instrument

      # Single source of truth for lot size — same lookup live order sizing uses
      # (Entries::Guards::SizingGuard/ExposureGuard), not a locally-guessed table.
      @lot_size = Trading::LotCalculator.lot_size_for(@symbol)

      @params = DEFAULT_PARAMS.merge(params)
      @raw_entries = []
      @entries_collected = false
      @trade_log = []
      @daily_log = []
    end

    def self.call(symbol:, days_back: 90, params: {}, trading_type: :options, entry_interval: '5')
      service = new(symbol: symbol, days_back: days_back, params: params, trading_type: trading_type, entry_interval: entry_interval)
      service.execute
      service
    end

    # Process-local memoization so a sweep can grab the same collected entries for a symbol
    # across many parameter combos without re-hitting the live API for each one.
    def self.for_sweep(symbol:, days_back: 90, trading_type: :options, entry_interval: '5')
      @sweep_cache ||= {}
      key = [symbol.to_s.upcase, days_back, trading_type, entry_interval]
      @sweep_cache[key] ||= new(symbol: symbol, days_back: days_back, trading_type: trading_type, entry_interval: entry_interval).tap(&:collect_entries)
    end

    def self.clear_sweep_cache!
      @sweep_cache = {}
    end

    def execute
      $stdout.puts "\n#{'=' * 80}"
      $stdout.puts "FIVE-INDICATOR OPTIONS BUYING BACKTEST: #{@symbol}"
      $stdout.puts "Period: Last #{@days_back} trading days"
      $stdout.puts '=' * 80

      collect_entries
      simulate!

      $stdout.puts "\n#{'=' * 80}"
      $stdout.puts 'BACKTEST COMPLETE'
      $stdout.puts '=' * 80

      self
    end

    # Phase 1 (expensive, network): fetch index candles + run the signal scan + fetch each
    # entry's 1m option premium series. Idempotent — safe to call more than once.
    def collect_entries
      return self if @entries_collected

      min5_data = fetch_data('5')
      min1_data = fetch_data('1')

      unless min5_data && min1_data
        log_error('Missing candle data')
        @entries_collected = true
        return self
      end

      series_5m = build_series(min5_data, '5')
      series_1m = build_series(min1_data, '1')
      @series_1m = series_1m

      days_5m = group_by_date(series_5m)
      entry_series = @entry_interval == '1' ? series_1m : series_5m
      days_entry = group_by_date(entry_series)

      $stdout.puts "#{@entry_interval}m candles: #{entry_series.candles.size}, 5m(CPR): #{series_5m.candles.size}, 1m: #{series_1m.candles.size}"
      $stdout.puts "Trading days found: #{days_entry.size}"

      days_entry.each_with_index do |(date, candles_entry), idx|
        next if idx.zero?

        prev_date = days_entry.keys[idx - 1]
        prev_5m = days_5m[prev_date]
        next unless prev_5m

        collect_day_entries(date, candles_entry, prev_date, prev_5m, series_1m)
      end

      @entries_collected = true
      self
    end

    # Phase 2 (cheap, pure): replay exit management against the collected entries under
    # @params. Resets and rebuilds trade_log/daily_log every call.
    def simulate!
      @trade_log = []
      @daily_log = []

      @raw_entries.group_by { |e| e[:entry_time].to_date }.sort.each do |date, entries|
        day_pnl = 0.0
        entries.each do |entry|
          result = simulate_trade(entry)
          @trade_log << result
          day_pnl += result[:pnl]
        end
        @daily_log << { date: date, trade_count: entries.size, pnl: day_pnl }
      end

      self
    end

    # Re-run exit simulation with different exit parameters against already-collected entries.
    def resimulate(new_params)
      @params = DEFAULT_PARAMS.merge(new_params)
      simulate!
    end

    def summary
      wins   = @trade_log.select { |t| t[:pnl].positive? }
      losses = @trade_log.select { |t| t[:pnl] <= 0 }
      total  = @trade_log.size

      total_pnl     = @trade_log.sum { |t| t[:pnl] }
      win_rate      = total.positive? ? (wins.size.to_f / total * 100).round(2) : 0.0
      avg_win       = wins.any?   ? (wins.sum { |t| t[:pnl] } / wins.size.to_f).round(2) : 0.0
      avg_loss      = losses.any? ? (losses.sum { |t| t[:pnl] } / losses.size.to_f).round(2) : 0.0
      max_drawdown  = compute_max_drawdown
      expectancy    = total.positive? ? (total_pnl / total.to_f).round(2) : 0.0

      signals_by_hour = @trade_log.group_by { |t| t[:entry_time].in_time_zone('Asia/Kolkata').strftime('%H:00') }
                                  .transform_values(&:size)
                                  .sort.to_h

      {
        symbol: @symbol,
        days_back: @days_back,
        params: @params,
        total_trades: total,
        winning_trades: wins.size,
        losing_trades: losses.size,
        win_rate: win_rate,
        total_pnl: total_pnl.round(2),
        avg_win: avg_win,
        avg_loss: avg_loss,
        max_drawdown: max_drawdown.round(2),
        expectancy: expectancy,
        profit_factor: compute_profit_factor(wins, losses),
        avg_minutes_held: compute_avg_minutes_held,
        avg_giveback_from_hwm_pct: compute_avg_giveback,
        exit_reasons: count_exit_reasons,
        win_loss_ratio: avg_loss.zero? ? 0.0 : (avg_win.abs / avg_loss.abs).round(2),
        signals_by_hour: signals_by_hour,
        daily_pnl: @daily_log.map { |d| { date: d[:date], trades: d[:trade_count], pnl: d[:pnl].round(2) } },
        trades: @trade_log
      }
    end

    def print_summary
      s = summary
      return $stdout.puts 'No trades executed' if s[:total_trades].zero?

      puts_summary_header
      puts_summary_basic(s)
      puts_summary_advanced(s)
      puts_summary_hourly(s)
      puts_summary_exit_reasons(s)
      puts_summary_daily_pnl(s)
    end

    private

    # ── Data Fetching ──────────────────────────────────────────────────────

    def fetch_data(interval)
      to_date = snap_to_trading_day(Time.zone.today - 1, direction: :backward)
      from_date = snap_to_trading_day(to_date - @days_back.days, direction: :backward)

      $stdout.puts "Fetching #{interval} data: #{from_date} to #{to_date}..."
      fetch_in_windows(interval, from_date, to_date)
    rescue StandardError => e
      $stdout.puts "  ⚠️  #{interval} fetch error: #{e.class} #{e.message}"
      nil
    end

    def fetch_in_windows(interval, from_date, to_date)
      raw_chunks = []
      window_start = from_date

      while window_start <= to_date
        window_end = snap_to_trading_day([window_start + MAX_FETCH_SPAN_DAYS.days, to_date].min, direction: :backward)
        window_end = window_start if window_end < window_start

        raw = @instrument.intraday_ohlc(interval: interval, from_date: window_start.to_s, to_date: window_end.to_s, days: @days_back)
        raw_chunks << raw if raw.present?

        next_start = window_end + 1.day
        break if next_start > to_date

        window_start = snap_to_trading_day(next_start, direction: :forward)
      end

      merge_raw_chunks(raw_chunks)
    end

    # DhanHQ::Models::HistoricalData.intraday returns an Array of per-candle hashes (verified
    # against the live response — not the parallel-array Hash shape CandleSeries also accepts).
    # Handle both, since that's what CandleSeries#normalise_candles itself supports.
    def merge_raw_chunks(chunks)
      return nil if chunks.empty?
      return chunks.flatten(1) if chunks.first.is_a?(Array)

      chunks.reduce do |merged, chunk|
        RAW_CANDLE_FIELDS.each { |key| merged[key] = Array(merged[key]) + Array(chunk[key]) }
        merged
      end
    end

    def snap_to_trading_day(date, direction:)
      step = direction == :backward ? -1 : 1
      20.times do
        return date if trading_day?(date)

        date += step.days
      end
      date
    end

    def trading_day?(date)
      return Market::Calendar.trading_day?(date) if defined?(Market::Calendar) && Market::Calendar.respond_to?(:trading_day?)

      !(date.saturday? || date.sunday?)
    end

    def build_series(raw_data, interval)
      series = CandleSeries.new(symbol: @symbol, interval: interval)
      series.load_from_raw(raw_data) if raw_data.present?
      series
    end

    # ── Day Grouping ───────────────────────────────────────────────────────

    def group_by_date(series)
      groups = {}
      series.candles.each do |c|
        date_key = c.timestamp.to_date
        groups[date_key] ||= []
        groups[date_key] << c
      end
      groups.sort_by { |date, _| date }.to_h
    end

    # ── Per-Day Entry Collection ──────────────────────────────────────────

    def collect_day_entries(date, candles_5m, prev_date, prev_candles_5m, series_1m)
      return if candles_5m.size < 10

      prev_daily = daily_ohlc_from(prev_candles_5m)
      cpr = Indicators::Cpr.call(high: prev_daily[:high], low: prev_daily[:low], close: prev_daily[:close])
      vp = volume_profile_for_date(prev_date, series_1m)

      $stdout.puts "#{date} | CPR: #{cpr[:width_type]} (#{cpr[:width]}pts, #{cpr[:width_pct]}%) | VP-POC: #{vp[:poc] || 'N/A'}"

      day_close_time = candles_5m.last.timestamp
      entries_today = 0

      candles_5m.each_with_index do |candle, idx|
        break if entries_today >= MAX_TRADES_PER_DAY
        next unless trading_hours?(candle.timestamp)

        prefix = candles_5m[0..idx]
        signal = evaluate_signal(prefix, cpr, vp, candle)
        next unless signal

        entry = build_entry(signal, candle, day_close_time, series_1m)
        next unless entry

        @raw_entries << entry
        entries_today += 1
      end

      $stdout.puts "  Entries: #{entries_today}"
    end

    def build_entry(signal, candle, day_close_time, series_1m = nil)
      if @trading_type == :futures
        build_futures_entry(signal, candle, day_close_time, series_1m)
      else
        build_options_entry(signal, candle, day_close_time)
      end
    end

    def build_futures_entry(signal, candle, day_close_time, series_1m)
      day_1m = series_1m.candles.select { |c| c.timestamp.to_date == candle.timestamp.to_date }
      entry_bar = nearest_index_bar(day_1m, candle.timestamp)
      return nil if entry_bar.nil?

      exit_bars = day_1m
                  .select { |b| b.timestamp > entry_bar.timestamp && b.timestamp <= day_close_time }
                  .map { |b| { timestamp: b.timestamp, close: b.close } }

      {
        signal_type: signal[:type],
        entry_time: candle.timestamp,
        entry_price: entry_bar.close,
        entry_index_price: candle.close,
        exit_bars: exit_bars,
        day_close_time: day_close_time,
        reason: signal[:reason]
      }
    end

    def build_options_entry(signal, candle, day_close_time)
      option_data = fetch_option_data(signal[:type], candle.timestamp)
      return nil if option_data.blank?

      entry_bar = nearest_bar(option_data, candle.timestamp)
      return nil if entry_bar.nil? || entry_bar[:close].to_f <= 0

      {
        signal_type: signal[:type],
        entry_time: candle.timestamp,
        entry_price: entry_bar[:close].to_f,
        entry_index_price: candle.close,
        entry_strike: entry_bar[:strike],
        option_data: option_data,
        day_close_time: day_close_time,
        reason: signal[:reason]
      }
    end

    # ── Signal Evaluation ──────────────────────────────────────────────────

    def evaluate_signal(candles, cpr, vp, current_candle)
      return nil if candles.size < 30
      return nil unless cpr[:width_type] == :narrow

      t = current_candle.timestamp.in_time_zone('Asia/Kolkata')
      return nil if t.hour >= LATEST_ENTRY_HOUR # No entries late in the day

      candle_hashes = candles.map { |c| { high: c.high, low: c.low, close: c.close, volume: c.volume } }

      chop = Indicators::ChoppinessIndex.call(candle_hashes)
      return nil if chop.nil?
      return nil unless chop[:regime] == :trending

      vi = Indicators::Vortex.call(candle_hashes)
      return nil if vi.nil?

      crossover = Indicators::Vortex.crossover?(candle_hashes[0...-1], candle_hashes, curr: vi)

      # MFI/VolumeProfile are computed from index (spot) candles, and DhanHQ always reports
      # volume=0 for indices (see Signal::TrendScorer, Signal::MomentumValidator — same fact
      # documented there). That pins MFI at 100/:overbought permanently and VolumeProfile
      # permanently empty, so neither carries real signal on this data. Kept for the trade-log
      # tag only; gating stays on CPR + CHOP + Vortex, which are price-only.
      mfi = Indicators::MoneyFlowIndex.call(candle_hashes)

      price = current_candle.close

      tag = "CPR:#{cpr[:width_type]} C:#{chop[:regime]}(#{chop[:value]}) VI:#{vi[:state]}(#{vi[:vi_plus]}/#{vi[:vi_minus]}) MFI:#{mfi&.dig(:state)}(#{mfi&.dig(:value)})"

      long_type  = @trading_type == :futures ? :long : :ce
      short_type = @trading_type == :futures ? :short : :pe
      long_label  = long_type.to_s.upcase
      short_label = short_type.to_s.upcase

      # Tier 1: fresh crossover (strongest signal)
      if crossover == :bullish_crossover
        return nil if near_hvn?(price, vp[:hvns], :bullish)
        return { type: long_type, price: price, reason: "#{long_label} X ↑ #{tag}" }
      end

      if crossover == :bearish_crossover
        return nil if near_hvn?(price, vp[:hvns], :bearish)
        return { type: short_type, price: price, reason: "#{short_label} X ↓ #{tag}" }
      end

      # Tier 2: sustained VI direction while trending (no crossover needed)
      if vi[:state] == :bullish
        return nil if near_hvn?(price, vp[:hvns], :bullish)
        return { type: long_type, price: price, reason: "#{long_label} VI #{tag}" }
      end

      if vi[:state] == :bearish
        return nil if near_hvn?(price, vp[:hvns], :bearish)
        return { type: short_type, price: price, reason: "#{short_label} VI #{tag}" }
      end

      nil
    end

    # ── HVN Proximity Check ────────────────────────────────────────────────

    def near_hvn?(price, hvns, direction)
      return false if hvns.blank?

      if direction == :bullish
        nearest = hvns.select { |h| h > price }.min
        nearest && (nearest - price).abs < 15
      else
        nearest = hvns.select { |h| h < price }.max
        nearest && (price - nearest).abs < 15
      end
    end

    # ── Exit Simulation (pure — no network) ───────────────────────────────

    def simulate_trade(entry)
      position = {
        entry_price: entry[:entry_price],
        entry_time: entry[:entry_time],
        stop_loss: entry[:entry_price] * @params[:stop_loss_pct],
        target: entry[:entry_price] * @params[:target_pct],
        hwm: entry[:entry_price],
        hwm_time: entry[:entry_time],
        giveback_active: false
      }

      bars = exit_bars_for(entry)
             .select { |b| b[:timestamp] > entry[:entry_time] && b[:timestamp] <= entry[:day_close_time] }
             .sort_by { |b| b[:timestamp] }
      bars.each do |bar|
        premium = bar[:close]
        if premium > position[:hwm]
          position[:hwm] = premium
          position[:hwm_time] = bar[:timestamp]
        end

        reason = exit_reason_for(position, premium, bar[:timestamp])
        next unless reason

        return build_exit(entry, position, premium, bar[:timestamp], reason)
      end

      force_exit(entry, position)
    end

    # Ordered stop_loss-before-target: if both are technically touched within the same bar
    # we can't tell which happened first, so assume the worse outcome (conservative backtest).
    def exit_reason_for(position, premium, now)
      return 'stop_loss' if premium <= position[:stop_loss]
      return 'target' if premium >= position[:target]

      gain_pct = pnl_pct_for(position[:entry_price], premium)
      position[:giveback_active] ||= gain_pct >= @params[:giveback_activation_pct]

      if position[:giveback_active]
        giveback_floor = position[:hwm] * (1 - @params[:giveback_pct])
        return 'giveback_stop' if premium <= giveback_floor
      elsif now - position[:entry_time] >= @params[:max_hold_minutes].minutes
        return 'time_stop'
      end

      nil
    end

    def force_exit(entry, position)
      last_bar = exit_bars_for(entry).select { |b| b[:timestamp] <= entry[:day_close_time] }.max_by { |b| b[:timestamp] }
      final_premium = last_bar ? last_bar[:close] : position[:entry_price] * 0.5
      position[:hwm] = final_premium if final_premium > position[:hwm]
      build_exit(entry, position, final_premium, entry[:day_close_time], 'end_of_day')
    end

    def build_exit(entry, position, exit_premium, exit_time, reason)
      pnl_cash = ((exit_premium - entry[:entry_price]) * @lot_size) - trade_costs(exit_premium, @lot_size)
      giveback_from_hwm_pct = position[:hwm].positive? ? (((position[:hwm] - exit_premium) / position[:hwm]) * 100.0).round(2) : 0.0

      {
        signal_type: entry[:signal_type],
        entry_time: entry[:entry_time],
        entry_price: entry[:entry_price].round(2),
        exit_time: exit_time,
        exit_price: exit_premium.round(2),
        pnl: pnl_cash.round(2),
        pnl_pct: pnl_pct_for(entry[:entry_price], exit_premium).round(2),
        exit_reason: reason,
        minutes_held: ((exit_time - entry[:entry_time]) / 60.0).round(1),
        entry_index_price: entry[:entry_index_price],
        hwm_price: position[:hwm].round(2),
        hwm_time: position[:hwm_time],
        giveback_from_hwm_pct: giveback_from_hwm_pct,
        reason: entry[:reason]
      }
    end

    def trade_costs(exit_premium, lot_size)
      brokerage = BROKERAGE_PER_LEG * 2
      stt = exit_premium * lot_size * STT_SELL_PCT
      slippage = SLIPPAGE_POINTS * lot_size * 2
      brokerage + stt + slippage
    end

    def pnl_pct_for(entry_price, premium)
      entry_price.positive? ? ((premium - entry_price) / entry_price * 100.0) : 0.0
    end

    # ── Option Data ────────────────────────────────────────────────────────

    def fetch_option_data(signal_type, timestamp)
      Options::ExpiredFetcher.call(
        symbol: @symbol,
        expiry_flag: 'WEEK',
        date: timestamp.to_date
      )[signal_type]
    rescue StandardError => e
      $stdout.puts "  ⚠️  Option data error for #{timestamp.to_date}: #{e.message}"
      nil
    end

    def nearest_bar(option_data, timestamp)
      return nil if option_data.blank?

      option_data.min_by { |b| (b[:timestamp] - timestamp).abs }
    end

    # DhanHQ's expired-options "ATM" series re-resolves the strike per bar as spot drifts —
    # it's a rolling composite, not one contract's continuous price (confirmed: the same day's
    # series can flip between adjacent strikes multiple times an hour). A real position holds
    # ONE strike from entry to exit, so exit simulation must only look at bars that still quote
    # entry_strike — this thins 1m coverage to ~25-30% (bars where a different strike momentarily
    # resolved are skipped, not followed), but tracks the actual contract instead of a splice.
    def same_strike_bars(entry)
      entry[:option_data].select { |b| b[:strike].to_i == entry[:entry_strike].to_i }
    end

    def exit_bars_for(entry)
      return entry[:exit_bars] if entry[:exit_bars]

      same_strike_bars(entry)
    end

    def nearest_index_bar(bars, timestamp)
      bars.min_by { |b| (b.timestamp - timestamp).abs }
    end

    # ── Helpers ────────────────────────────────────────────────────────────

    def daily_ohlc_from(candles)
      {
        high: candles.map(&:high).max,
        low: candles.map(&:low).min,
        open: candles.first.open,
        close: candles.last.close
      }
    end

    def volume_profile_for_date(date, series_1m)
      day_candles = series_1m.candles.select { |c| c.timestamp.to_date == date }
      return {} if day_candles.size < 10

      candles_h = day_candles.map { |c| { high: c.high, low: c.low, volume: c.volume } }
      Indicators::VolumeProfile.call(candles_h, bin_size: 5.0)
    end

    def trading_hours?(timestamp)
      t = timestamp.in_time_zone('Asia/Kolkata').strftime('%H:%M')
      t.between?(TRADING_START, TRADING_END)
    end

    # ── Metrics ────────────────────────────────────────────────────────────

    def compute_max_drawdown
      peak = 0.0
      max_dd = 0.0
      cumulative = 0.0

      @trade_log.each do |t|
        cumulative += t[:pnl]
        peak = [peak, cumulative].max
        dd = peak - cumulative
        max_dd = [max_dd, dd].max
      end

      max_dd
    end

    def compute_profit_factor(wins, losses)
      gross_profit = wins.sum { |t| t[:pnl] }
      gross_loss = losses.sum { |t| t[:pnl] }.abs

      return (gross_profit / gross_loss).round(2) if gross_loss.positive?

      gross_profit.positive? ? 99.99 : 0.0
    end

    def compute_avg_minutes_held
      return 0.0 if @trade_log.empty?

      (@trade_log.sum { |t| t[:minutes_held] } / @trade_log.size.to_f).round(1)
    end

    def compute_avg_giveback
      return 0.0 if @trade_log.empty?

      (@trade_log.sum { |t| t[:giveback_from_hwm_pct] } / @trade_log.size.to_f).round(2)
    end

    def count_exit_reasons
      @trade_log.each_with_object(Hash.new(0)) { |t, h| h[t[:exit_reason]] += 1 }.sort.to_h
    end

    # ── Output ─────────────────────────────────────────────────────────────

    def log_error(msg)
      $stdout.puts "❌ #{msg}"
      nil
    end

    def puts_summary_header
      $stdout.puts "\n#{'=' * 80}"
      $stdout.puts "BACKTEST REPORT: #{@symbol}"
      $stdout.puts "Period: Last #{@days_back} trading days"
      $stdout.puts '=' * 80
    end

    def puts_summary_basic(s)
      $stdout.puts "\n📊 TRADE STATISTICS"
      $stdout.puts '-' * 80
      $stdout.puts "Total Trades:      #{s[:total_trades]}"
      $stdout.puts "Winning Trades:    #{s[:winning_trades]} (#{s[:win_rate]}%)"
      $stdout.puts "Losing Trades:     #{s[:losing_trades]}"
      $stdout.puts "Win Rate:          #{s[:win_rate]}%"
      $stdout.puts "Total P&L:         ₹#{s[:total_pnl]}"
      $stdout.puts "Avg Win:           ₹#{s[:avg_win]}"
      $stdout.puts "Avg Loss:          ₹#{s[:avg_loss]}"
    end

    def puts_summary_advanced(s)
      $stdout.puts '-' * 80
      $stdout.puts "\n📈 ADVANCED METRICS"
      $stdout.puts '-' * 80
      $stdout.puts "Max Drawdown:      ₹#{s[:max_drawdown]}"
      $stdout.puts "Expectancy:        ₹#{s[:expectancy]} per trade"
      $stdout.puts "Profit Factor:     #{s[:profit_factor]}"
      $stdout.puts "Win/Loss Ratio:    #{s[:win_loss_ratio]}"
      $stdout.puts "Avg Minutes Held:  #{s[:avg_minutes_held]}"
      $stdout.puts "Avg Give-back from HWM: #{s[:avg_giveback_from_hwm_pct]}%"
    end

    def puts_summary_hourly(s)
      $stdout.puts '-' * 80
      $stdout.puts "\n⏰ SIGNALS BY HOUR"
      $stdout.puts '-' * 80
      s[:signals_by_hour].each { |hour, count| $stdout.puts "  #{hour}  →  #{count} trades" }
    end

    def puts_summary_exit_reasons(s)
      $stdout.puts '-' * 80
      $stdout.puts "\n🚪 EXIT REASONS"
      $stdout.puts '-' * 80
      s[:exit_reasons].each { |reason, count| $stdout.puts "  #{reason}: #{count}" }
    end

    def puts_summary_daily_pnl(s)
      $stdout.puts '-' * 80
      $stdout.puts "\n📅 DAILY P&L"
      $stdout.puts '-' * 80
      s[:daily_pnl].each do |d|
        next if d[:trades].zero?

        sign = d[:pnl].negative? ? '' : '+'
        $stdout.puts "  #{d[:date]} | #{d[:trades]} trade(s) | #{sign}₹#{d[:pnl]}"
      end
    end
  end
end
