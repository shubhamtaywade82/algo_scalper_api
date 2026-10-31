# frozen_string_literal: true

module Investing
  module Allocation
    # Computes actual allocation from a valuation + policy (TDD §7.1).
    # Pure computation — no I/O, no LLM, fully unit-testable. This is the
    # deterministic core the whole Investing domain builds on.
    #
    # Arithmetic rules (test-pinned, A-ALC-01):
    #   - all math on BigDecimal, ROUND_HALF_UP to 4dp
    #   - actual_pct denominator = total portfolio value INCLUDING cash
    #   - drift_pct is in percentage points (actual - target)
    #   - sleeves with zero holdings report actual 0
    #   - bands are group-level; sleeve.within_band mirrors its group
    class Calculator < ApplicationService
      FULL = BigDecimal("100")
      SleeveCalc = Data.define(:sleeve_key, :group_key, :target_pct, :target_value,
                               :actual_value, :actual_pct, :drift_pct, :drift_value,
                               :band_lower_pct, :band_upper_pct, :within_band) do
        def within_band? = within_band
      end
      GroupCalc = Data.define(:group_key, :target_pct, :actual_pct, :drift_pct,
                              :band_lower_pct, :band_upper_pct, :within_band) do
        def within_band? = within_band
      end
      Calculations = Data.define(:total_value, :sleeves, :groups,
                                 :unclassified_value, :unclassified_pct)

      def initialize(policy:, valuation:)
        super()
        @policy = policy
        @valuation = valuation
      end

      def call
        Calculations.new(
          total_value: @valuation.total_value,
          sleeves: sleeve_calcs,
          groups: group_calcs,
          unclassified_value: @valuation.unclassified_value,
          unclassified_pct: pct_of(@valuation.unclassified_value)
        )
      end

      private

      def sleeve_calcs
        sleeves = @policy.sleeves.in_display_order.map do |sleeve|
          target_pct = BigDecimal(sleeve.target_pct.to_s)
          actual_value = @valuation.sleeve_value(sleeve.sleeve_key) || BigDecimal("0")
          SleeveCalc.new(
            sleeve_key: sleeve.sleeve_key,
            group_key: sleeve.group_key,
            target_pct: target_pct,
            target_value: target_value(target_pct),
            actual_value: actual_value,
            actual_pct: pct_of(actual_value),
            drift_pct: round4(pct_of(actual_value) - target_pct),
            drift_value: actual_value - target_value(target_pct),
            band_lower_pct: band_for(sleeve.group_key)&.first,
            band_upper_pct: band_for(sleeve.group_key)&.last,
            within_band: nil # filled from group pass below
          )
        end
        groups = group_calcs
        sleeves.map do |sleeve|
          group = groups.find { |g| g.group_key == sleeve.group_key }
          sleeve.with(within_band: group.within_band)
        end
      end

      def group_calcs
        groups = @policy.sleeves.group_by(&:group_key).map do |group_key, members|
          target = members.sum { |s| BigDecimal(s.target_pct.to_s) }
          actual_value = members.sum { |s| @valuation.sleeve_value(s.sleeve_key) || BigDecimal("0") }
          actual_pct = pct_of(actual_value)
          band = band_for(group_key)
          GroupCalc.new(
            group_key: group_key,
            target_pct: round4(target),
            actual_pct: actual_pct,
            drift_pct: round4(actual_pct - target),
            band_lower_pct: band&.first,
            band_upper_pct: band&.last,
            within_band: within_band?(actual_pct, band)
          )
        end
        groups.sort_by { |g| members_order.index(g.group_key) || members_order.size }
      end

      # Band bounds are inclusive for ACTUALS (touching the edge is not a
      # breach); policy TARGETS must sit strictly inside (PolicyValidator).
      def within_band?(actual_pct, band)
        return true if band.blank?

        actual_pct.between?(band.first, band.last)
      end

      def band_for(group_key)
        band = @policy.group_bands[group_key] || @policy.group_bands[group_key.to_sym]
        return if band.blank?

        [BigDecimal(fetch_value(band, "lower_pct").to_s),
         BigDecimal(fetch_value(band, "upper_pct").to_s)]
      end

      def members_order
        @members_order ||= @policy.sleeves.in_display_order.map(&:group_key).uniq
      end

      def target_value(target_pct)
        round4(@valuation.total_value * target_pct / FULL)
      end

      def pct_of(value)
        return BigDecimal("0") if @valuation.total_value.zero?

        round4(value * FULL / @valuation.total_value)
      end

      def round4(value)
        value.round(4, :half_up)
      end

      # Reads a value from a hash whose keys may be strings or symbols
      # (YAML via deep_symbolize_keys vs. hand-built hashes).
      def fetch_value(hash, key)
        hash[key] || hash[key.to_sym]
      end
    end
  end
end
