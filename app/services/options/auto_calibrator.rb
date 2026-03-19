# frozen_string_literal: true

module Options
  # Automated calibration orchestrator.
  #
  # Never raises. All DhanHQ fetches are individually rescued.
  # Returns a persisted CalibrationRun on success, nil if all fetches fail.
  #
  # Usage:
  #   run = Options::AutoCalibrator.call(symbol: 'NIFTY', weeks: 52)
  #   run&.propose_config!
  class AutoCalibrator
    SESSIONS = {
      'Morning' => ((9 * 60) + 15)..(11 * 60),
      'Midday' => ((11 * 60) + 1)..(13 * 60),
      'Afternoon' => ((13 * 60) + 1)..((15 * 60) + 30)
    }.freeze

    def self.call(symbol:, weeks: 52)
      new(symbol: symbol, weeks: weeks).call
    end

    def initialize(symbol:, weeks:)
      @symbol = symbol.to_s.upcase
      @weeks  = weeks
    end

    def call
      index_cfg = IndexConfigLoader.load_indices.find { |idx| idx[:key].to_s.upcase == @symbol }
      unless index_cfg
        Rails.logger.warn("[AutoCalibrator] #{@symbol}: not found in IndexConfigLoader")
        return nil
      end

      unless Options::ExpiryCalendar::EXPIRY_WEEKDAY.key?(@symbol)
        Rails.logger.warn("[AutoCalibrator] #{@symbol}: weekly expiry not supported — skipping calibration")
        return nil
      end

      @security_id = index_cfg[:sid].to_s
      # IndexConfigLoader returns IDX_I (spot segment); we need the FNO segment for ExpiredOptionsData.
      @segment     = @symbol == 'SENSEX' ? 'BSE_FNO' : 'NSE_FNO'

      windows = Options::ExpiryCalendar.windows(symbol: @symbol, weeks: @weeks)

      atm_result  = run_engine_for_strike('ATM', windows)
      otm1_result = run_engine_for_strike('ATM+1', windows)
      otm2_result = run_engine_for_strike('ATM-1', windows)

      if atm_result.nil?
        Rails.logger.error("[AutoCalibrator] #{@symbol}: all ATM fetches failed — aborting")
        return nil
      end

      combined_stats = Options::StrikeAggregator.combine(
        atm_stats: { ce: atm_result[:ce], pe: atm_result[:pe] },
        otm1_stats: otm1_result ? { ce: otm1_result[:ce], pe: otm1_result[:pe] } : nil,
        otm2_stats: otm2_result ? { ce: otm2_result[:ce], pe: otm2_result[:pe] } : nil
      )

      regime = Options::RegimeDetector.check(symbol: @symbol, combined_stats: combined_stats)
      patch  = Options::CalibrationConfigPatchBuilder.build(
        combined_stats: combined_stats, symbol: @symbol
      )

      strike_mode = otm1_result || otm2_result ? 'atm_plus_minus' : 'atm_only'

      CalibrationRun.create!(
        symbol: @symbol,
        weeks_analyzed: @weeks,
        strike_mode: strike_mode,
        raw_stats: combined_stats,
        proposed_patch: patch,
        is_regime_shift: regime[:shift],
        regime_reason: regime[:reason]
      )
    rescue StandardError => e
      Rails.logger.error("[AutoCalibrator] #{@symbol} unexpected error: #{e.class} — #{e.message}")
      Rails.logger.debug { e.backtrace.first(5).join("\n") }
      nil
    end

    private

    # Fetches OHLCV data for all windows for a given strike, builds
    # HistoricalCalibrationEngine-compatible rows, and runs the engine.
    # Returns engine result hash, or nil if no data could be fetched.
    def run_engine_for_strike(strike_code, windows)
      rows = build_rows_for_strike(strike_code, windows)
      return nil if rows.empty?

      Options::HistoricalCalibrationEngine.new(
        rows: rows, symbol: @symbol
      ).call
    rescue StandardError => e
      Rails.logger.warn("[AutoCalibrator] #{@symbol} #{strike_code} engine error: #{e.class} — #{e.message}")
      nil
    end

    def build_rows_for_strike(strike_code, windows)
      windows.filter_map do |window|
        ce_candles = fetch_candles(strike_code, window, 'CALL')
        pe_candles = fetch_candles(strike_code, window, 'PUT')
        next nil if ce_candles.empty? && pe_candles.empty?

        build_row(ce_candles, pe_candles)
      end
    end

    def fetch_candles(strike_code, window, opt_type)
      side = opt_type == 'CALL' ? 'ce' : 'pe'
      raw = DhanHQ::Models::ExpiredOptionsData.fetch(
        exchange_segment: @segment,
        interval: '5',
        security_id: @security_id,
        instrument: 'OPTIDX',
        expiry_flag: 'WEEK',
        expiry_code: 1,
        strike: strike_code,
        drv_option_type: opt_type,
        required_data: %w[open high low close volume oi spot strike],
        from_date: window[:from].strftime('%Y-%m-%d'),
        to_date: window[:to].strftime('%Y-%m-%d')
      )
      d = raw&.data&.dig(side)
      return [] unless d&.dig('timestamp')

      d['timestamp'].map.with_index do |ts, i|
        t = Time.at(ts).in_time_zone('Asia/Kolkata')
        {
          time: t.iso8601, day: t.wday,
          mins: (t.hour * 60) + t.min,
          open: d['open'][i].to_f, high: d['high'][i].to_f,
          low: d['low'][i].to_f, close: d['close'][i].to_f,
          volume: d['volume'][i].to_i, oi: d['oi'][i].to_i,
          spot: d['spot'][i].to_f, strike: d['strike'][i].to_f
        }
      end
    rescue StandardError => e
      Rails.logger.warn("[AutoCalibrator] #{@symbol} fetch_candles #{strike_code} #{opt_type}: #{e.message}")
      []
    end

    def build_row(ce_candles, pe_candles)
      ce_stats = ce_candles.any? ? cycle_stats(ce_candles) : nil
      pe_stats = pe_candles.any? ? cycle_stats(pe_candles) : nil
      return nil unless ce_stats || pe_stats

      ce_sess = ce_candles.any? ? session_breakdown(ce_candles) : {}
      pe_sess = pe_candles.any? ? session_breakdown(pe_candles) : {}
      ce_corr = ce_candles.any? ? correlation_slope(ce_candles).to_f : 0.0
      pe_corr = pe_candles.any? ? correlation_slope(pe_candles).to_f : 0.0

      {
        'symbol' => @symbol,
        'ce_max_gain_pct' => ce_stats&.dig(:max_gain_pct).to_f,
        'ce_max_loss_pct' => ce_stats&.dig(:max_loss_pct).to_f,
        'ce_retrace' => ce_stats&.dig(:post_peak_retrace).to_f,
        'ce_oc_pct' => ce_stats&.dig(:open_to_close_pct).to_f,
        'ce_entry' => ce_stats&.dig(:entry).to_f,
        'ce_corr_slope' => ce_corr,
        'ce_morning_oc' => ce_sess.dig('Morning', :oc_pct).to_f,
        'ce_midday_oc' => ce_sess.dig('Midday', :oc_pct).to_f,
        'ce_afternoon_oc' => ce_sess.dig('Afternoon', :oc_pct).to_f,
        'pe_max_gain_pct' => pe_stats&.dig(:max_gain_pct).to_f,
        'pe_max_loss_pct' => pe_stats&.dig(:max_loss_pct).to_f,
        'pe_retrace' => pe_stats&.dig(:post_peak_retrace).to_f,
        'pe_oc_pct' => pe_stats&.dig(:open_to_close_pct).to_f,
        'pe_entry' => pe_stats&.dig(:entry).to_f,
        'pe_corr_slope' => pe_corr,
        'pe_morning_oc' => pe_sess.dig('Morning', :oc_pct).to_f,
        'pe_midday_oc' => pe_sess.dig('Midday', :oc_pct).to_f,
        'pe_afternoon_oc' => pe_sess.dig('Afternoon', :oc_pct).to_f
      }
    end

    def cycle_stats(candles)
      entry   = candles.first[:open].to_f
      max_h   = candles.map { |c| c[:high] }.max.to_f
      min_l   = candles.map { |c| c[:low] }.min.to_f
      final_c = candles.last[:close].to_f
      peak_idx   = candles.index { |c| c[:high] == max_h } || 0
      pullback_l = candles[peak_idx..].map { |c| c[:low] }.min.to_f

      {
        entry: entry.round(2),
        max_gain_pct: pct(max_h, entry),
        max_loss_pct: pct(min_l, entry),
        open_to_close_pct: pct(final_c, entry),
        post_peak_retrace: pct(pullback_l, max_h).round(2)
      }
    end

    def session_breakdown(candles)
      SESSIONS.transform_values do |range|
        sess = candles.select { |c| range.cover?(c[:mins]) }
        next nil if sess.empty?

        s_open  = sess.first[:open].to_f
        s_close = sess.last[:close].to_f
        { oc_pct: pct(s_close, s_open) }
      end
    end

    def correlation_slope(candles)
      return 0.0 if candles.empty?

      base_spot   = candles.first[:spot].to_f
      base_option = candles.first[:open].to_f
      return 0.0 if base_spot.zero? || base_option.zero?

      pairs = candles.map { |c| [pct(c[:spot].to_f, base_spot), pct(c[:close].to_f, base_option)] }
      n     = pairs.size.to_f
      sx    = pairs.sum { |x, _| x }
      sy    = pairs.sum { |_, y| y }
      sx2   = pairs.sum { |x, _| x**2 }
      sxy   = pairs.sum { |x, y| x * y }
      denom = (n * sx2) - (sx**2)
      return 0.0 if denom.zero?

      (((n * sxy) - (sx * sy)) / denom).round(2)
    end

    def pct(v, base)
      base.zero? ? 0.0 : ((v - base) / base.to_f * 100).round(2)
    end
  end
end
