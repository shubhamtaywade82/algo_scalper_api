# frozen_string_literal: true

module Research
  class NonlinearFeatureImportance
    # Computes Shannon Information Gain (Mutual Information) and binned conditional probabilities.
    # @param trades [Array<Hash>] List of trades/events
    # @param strike_label [String] Option strike
    # @return [Hash] Dictionary containing Information Gain ranks and binned probability tables
    def self.analyze(trades, strike_label: "ATM")
      return {} if trades.size <= 2

      # Classify outcome: Y = 1 if option MFE >= 30%, else 0
      y = trades.map { |t| (t[:strikes][strike_label][:mfe_pct] >= 30.0) ? 1 : 0 }
      base_entropy = entropy(y)

      # 1. Binned Feature extractors
      feature_bins = {
        gap_regime: ->(t) {
          pct = t[:gap_pct] || 0.0
          if pct < -0.4 then :large_gap_down
          elsif pct < -0.15 then :mod_gap_down
          elsif pct <= 0.15 then :flat_open
          elsif pct <= 0.4 then :mod_gap_up
          else :large_gap_up
          end
        },
        or_width_regime: ->(t) {
          width = t[:or_width] || 0.0
          if width < 25.0 then :narrow_range
          elsif width < 50.0 then :mod_range
          else :wide_range
          end
        },
        volatility_regime: ->(t) {
          t[:regime]&.[](:volatility) || :normal
        },
        trend_regime: ->(t) {
          t[:regime]&.[](:trend) || :mean_reverting
        },
        adx_strength: ->(t) {
          adx = t[:adx] || 0.0
          if adx < 20.0 then :low_trend
          elsif adx <= 30.0 then :mod_trend
          else :strong_trend
          end
        }
      }

      info_gains = {}
      probability_tables = {}

      feature_bins.each do |name, bin_extractor|
        # Bin values for each trade
        x_bins = trades.map { |t| bin_extractor.call(t) }

        # Information Gain Calculation
        gain = shannon_information_gain(x_bins, y, base_entropy)
        info_gains[name] = gain.round(4)

        # Conditional Probability Table: P(MFE >= 30% | Bin)
        unique_bins = x_bins.uniq
        probability_tables[name] = unique_bins.each_with_object({}) do |bin, memo|
          matching_idx = x_bins.each_index.select { |i| x_bins[i] == bin }
          sample_size = matching_idx.size
          successes = matching_idx.count { |i| y[i] == 1 }
          prob = sample_size > 0 ? (successes.to_f / sample_size) * 100.0 : 0.0

          memo[bin] = {
            sample: sample_size,
            probability_pct: prob.round(2)
          }
        end
      end

      # Sort Information Gain descending
      sorted_gains = info_gains.sort_by { |_, g| -g }.to_h

      {
        information_gains: sorted_gains,
        conditional_probability_tables: probability_tables
      }
    end

    private

    def self.entropy(labels)
      return 0.0 if labels.empty?

      counts = labels.group_by { |x| x }.transform_values(&:size)
      total = labels.size.to_f

      counts.values.map { |count|
        p = count / total
        -p * Math.log2(p)
      }.sum
    end

    def self.shannon_information_gain(x, y, base_entropy)
      total = x.size.to_f
      return 0.0 if total.zero?

      # Calculate conditional entropy H(Y|X)
      grouped = x.each_index.group_by { |i| x[i] }
      conditional_entropy = grouped.values.map { |indices|
        subset_y = indices.map { |i| y[i] }
        weight = indices.size / total
        weight * entropy(subset_y)
      }.sum

      base_entropy - conditional_entropy
    end
  end
end
