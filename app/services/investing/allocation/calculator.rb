# frozen_string_literal: true

require "bigdecimal"

module Investing
  module Allocation
    # Pure allocation math (TDD §7.1): target vs actual weights, drift,
    # equity-band status. No DB writes, no wall clock, no network. Works with
    # AR AllocationSleeve rows or any duck-typed sleeve responding to
    # sleeve_key / asset_class / target_weight_pct (and optionally sleeve_name).
    #
    # Rounding contract (TDD §7.1 rule 6): every reported percentage is the
    # exact quotient rounded half-up to 2dp; the band comparison uses the
    # ROUNDED equity weight; equity_weight_pct is computed from raw sleeve
    # values, never by re-summing rounded rows.
    class Calculator
      DEFAULT_BAND = [BigDecimal("50"), BigDecimal("60")].freeze
      DEFAULT_DRIFT_THRESHOLD = BigDecimal("5")
      ZERO = BigDecimal("0")
      HUNDRED = BigDecimal("100")

      # @param sleeves [Enumerable] sleeve rows/structs
      # @param valuation [Object] responds to total_value, cash_value and
      #        sleeve_values (Hash{String=>BigDecimal} sleeve_key => market value)
      # @param band [Array(BigDecimal, BigDecimal)] equity band [min, max] pct
      # @param drift_threshold [BigDecimal] absolute pp drift that "breaches"
      # @return [Investing::Allocation::Report]
      def report(sleeves, valuation, band: DEFAULT_BAND, drift_threshold: DEFAULT_DRIFT_THRESHOLD)
        total = to_d(valuation.total_value)
        sleeve_values = Hash(valuation.sleeve_values).transform_values { |v| to_d(v) }

        rows = sleeves.map do |sleeve|
          value = sleeve_values.fetch(sleeve.sleeve_key, ZERO)
          # TDD §7.1 rule 2: cash is attributed to the cash sleeve (and to the
          # denominator via total_value) — uninvested money shows up as
          # cash-sleeve overweight, never spread across sleeves.
          value += to_d(valuation.cash_value) if sleeve.asset_class == "cash"
          Row.new(
            sleeve_key: sleeve.sleeve_key,
            sleeve_name: sleeve.respond_to?(:sleeve_name) ? sleeve.sleeve_name : sleeve.sleeve_key,
            asset_class: sleeve.asset_class,
            target_pct: pct(sleeve.target_weight_pct, HUNDRED),
            actual_value: value,
            total_value: total
          ).freeze
        end

        equity_value = sleeves.sum do |sleeve|
          next ZERO unless sleeve.asset_class == "equity"

          sleeve_values.fetch(sleeve.sleeve_key, ZERO)
        end
        equity_weight = pct(equity_value, total)

        Report.new(
          rows: rows.freeze,
          equity_weight_pct: equity_weight,
          band_min: to_d(band[0]),
          band_max: to_d(band[1]),
          drift_threshold: to_d(drift_threshold)
        ).freeze
      end

      private

      def to_d(value)
        BigDecimal(value.to_s)
      end

      # exact quotient * 100, rounded half-up to 2dp; zero when total is zero.
      def pct(value, total)
        return ZERO if total.zero?

        ((value * HUNDRED) / total).round(2, :half_up)
      end
    end

    # Immutable result (TDD §7.1).
    class Report
      attr_reader :rows, :equity_weight_pct, :band_min, :band_max, :drift_threshold, :breached_sleeves

      def initialize(rows:, equity_weight_pct:, band_min:, band_max:, drift_threshold:)
        @rows = rows
        @equity_weight_pct = equity_weight_pct
        @band_min = band_min
        @band_max = band_max
        @drift_threshold = drift_threshold
        # computed eagerly: Report instances are frozen (immutable value objects)
        @breached_sleeves = rows.select { |row| row.drift_pct.abs >= drift_threshold }
      end

      def within_equity_band?
        equity_weight_pct.between?(band_min, band_max)
      end
      alias in_equity_band? within_equity_band?

      def row(sleeve_key)
        rows.find { |r| r.sleeve_key == sleeve_key }
      end

      def to_h
        {
          equity_weight_pct: equity_weight_pct.to_s("F"),
          within_equity_band: within_equity_band?,
          band: { min: band_min.to_s("F"), max: band_max.to_s("F") },
          rows: rows.map(&:to_h)
        }
      end
    end

    # One sleeve line (TDD §7.1). frozen value object.
    class Row
      attr_reader :sleeve_key, :sleeve_name, :asset_class, :target_pct, :actual_value, :total_value, :actual_pct

      def initialize(sleeve_key:, sleeve_name:, asset_class:, target_pct:,
                     actual_value:, total_value:)
        @sleeve_key = sleeve_key
        @sleeve_name = sleeve_name
        @asset_class = asset_class
        @target_pct = target_pct
        @actual_value = actual_value
        @total_value = total_value
        # computed eagerly: Row instances are frozen (immutable value objects)
        @actual_pct =
          if total_value.zero?
            BigDecimal("0")
          else
            ((actual_value * BigDecimal("100")) / total_value).round(2, :half_up)
          end
      end

      def target_value
        (target_pct / BigDecimal("100")) * total_value
      end

      def drift_pct
        (actual_pct - target_pct).round(2, :half_up)
      end

      def delta_value
        actual_value - target_value
      end

      def to_h
        {
          sleeve_key: sleeve_key, sleeve_name: sleeve_name, asset_class: asset_class,
          target_pct: target_pct.to_s("F"), actual_pct: actual_pct.to_s("F"),
          drift_pct: drift_pct.to_s("F"),
          target_value: target_value.to_s("F"), actual_value: actual_value.to_s("F"),
          delta_value: delta_value.to_s("F")
        }
      end
    end
  end
end
