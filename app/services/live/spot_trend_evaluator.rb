# frozen_string_literal: true

module Live
  # Shared module: answers "is the underlying spot trend still alive?"
  #
  # Used by TrailingStopRule and PremiumMomentumFailureRule to avoid
  # exiting winners based on option premium noise when the underlying
  # index trend is fully intact.
  #
  # API: evaluate_spot_trend_for(tracker) → Hash
  #   trend_alive: Boolean  — false means the trend has broken
  #   severity: :none | :mild | :moderate | :severe
  #   supertrend_ok: Boolean
  #   adx_ok: Boolean
  #   no_choch: Boolean
  #   adx_value: Float
  module SpotTrendEvaluator
    # Returns { trend_alive:, severity:, supertrend_ok:, adx_ok:, no_choch:, adx_value: }
    # Fail-safe: returns trend_alive: true when data is unavailable (never exit on missing data).
    def evaluate_spot_trend_for(tracker)
      instrument = tracker.instrument || tracker.watchable&.instrument
      return fail_safe_result unless instrument

      side    = tracker.side.to_s
      min_adx = min_adx_to_hold

      # instrument.supertrend_signal(interval:) → :long_entry | :short_entry | nil
      # instrument.adx(period, interval:) → Float | nil
      st_signal = begin
                    instrument.supertrend_signal(interval: '1')
      rescue StandardError
                    nil
      end
      adx_value = begin
                    instrument.adx(14, interval: '1').to_f
      rescue StandardError
                    0.0
      end
      series = begin
                    instrument.candle_series(interval: '1')
      rescue StandardError
                    nil
      end
      choch_detected = detect_choch(series)

      # long_ce expects :long_entry, long_pe expects :short_entry
      expected_st = side == 'long_ce' ? :long_entry : :short_entry

      supertrend_ok = st_signal == expected_st
      adx_ok        = adx_value >= min_adx
      no_choch      = !choch_detected
      trend_alive   = supertrend_ok && adx_ok && no_choch

      severity = compute_severity(supertrend_ok, adx_ok, no_choch)

      { trend_alive: trend_alive, severity: severity,
        supertrend_ok: supertrend_ok, adx_ok: adx_ok,
        no_choch: no_choch, adx_value: adx_value }
    rescue StandardError => e
      Rails.logger.warn("[SpotTrendEvaluator] Error — defaulting to trend_alive: true: #{e.message}")
      fail_safe_result
    end

    private

    def fail_safe_result
      { trend_alive: true, severity: :none,
        supertrend_ok: true, adx_ok: true, no_choch: true, adx_value: 0.0 }
    end

    def min_adx_to_hold
      AlgoConfig.fetch.dig(:risk, :exits, :trailing, :spot_anchored, :min_adx_to_hold).to_f
    rescue StandardError
      15.0
    end

    def detect_choch(series)
      return false unless series

      structure = Smc::Detectors::Structure.new(series)
      structure.choch? != false
    rescue StandardError
      false
    end

    def compute_severity(supertrend_ok, adx_ok, no_choch)
      if !supertrend_ok && !adx_ok
        :severe
      elsif !supertrend_ok || !no_choch
        :moderate
      elsif !adx_ok
        :mild
      else
        :none
      end
    end
  end
end
