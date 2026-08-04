# frozen_string_literal: true

module Research
  # Grid-searches Research::ExitCaptureAnalyzer.simulate_dynamic_hold_exit's
  # threshold params over already-scored Research::OptionCandidate rows
  # (produced by research:run_signal / research:run_regime_scan), ranking
  # combos by avg return — answers "what theta barrier / SL / IV-crush
  # actually works" instead of eyeballing a single fixed-threshold run.
  class HoldExitSweep
    GRID = {
      theta_minutes: [30, 45, 60],
      hard_sl_pct: [0.20, 0.25, 0.30],
      iv_crush_pct: [0.05, 0.10, 0.15]
    }.freeze

    class << self
      def run(scope: Research::OptionCandidate.where(status: "scored"))
        candidates = scope.to_a
        combos.map { |combo| combo.merge(simulate_combo(candidates, combo)) }
              .sort_by { |row| -row[:avg_return_pct] }
      end

      private

      def combos
        GRID[:theta_minutes].product(GRID[:hard_sl_pct], GRID[:iv_crush_pct]).map do |theta, sl, iv|
          { theta_minutes: theta, hard_sl_pct: sl, iv_crush_pct: iv }
        end
      end

      def simulate_combo(candidates, combo)
        results = candidates.filter_map { |candidate| simulate_candidate(candidate, combo) }
        return { sample_size: 0, win_rate_pct: 0.0, avg_return_pct: 0.0, avg_holding_minutes: 0.0 } if results.empty?

        wins = results.count { |r| r[:return_pct].positive? }
        {
          sample_size: results.size,
          win_rate_pct: (wins / results.size.to_f * 100).round(2),
          avg_return_pct: (results.sum { |r| r[:return_pct] } / results.size).round(2),
          avg_holding_minutes: (results.sum { |r| r[:holding_minutes] } / results.size.to_f).round(1)
        }
      end

      def simulate_candidate(candidate, combo)
        return nil if candidate.entry_price.blank? || candidate.entry_timestamp.blank?

        window = same_strike_window(candidate)
        return nil if window.blank?

        entry_price = candidate.entry_price.to_f
        option_candles = window.map { |bar| to_candle(bar) }
        underlying_candles = window.map { |bar| to_synthetic_underlying_candle(bar) }
        breakout_type = candidate.option_type.to_s.upcase == "PE" ? :bearish : :bullish

        exit_price, exit_time, = Research::ExitCaptureAnalyzer.simulate_dynamic_hold_exit(
          entry_price, 0, option_candles, underlying_candles, breakout_type, **combo
        )

        {
          return_pct: ((exit_price - entry_price) / entry_price) * 100.0,
          holding_minutes: ((exit_time - window.first.ts) / 60).round
        }
      end

      # Mirrors Research::TradeScorer#same_strike_window — the rolling-option
      # "ATM" series re-resolves strike per bar as spot drifts, so a real
      # position only ever holds the strike actually filled at entry.
      def same_strike_window(candidate)
        Research::OptionBar.where(
          underlying_symbol: candidate.underlying_symbol, expiry_flag: candidate.expiry_flag,
          option_type: candidate.option_type, strike_label: candidate.strike_label,
          interval: candidate.interval, actual_strike: candidate.actual_strike,
          ts: candidate.entry_timestamp..(candidate.entry_timestamp.to_date + 1)
        ).order(:ts)
      end

      def to_candle(bar)
        {
          timestamp: bar.ts, open: bar.open.to_f, high: bar.high.to_f, low: bar.low.to_f,
          close: bar.close.to_f, volume: bar.volume.to_i, oi: bar.oi.to_i, iv: bar.iv.to_f
        }
      end

      def to_synthetic_underlying_candle(bar)
        spot = bar.spot.to_f
        { timestamp: bar.ts, open: spot, high: spot, low: spot, close: spot, volume: 0 }
      end
    end
  end
end
