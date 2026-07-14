# frozen_string_literal: true

module Research
  class StatisticalValidator
    # Validates exit strategies using Bootstrap resampling and In-Sample/Out-of-Sample splits.
    # @param trades [Array<Hash>] List of parsed trades
    # @param strike_label [String] Option strike
    # @param iterations [Integer] Bootstrap iterations (default 1000)
    # @return [Hash] Validation report containing bootstrap CIs and IS/OOS comparisons
    def self.run(trades, strike_label: "ATM", iterations: 1000)
      return {} if trades.empty?

      exit_names = Research::ExitCaptureAnalyzer::STRATEGY_NAMES

      # 1. Chronological Split (IS: 60%, OOS: 40%)
      sorted_trades = trades.sort_by { |t| t[:entry_time] }
      is_size = (sorted_trades.size * 0.6).round
      is_size = 1 if is_size.zero?

      is_trades = sorted_trades.first(is_size)
      oos_trades = sorted_trades.drop(is_size)

      reports = {}

      exit_names.each do |name|
        # Pull return arrays with safe navigation in case some exit profiles are omitted
        all_rets = trades.map { |t| t[:strikes][strike_label][:exits][name]&.[](:return_pct) || 0.0 }
        is_rets = is_trades.map { |t| t[:strikes][strike_label][:exits][name]&.[](:return_pct) || 0.0 }
        oos_rets = oos_trades.map { |t| t[:strikes][strike_label][:exits][name]&.[](:return_pct) || 0.0 }

        # 2. Bootstrap Resampling (1000 iterations)
        bootstrap_means = []
        bootstrap_win_rates = []

        iterations.times do
          resampled = Array.new(all_rets.size) { all_rets.sample }
          bootstrap_means << (resampled.sum / resampled.size)
          
          wins = resampled.count { |r| r > 0.0 }
          bootstrap_win_rates << (wins.to_f / resampled.size) * 100.0
        end

        bootstrap_means.sort!
        bootstrap_win_rates.sort!

        # 95% Confidence Intervals
        ci_lower_idx = (iterations * 0.025).round
        ci_upper_idx = (iterations * 0.975).round - 1
        ci_lower_idx = 0 if ci_lower_idx < 0
        ci_upper_idx = bootstrap_means.size - 1 if ci_upper_idx >= bootstrap_means.size

        mean_ci = [bootstrap_means[ci_lower_idx], bootstrap_means[ci_upper_idx]]
        win_rate_ci = [bootstrap_win_rates[ci_lower_idx], bootstrap_win_rates[ci_upper_idx]]

        # In-Sample vs Out-of-Sample metrics
        is_avg = is_rets.any? ? (is_rets.sum / is_rets.size) : 0.0
        is_wins = is_rets.count { |r| r > 0.0 }
        is_win_rate = is_rets.any? ? (is_wins.to_f / is_rets.size) * 100.0 : 0.0

        oos_avg = oos_rets.any? ? (oos_rets.sum / oos_rets.size) : 0.0
        oos_wins = oos_rets.count { |r| r > 0.0 }
        oos_win_rate = oos_rets.any? ? (oos_wins.to_f / oos_rets.size) * 100.0 : 0.0

        # Compute decay of performance between IS and OOS
        expectancy_decay = is_avg != 0 ? ((is_avg - oos_avg) / is_avg.abs) * 100.0 : 0.0

        reports[name] = {
          bootstrap: {
            expected_return_95_ci: [mean_ci[0].round(2), mean_ci[1].round(2)],
            win_rate_95_ci: [win_rate_ci[0].round(2), win_rate_ci[1].round(2)]
          },
          split_validation: {
            is_sample_size: is_trades.size,
            is_avg_return_pct: is_avg.round(2),
            is_win_rate_pct: is_win_rate.round(2),
            oos_sample_size: oos_trades.size,
            oos_avg_return_pct: oos_avg.round(2),
            oos_win_rate_pct: oos_win_rate.round(2),
            expectancy_decay_pct: expectancy_decay.round(2)
          }
        }
      end

      reports
    end
  end
end
