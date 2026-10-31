# frozen_string_literal: true

module Investing
  module Allocation
    # Validates a mandate hash (config/investing.yml or user input) BEFORE it
    # is compiled into policy rows (TDD §7.3). Pure function over the mandate
    # structure — no DB access, no side effects.
    #
    # Handles both string-keyed and symbol-keyed mandates (hand-built hashes
    # vs. config_for(:investing).deep_symbolize_keys) and normalizes to
    # string-keyed output, matching what JSONB columns store.
    #
    # Weight summation uses BigDecimal against exactly 100 — 99.9999 is a
    # failure, never rounded through (A-POL-01).
    class PolicyValidator < ApplicationService
      GROUP_KEYS = %w[equity fixed_income real_assets cash_alternatives].freeze
      FULL_ALLOCATION = BigDecimal("100")
      MIN_THRESHOLD_PCT = BigDecimal("0.05")

      def initialize(mandate:)
        super()
        @mandate = mandate || {}
        @errors = []
      end

      def call
        allocation = extract_allocation
        return Investing::Result.failure(@errors) if @errors.any?

        validate_sleeves(allocation)
        validate_weights(allocation)
        validate_bands(allocation)
        validate_constraints
        validate_threshold
        validate_deployment
        return Investing::Result.failure(@errors) if @errors.any?

        Investing::Result.success(normalized: normalize(allocation))
      end

      private

      def extract_allocation
        allocation = fetch(@mandate, "allocation")
        @errors << [:allocation_missing, {}] if !allocation.is_a?(Hash) || allocation.empty?
        allocation.is_a?(Hash) ? allocation : {}
      end

      def validate_sleeves(allocation)
        allocation.each do |sleeve_key, spec|
          @errors << [:invalid_sleeve_key, { sleeve: sleeve_key }] unless sleeve_key.to_s.match?(/\A[a-z0-9_]+\z/)

          group = fetch(spec, "group") if spec.is_a?(Hash)
          if group.blank?
            @errors << [:unknown_group_key, { sleeve: sleeve_key, group: group }]
          elsif GROUP_KEYS.exclude?(group.to_s)
            @errors << [:unknown_group_key, { sleeve: sleeve_key, group: group.to_s }]
          end

          pct = fetch(spec, "target_pct") if spec.is_a?(Hash)
          @errors << [:invalid_pct_range, { key: sleeve_key, value: pct }] unless pct.is_a?(Numeric) && pct.positive? && pct <= 100
        end
      end

      def validate_weights(allocation)
        sum = allocation.values.sum(BigDecimal("0")) do |spec|
          BigDecimal(fetch(spec, "target_pct").to_s)
        rescue TypeError, ArgumentError
          BigDecimal("0")
        end
        return if sum == FULL_ALLOCATION

        @errors << [:weights_do_not_sum_to_100, { sum: sum }]
      end

      def validate_bands(allocation)
        bands = fetch(rebalancing_section, "bands") || {}
        return if bands.blank?

        group_targets = allocation.each_with_object(Hash.new(BigDecimal("0"))) do |(_key, spec), acc|
          acc[fetch(spec, "group").to_s] += BigDecimal(fetch(spec, "target_pct").to_s)
        end

        bands.each do |group, band|
          next unless band.is_a?(Hash)

          lower = BigDecimal(fetch(band, "lower_pct").to_s)
          upper = BigDecimal(fetch(band, "upper_pct").to_s)
          target = group_targets[group.to_s]

          if lower >= upper
            @errors << [:invalid_band, { group: group, band: { lower_pct: lower, upper_pct: upper } }]
          elsif target.blank? || target <= lower || target >= upper
            @errors << [:band_excludes_target,
                        { group: group, band: { lower_pct: lower, upper_pct: upper }, target: target }]
          end
        end
      end

      def validate_constraints
        constraints = constraints_section
        single = fetch(constraints, "max_single_stock_pct")
        sector = fetch(constraints, "max_sector_pct")
        return unless single.is_a?(Numeric) && sector.is_a?(Numeric)
        return if single <= sector

        @errors << [:constraints_inconsistent,
                    { detail: "max_single_stock_pct (#{single}) exceeds max_sector_pct (#{sector})" }]
      end

      def validate_threshold
        threshold = fetch(rebalancing_section, "threshold_to_act_pct")
        return if threshold.blank?
        return if BigDecimal(threshold.to_s) >= MIN_THRESHOLD_PCT

        @errors << [:threshold_too_small, { value: threshold, minimum: MIN_THRESHOLD_PCT.to_s("F") }]
      end

      def validate_deployment
        tranches = fetch(deployment_section, "equity_tranches")
        weeks = fetch(deployment_section, "deployment_weeks")

        if tranches.present? && !(1..12).cover?(tranches)
          @errors << [:deployment_out_of_range, { key: "equity_tranches", value: tranches }]
        end
        return unless weeks.present? && !(1..104).cover?(weeks)

        @errors << [:deployment_out_of_range, { key: "deployment_weeks", value: weeks }]
      end

      def normalize(allocation)
        {
          "allocation" => allocation.to_h do |key, spec|
            [key.to_s,
             { "group" => fetch(spec, "group").to_s,
               "target_pct" => BigDecimal(fetch(spec, "target_pct").to_s) }]
          end,
          "constraints" => constraints_section.deep_stringify_keys,
          "rebalancing" => rebalancing_section.deep_stringify_keys,
          "deployment" => deployment_section.deep_stringify_keys
        }
      end

      def constraints_section = @mandate[:constraints] || @mandate["constraints"] || {}
      def rebalancing_section = @mandate[:rebalancing] || @mandate["rebalancing"] || {}
      def deployment_section = @mandate[:deployment] || @mandate["deployment"] || {}

      # Reads a value from a hash whose keys may be strings or symbols.
      def fetch(hash, key)
        return nil unless hash.is_a?(Hash)

        hash[key.to_s].nil? ? hash[key.to_sym] : hash[key.to_s]
      end
    end
  end
end
