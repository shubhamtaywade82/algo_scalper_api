# frozen_string_literal: true

module Research
  # Forensic scan of research_option_bars: finds every contract (a real
  # actual_strike, not the relabeled "ATM" series) whose intraday premium
  # rose min_gain_pct+ from its day's open to peak, and captures what the
  # underlying spot and IV were doing at that exact moment. Grouping by
  # actual_strike (not strike_label) matters — the rolling "ATM" label
  # re-resolves to a different real strike as spot drifts (see
  # Research::TradeScorer's same_strike_window comment), so grouping by
  # label alone would blend unrelated contracts into one "move".
  class ExplosiveMoveScanner
    DEFAULT_MIN_GAIN_PCT = 0.5
    DEFAULT_MIN_PREMIUM = 10.0

    class << self
      def scan(symbol:, from_date:, to_date:, expiry_flag: nil,
               min_gain_pct: DEFAULT_MIN_GAIN_PCT, min_premium: DEFAULT_MIN_PREMIUM)
        bars = Research::OptionBar
               .where(underlying_symbol: symbol.to_s.upcase)
               .where(ts: Time.zone.parse(from_date.to_s).beginning_of_day..Time.zone.parse(to_date.to_s).end_of_day)
               .where.not(actual_strike: [nil, 0])
        bars = bars.where(expiry_flag: expiry_flag) if expiry_flag.present?

        bars.order(:ts).group_by { |bar| [bar.ts.to_date, bar.option_type, bar.actual_strike] }
                       .filter_map { |key, rows| build_move(key, rows, min_gain_pct, min_premium) }
                       .sort_by { |row| -row[:gain_pct] }
      end

      private

      def build_move((date, option_type, strike), rows, min_gain_pct, min_premium)
        open_price = rows.first.open.to_f
        return nil if open_price < min_premium

        peak_row = rows.max_by { |bar| bar.high.to_f }
        gain_pct = (peak_row.high.to_f - open_price) / open_price
        return nil if gain_pct < min_gain_pct

        entry_row = rows.first
        spot_start = entry_row.spot.to_f
        spot_end = peak_row.spot.to_f

        {
          date: date, option_type: option_type, strike: strike,
          open_price: open_price.round(2), peak_price: peak_row.high.to_f.round(2),
          gain_pct: (gain_pct * 100).round(0), time_of_peak: peak_row.ts,
          spot_start: spot_start.round(2), spot_end: spot_end.round(2),
          spot_move_pct: spot_start.positive? ? (((spot_end - spot_start) / spot_start) * 100.0).round(2) : nil,
          iv_start: entry_row.iv&.round(2), iv_peak: peak_row.iv&.round(2),
          vega_expansion: entry_row.iv && peak_row.iv ? (peak_row.iv - entry_row.iv).round(2) : nil
        }
      end
    end
  end
end
