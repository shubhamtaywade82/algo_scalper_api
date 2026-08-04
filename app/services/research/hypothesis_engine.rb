# frozen_string_literal: true

module Research
  class HypothesisEngine
    # Helper to calculate combinations nCr
    def self.choose(n, k)
      return 1 if k.zero? || k == n
      return 0 if k > n || k.negative? || n.negative?
      prod = 1
      (1..k).each do |i|
        prod = prod * (n - i + 1) / i
      end
      prod
    end

    # Helper to calculate one-tailed Binomial p-value
    # H0: success_rate <= p_null
    # Ha: success_rate > p_null
    def self.binomial_p_value(k, n, p_null = 0.5)
      return 1.0 if n.zero?
      sum = 0.0
      (k..n).each do |i|
        sum += choose(n, i) * (p_null**i) * ((1.0 - p_null)**(n - i))
      end
      sum
    end

    # Represents an executable quantitative hypothesis.
    class Hypothesis
      attr_accessor :verdict, :reason
      attr_reader :description, :success_rate, :expectancy, :sample_size, :p_value

      def initialize(description, filter_proc, outcome_proc)
        @description = description
        @filter_proc = filter_proc
        @outcome_proc = outcome_proc
        @sample_size = 0
        @success_rate = 0.0
        @expectancy = 0.0
        @p_value = 1.0
        @verdict = :insufficient_evidence
        @reason = "Not evaluated yet"
      end

      # Evaluates the hypothesis against simulated trade events.
      def evaluate(trades)
        matching_trades = trades.select { |t| @filter_proc.call(t) }
        @sample_size = matching_trades.size
        if @sample_size.zero?
          @verdict = :insufficient_evidence
          @reason = "No matching sample events found"
          return
        end

        success_count = matching_trades.count { |t| @outcome_proc.call(t) }
        @success_rate = (success_count.to_f / @sample_size) * 100.0

        # Calculate expectation (avg return relative to a standard 20% risk multiplier)
        returns = matching_trades.map do |t|
          atm_strike = t[:strikes]["ATM"]
          exit_data = atm_strike&.[](:exits)&.[](:hybrid_divergence)
          exit_data ? exit_data[:return_pct] : 0.0
        end

        avg_return = returns.sum / @sample_size
        @expectancy = avg_return / 20.0 # Expected R-multiple

        # Calculate Binomial p-value under null hypothesis p_null = 0.50 (random coin flip)
        @p_value = HypothesisEngine.binomial_p_value(success_count, @sample_size, 0.5)

        if @sample_size < 250
          @verdict = :needs_more_samples
          @reason = "Sample size of #{@sample_size} is below the expected minimum of 250"
        else
          @verdict = :rejected
          @reason = nil
        end
      end
    end

    # Runs the hypothesis validation suite over all trade opportunities.
    # Applies Benjamini-Hochberg False Discovery Rate correction to limit false positives.
    # @param trades [Array<Hash>] List of trade opportunities
    # @return [Array<Hypothesis>] Validated hypotheses
    def self.run(trades)
      hypotheses = [
        # Hypothesis 1: Gap down + entry below VWAP -> Bearish PE ATM MFE >= 30%
        Hypothesis.new(
          "Gap-down (< -0.15%) + entry below VWAP -> Bearish PE ATM MFE >= 30%",
          ->(t) { t[:breakout_type] == :bearish && t[:gap_pct] < -0.15 && t[:vwap_dist].negative? },
          ->(t) { t[:strikes]["ATM"][:mfe_pct] >= 30.0 }
        ),
        # Hypothesis 2: Inside Day Compression -> Sustained Breakout
        Hypothesis.new(
          "Inside Day + Narrow OR (< 35 pts) + ADX > 20 -> Sustained breakout",
          ->(t) { t[:is_inside_day] && t[:or_width] < 35.0 && t[:adx] && t[:adx] > 20.0 },
          ->(t) { t[:sustained] }
        ),
        # Hypothesis 3: Wide OR -> Mean Reversion Fakeout
        Hypothesis.new(
          "Wide OR (> 50 pts) -> Breakout fails / mean reverts",
          ->(t) { t[:or_width] > 50.0 },
          ->(t) { t[:failed] }
        ),
        # Hypothesis 4: High Ignition Velocity -> Option Expansion >= 30%
        Hypothesis.new(
          "High Ignition Velocity (> 3.0 pts/min) -> Option MFE >= 30%",
          ->(t) { t[:ignition] && t[:ignition][:ignition_velocity].abs >= 3.0 },
          ->(t) { t[:strikes]["ATM"][:mfe_pct] >= 30.0 }
        )
      ]

      # Step 1: Evaluate all hypotheses
      hypotheses.each { |h| h.evaluate(trades) }

      # Set verdict for sample_size == 0
      hypotheses.each do |h|
        if h.sample_size.zero?
          h.verdict = :insufficient_evidence
          h.reason = "No matching sample events found"
        end
      end

      # Get hypotheses eligible for statistical significance testing (sample_size >= 250)
      testable_hyps = hypotheses.select { |h| h.sample_size >= 250 }

      if testable_hyps.any?
        # Step 2: Sort by p-value in ascending order for Benjamini-Hochberg (BH) FDR correction
        sorted_hyps = testable_hyps.sort_by(&:p_value)
        m = sorted_hyps.size
        fdr_target = 0.10 # Target FDR limit 10%

        # Find the largest index i (1-indexed) such that P_i <= (i/m) * fdr_target
        max_significant_idx = -1
        sorted_hyps.each_with_index do |h, idx|
          i = idx + 1
          threshold = (i.to_f / m) * fdr_target
          if h.p_value <= threshold
            max_significant_idx = idx
          end
        end

        # Step 3: Assign verdicts: accepted (significant) vs rejected
        sorted_hyps.each_with_index do |h, idx|
          threshold = ((idx + 1).to_f / m) * fdr_target
          if idx <= max_significant_idx
            if h.expectancy > 0.0 && h.success_rate >= 60.0
              h.verdict = :accepted
              h.reason = "Passes BH FDR correction (p-value: #{h.p_value.round(4)} <= threshold: #{threshold.round(4)}) and satisfies performance criteria (expectancy: #{h.expectancy.round(2)}R, success_rate: #{h.success_rate.round(1)}%)"
            else
              h.verdict = :rejected
              reasons = []
              reasons << "expectancy #{h.expectancy.round(2)}R <= 0.0R" if h.expectancy <= 0.0
              reasons << "success_rate #{h.success_rate.round(1)}% < 60.0%" if h.success_rate < 60.0
              h.reason = "Passes significance but fails performance criteria: #{reasons.join(', ')}"
            end
          else
            h.verdict = :rejected
            h.reason = "Fails Benjamini-Hochberg FDR correction (p-value: #{h.p_value.round(4)} > threshold: #{threshold.round(4)})"
          end
        end
      end

      hypotheses
    end
  end
end
