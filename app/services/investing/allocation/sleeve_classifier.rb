# frozen_string_literal: true

module Investing
  module Allocation
    # Maps an instrument to a policy sleeve (TDD §7.4).
    #
    # Resolution order:
    #   1. explicit symbol override in a policy sleeve's instrument_filter
    #   2. static asset-class map (with ETF keyword hints)
    #   3. nil — surfaces in Calculator.unclassified_value and blocks order
    #      planning for that holding until classified
    #
    # The static map is intentionally conservative: unknown shapes stay
    # unclassified rather than being guessed into a sleeve.
    class SleeveClassifier < ApplicationService
      # Substring routing (no \b anchors): real tickers embed keywords with
      # no word boundaries (GOLDBEES, NASDAQ100ETF, MID150BEES). Order matters:
      # specific sleeves before generic; explicit symbol overrides always win.
      ETF_KEYWORD_SLEEVES = [
        [/mid ?cap|small ?cap|next ?50|junior|nifty ?150|mid150/i, "indian_mid_small_cap"],
        [/gold|silver|gld|slv/i, "gold_silver_etfs"],
        [/infra|invit/i, "infrastructure_funds"],
        [/nasdaq|us ?500|s&p|global|international|world|feeder/i, "global_equity"],
        [/tech|digital|clean|green|energy/i, "technology_clean_energy"],
        [/liquid|money|overnight|cash/i, "cash_liquid_funds"]
      ].freeze

      ASSET_CLASS_SLEEVES = {
        "equity" => "indian_large_cap",
        "reit_invit" => "reits_invits",
        "government_bond" => "government_aaa_bonds",
        "corporate_bond" => "short_duration_debt",
        "liquid_fund" => "cash_liquid_funds"
      }.freeze

      def initialize(instrument, policy:)
        super()
        @instrument = instrument
        @policy = policy
      end

      # @return [String, nil] sleeve_key present in this policy, or nil
      def call
        sleeve = explicit_override || from_asset_class
        return nil if sleeve.blank?
        return nil unless sleeve_keys.include?(sleeve)

        sleeve
      end

      private

      def sleeve_keys
        @sleeve_keys ||= @policy.sleeves.in_display_order.to_set(&:sleeve_key)
      end

      def explicit_override
        symbols = instrument_symbols
        @policy.sleeves.in_display_order.each do |sleeve|
          filter = sleeve.instrument_filter || {}
          listed = Array(filter["symbols"] || filter[:symbols])
          return sleeve.sleeve_key if listed.intersect?(symbols)
        end
        nil
      end

      def from_asset_class
        asset_class = @instrument.asset_class.to_s
        return nil if asset_class.blank?

        if asset_class == "etf"
          name = [@instrument.display_name, @instrument.symbol_name].compact.join(" ")
          return ETF_KEYWORD_SLEEVES.find { |pattern, _| name.match?(pattern) }&.last ||
                 "indian_large_cap"
        end

        ASSET_CLASS_SLEEVES[asset_class]
      end

      def instrument_symbols
        [@instrument.symbol_name, @instrument.custom_symbol, @instrument.display_name]
          .compact.map { |value| value.to_s.upcase.delete(" ") }
      end
    end
  end
end
