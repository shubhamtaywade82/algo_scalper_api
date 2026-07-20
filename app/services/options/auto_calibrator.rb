# frozen_string_literal: true

module Options
  class AutoCalibrator
    SESSIONS = {
      'Morning' => ((9 * 60) + 15)..(11 * 60),
      'Midday' => ((11 * 60) + 1)..(13 * 60),
      'Afternoon' => ((13 * 60) + 1)..((15 * 60) + 30)
    }.freeze

    STRIKES = %w[ATM ATM+1 ATM-1].freeze
    REGIME_RECALIBRATION_WEEKS = 8

    def self.call(symbol:, weeks: 52)
      new(symbol: symbol, weeks: weeks).call
    end

    def initialize(symbol:, weeks:)
      @symbol = symbol.to_s.upcase
      @weeks = weeks
    end

    def call
      index_cfg = IndexConfigLoader.load_indices.find { |idx| idx[:key].to_s.upcase == @symbol }
      unless index_cfg
        Rails.logger.warn("[AutoCalibrator] #{@symbol}: not found in IndexConfigLoader")
        return nil
      end

      @security_id = index_cfg[:sid].to_s
      @segment = @symbol == 'SENSEX' ? 'BSE_FNO' : 'NSE_FNO'

      combined_stats, strike_mode, weeks_used = calibrate_for_weeks(@weeks)
      return nil if combined_stats.nil?

      regime = Options::RegimeDetector.check(symbol: @symbol, combined_stats: combined_stats)
      if regime[:shift] && weeks_used > REGIME_RECALIBRATION_WEEKS
        recalibrated, recal_mode, = calibrate_for_weeks(REGIME_RECALIBRATION_WEEKS)
        if recalibrated
          combined_stats = recalibrated
          strike_mode = recal_mode
          weeks_used = REGIME_RECALIBRATION_WEEKS
        end
      end

      patch = Options::CalibrationConfigPatchBuilder.build(
        combined_stats: combined_stats,
        symbol: @symbol
      )

      CalibrationRun.create!(
        symbol: @symbol,
        weeks_analyzed: weeks_used,
        strike_mode: strike_mode,
        raw_stats: combined_stats.deep_stringify_keys,
        proposed_patch: patch,
        is_regime_shift: regime[:shift],
        regime_reason: regime[:reason]
      )
    rescue StandardError => e
      Rails.logger.error("[AutoCalibrator] #{@symbol} unexpected error: #{e.class} - #{e.message}")
      nil
    end

    private

    def calibrate_for_weeks(weeks)
      windows = Options::ExpiryCalendar.windows(symbol: @symbol, weeks: weeks)

      atm_result = run_engine_for_strike('ATM', windows)
      return [nil, nil, weeks] if atm_result.nil?

      otm1_result = run_engine_for_strike('ATM+1', windows)
      otm2_result = run_engine_for_strike('ATM-1', windows)

      combined_stats = Options::StrikeAggregator.combine(
        atm_stats: { ce: atm_result[:ce], pe: atm_result[:pe] },
        otm1_stats: otm1_result ? { ce: otm1_result[:ce], pe: otm1_result[:pe] } : nil,
        otm2_stats: otm2_result ? { ce: otm2_result[:ce], pe: otm2_result[:pe] } : nil
      )

      strike_mode = otm1_result || otm2_result ? 'atm_plus_minus' : 'atm_only'
      [combined_stats, strike_mode, weeks]
    end

    def run_engine_for_strike(strike_code, windows)
      rows = build_rows_for_strike(strike_code, windows)
      return nil if rows.empty?

      Options::HistoricalCalibrationEngine.new(rows: rows, symbol: @symbol).call
    rescue StandardError => e
      Rails.logger.warn("[AutoCalibrator] #{@symbol} #{strike_code} engine error: #{e.class} - #{e.message}")
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
      data = raw&.data&.dig(side)
      return [] unless data&.dig('timestamp')

      data['timestamp'].map.with_index do |timestamp, index|
        time = Time.at(timestamp).in_time_zone('Asia/Kolkata')
        {
          mins: (time.hour * 60) + time.min,
          open: data['open'][index].to_f,
          high: data['high'][index].to_f,
          low: data['low'][index].to_f,
          close: data['close'][index].to_f,
          spot: data['spot'][index].to_f,
          strike: data['strike']&.[](index)&.to_f
        }
      end
    rescue StandardError => e
      Rails.logger.warn(
        "[AutoCalibrator] #{@symbol} fetch_candles #{strike_code} #{opt_type}: #{e.message}"
      )
      []
    end

    def build_row(ce_candles, pe_candles)
      ce_candles = same_strike_candles(ce_candles)
      pe_candles = same_strike_candles(pe_candles)
      ce_stats = ce_candles.any? ? cycle_stats(ce_candles) : nil
      pe_stats = pe_candles.any? ? cycle_stats(pe_candles) : nil
      return nil unless ce_stats || pe_stats

      ce_sess = ce_candles.any? ? session_breakdown(ce_candles) : {}
      pe_sess = pe_candles.any? ? session_breakdown(pe_candles) : {}

      {
        'symbol' => @symbol,
        'ce_max_gain_pct' => ce_stats&.dig(:max_gain_pct).to_f,
        'ce_max_loss_pct' => ce_stats&.dig(:max_loss_pct).to_f,
        'ce_retrace' => ce_stats&.dig(:post_peak_retrace).to_f,
        'ce_oc_pct' => ce_stats&.dig(:open_to_close_pct).to_f,
        'ce_entry' => ce_stats&.dig(:entry).to_f,
        'ce_corr_slope' => ce_candles.any? ? correlation_slope(ce_candles) : 0.0,
        'ce_morning_oc' => ce_sess.dig('Morning', :oc_pct).to_f,
        'ce_midday_oc' => ce_sess.dig('Midday', :oc_pct).to_f,
        'ce_afternoon_oc' => ce_sess.dig('Afternoon', :oc_pct).to_f,
        'pe_max_gain_pct' => pe_stats&.dig(:max_gain_pct).to_f,
        'pe_max_loss_pct' => pe_stats&.dig(:max_loss_pct).to_f,
        'pe_retrace' => pe_stats&.dig(:post_peak_retrace).to_f,
        'pe_oc_pct' => pe_stats&.dig(:open_to_close_pct).to_f,
        'pe_entry' => pe_stats&.dig(:entry).to_f,
        'pe_corr_slope' => pe_candles.any? ? correlation_slope(pe_candles) : 0.0,
        'pe_morning_oc' => pe_sess.dig('Morning', :oc_pct).to_f,
        'pe_midday_oc' => pe_sess.dig('Midday', :oc_pct).to_f,
        'pe_afternoon_oc' => pe_sess.dig('Afternoon', :oc_pct).to_f
      }
    end

    # DhanHQ's expired-options "ATM"/"ATM+N" series re-resolves the strike per bar as spot
    # drifts within the fetch window — a rolling composite, not one contract's continuous
    # price. Pin to the strike quoted at the first bar (window open) so cycle_stats/session
    # breakdowns/correlation all describe the same held contract, not a spliced series.
    def same_strike_candles(candles)
      return candles if candles.blank?

      entry_strike = candles.first[:strike]
      return candles if entry_strike.nil?

      candles.select { |c| c[:strike].to_i == entry_strike.to_i }
    end

    def cycle_stats(candles)
      entry = candles.first[:open].to_f
      max_high = candles.pluck(:high).max.to_f
      min_low = candles.pluck(:low).min.to_f
      final_close = candles.last[:close].to_f
      peak_index = candles.index { |c| c[:high] == max_high } || 0
      pullback_low = candles[peak_index..].pluck(:low).min.to_f

      {
        entry: entry.round(2),
        max_gain_pct: pct(max_high, entry),
        max_loss_pct: pct(min_low, entry),
        open_to_close_pct: pct(final_close, entry),
        post_peak_retrace: pct(pullback_low, max_high).round(2)
      }
    end

    def session_breakdown(candles)
      SESSIONS.transform_values do |range|
        session_candles = candles.select { |c| range.cover?(c[:mins]) }
        next nil if session_candles.empty?

        session_open = session_candles.first[:open].to_f
        session_close = session_candles.last[:close].to_f
        { oc_pct: pct(session_close, session_open) }
      end
    end

    def correlation_slope(candles)
      base_spot = candles.first[:spot].to_f
      base_option = candles.first[:open].to_f
      return 0.0 if base_spot.zero? || base_option.zero?

      pairs = candles.map do |candle|
        [pct(candle[:spot].to_f, base_spot), pct(candle[:close].to_f, base_option)]
      end
      count = pairs.size.to_f
      sum_x = pairs.sum { |x, _| x }
      sum_y = pairs.sum { |_, y| y }
      sum_x2 = pairs.sum { |x, _| x**2 }
      sum_xy = pairs.sum { |x, y| x * y }
      denominator = (count * sum_x2) - (sum_x**2)
      return 0.0 if denominator.zero?

      (((count * sum_xy) - (sum_x * sum_y)) / denominator).round(2)
    end

    def pct(value, base)
      base.zero? ? 0.0 : ((value - base) / base.to_f * 100).round(2)
    end
  end
end
