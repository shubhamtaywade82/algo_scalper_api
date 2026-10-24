# frozen_string_literal: true

module Research
  # Pure computation over a contract's bar series: given an anchor timestamp,
  # trace the premium from entry through its peak, decay, and session end.
  #
  # Input bars are plain hashes ({ ts:, open:, high:, low:, close: }) rather
  # than AR records, so this can be unit-tested and reused without touching
  # the DB — callers (e.g. Research::LifecycleRunner) convert
  # Research::OptionBar rows into this shape first.
  class PremiumLifecycleAnalyzer
    DEFAULT_THRESHOLDS = [25, 50, 75, 100, 150, 200, 300].freeze
    DEFAULT_DECAY_RATIO = 0.9 # decay begins once price falls below 90% of peak and never recovers above it
    NEAR_PEAK_RATIO = 0.95 # bars counted as "at the peak" for peak_duration_minutes

    class << self
      def analyze(bars, entry_ts:, thresholds: DEFAULT_THRESHOLDS, decay_ratio: DEFAULT_DECAY_RATIO)
        sorted = bars.sort_by { |bar| bar[:ts] }
        entry_index = sorted.index { |bar| bar[:ts] >= entry_ts }
        return { status: "no_data" } if entry_index.nil?

        window = sorted[entry_index..]
        entry_bar = window.first
        entry_premium = entry_bar[:close].to_f
        return { status: "no_data" } if entry_premium <= 0

        peak_index, peak_premium = peak(window)
        peak_bar = window[peak_index]

        {
          status: "computed",
          entry_ts: entry_bar[:ts],
          entry_premium: entry_premium,
          peak_ts: peak_bar[:ts],
          peak_premium: peak_premium,
          peak_return_pct: Research::PercentChange.of(peak_premium, entry_premium),
          minutes_to_peak: minutes_between(entry_bar[:ts], peak_bar[:ts]),
          peak_duration_minutes: peak_duration_minutes(window, peak_index, peak_premium),
          decay_start_ts: decay_start_ts(window, peak_index, peak_premium, decay_ratio),
          end_ts: window.last[:ts],
          end_premium: window.last[:close].to_f,
          end_return_pct: Research::PercentChange.of(window.last[:close].to_f, entry_premium),
          max_drawdown_after_peak_pct: max_drawdown_after_peak(window, peak_index, peak_premium),
          threshold_minutes: threshold_minutes(window, entry_bar, entry_premium, thresholds)
        }
      end

      private

      # Peak is measured off intracandle highs (a premium can touch a level
      # without closing there); ties resolve to the earliest occurrence.
      def peak(window)
        peak_index = 0
        peak_value = window.first[:high].to_f
        window.each_with_index do |bar, i|
          value = bar[:high].to_f
          if value > peak_value
            peak_value = value
            peak_index = i
          end
        end
        [peak_index, peak_value]
      end

      def peak_duration_minutes(window, peak_index, peak_premium)
        threshold = peak_premium * NEAR_PEAK_RATIO
        last_near_index = peak_index
        (peak_index...window.size).each do |i|
          break if window[i][:high].to_f < threshold

          last_near_index = i
        end
        minutes_between(window[peak_index][:ts], window[last_near_index][:ts])
      end

      # First bar after the peak beyond which the close never again recovers
      # above decay_ratio * peak_premium. Single backward pass over the tail
      # (O(n)) instead of rescanning the remaining suffix for every candidate
      # index (which was O(n^2)): track the last index (from the end) whose
      # close still met the threshold — decay starts right after it.
      def decay_start_ts(window, peak_index, peak_premium, decay_ratio)
        threshold = peak_premium * decay_ratio
        last_recovery_index = peak_index
        (peak_index...window.size).each do |i|
          last_recovery_index = i if window[i][:close].to_f >= threshold
        end
        return nil if last_recovery_index == window.size - 1

        window[last_recovery_index + 1][:ts]
      end

      def max_drawdown_after_peak(window, peak_index, peak_premium)
        return 0.0 if peak_premium.zero?

        min_low = window[peak_index..].map { |bar| bar[:low].to_f }.min
        Research::PercentChange.of(min_low, peak_premium).abs
      end

      def threshold_minutes(window, entry_bar, entry_premium, thresholds)
        thresholds.index_with do |threshold_pct|
          target = entry_premium * (1 + (threshold_pct / 100.0))
          hit_bar = window.find { |bar| bar[:high].to_f >= target }
          hit_bar ? minutes_between(entry_bar[:ts], hit_bar[:ts]) : nil
        end.transform_keys(&:to_s)
      end

      def minutes_between(from_ts, to_ts)
        ((to_ts - from_ts) / 60).round
      end
    end
  end
end
