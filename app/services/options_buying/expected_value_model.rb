# frozen_string_literal: true

module OptionsBuying
  # Pure math for long-option intraday EV in units of risk (1 unit = full stop loss).
  #
  #   EV = (P_win × R) - (P_loss × 1),  P_loss = 1 - P_win
  #
  class ExpectedValueModel
    DEFAULT_WIN_RATES = (0.20..0.65).step(0.05).map { |r| r.round(2) }.freeze
    DEFAULT_REWARD_MULTIPLES = [1.5, 2.0, 2.5, 3.0, 3.5, 4.0].freeze

    class << self
      def ev(win_probability:, reward_multiple:)
        p_win = win_probability.to_f.clamp(0.0, 1.0)
        r = reward_multiple.to_f
        return 0.0 if r.negative?

        p_loss = 1.0 - p_win
        ((p_win * r) - (p_loss * 1.0)).round(4)
      end

      def break_even_win_rate(reward_multiple:)
        r = reward_multiple.to_f
        return 1.0 if r <= 0.0

        (1.0 / (r + 1.0)).round(4)
      end

      def reward_multiple(sl_pct:, tp_pct:)
        sl = sl_pct.to_f
        tp = tp_pct.to_f
        return 0.0 if sl <= 0.0

        (tp / sl).round(4)
      end

      def grid(win_rates: DEFAULT_WIN_RATES, reward_multiples: DEFAULT_REWARD_MULTIPLES)
        win_rates = Array(win_rates)
        reward_multiples = Array(reward_multiples)

        {
          win_rates: win_rates,
          reward_multiples: reward_multiples,
          cells: reward_multiples.map do |r|
            {
              reward_multiple: r,
              break_even_win_rate: break_even_win_rate(reward_multiple: r),
              by_win_rate: win_rates.index_with { |p| ev(win_probability: p, reward_multiple: r) }
            }
          end
        }
      end
    end
  end
end
