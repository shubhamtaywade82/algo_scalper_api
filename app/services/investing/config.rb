# frozen_string_literal: true

require "bigdecimal"

module Investing
  # Boot-time loader + validator for config/investing.yml (TDD §5).
  #
  # Fail-loud by design: a malformed investing config aborts the boot rather
  # than silently degrading risk constraints. All weights are BigDecimal
  # numbers (25 == 25%), never fractions.
  class Config
    class Error < StandardError; end

    ASSET_CLASSES = %w[equity debt reit invit gold cash infra].freeze

    attr_reader :raw, :execution, :mandates

    # @param path [String] YAML file (defaults to config/investing.yml)
    # @param env [String] Rails.env-equivalent section
    def initialize(path: self.class.default_path, env: "test")
      @raw = YAML.safe_load_file(path, aliases: true) || {}
      base = @raw.fetch("default", {})
      section = @raw.fetch(env.to_s) { {} }
      merged = deep_merge(base, section)
      @execution = merged.fetch("execution")
      @mandates = merged.fetch("mandates")
    end

    class << self
      # Load + validate + memoize (called from the initializer).
      def load!(path: nil, env: nil)
        cfg = new(path: path || default_path, env: env || (defined?(Rails) ? Rails.env.to_s : "test"))
        cfg.validate!
        @config = cfg
      end

      # @return [Investing::Config]
      # @raise [Investing::Config::Error] when loaded config is absent
      def fetch
        @config || raise(Error, "Investing::Config not loaded — initializer missing?")
      end

      def reset!
        @config = nil
      end

      def default_path
        defined?(Rails) ? Rails.root.join("config/investing.yml").to_s : "config/investing.yml"
      end
    end

    # ---- convenience accessors -------------------------------------------

    # @return [Hash] the named mandate (validated)
    def mandate(name)
      mandates.fetch(name.to_s) { raise(Error, "unknown investing mandate: #{name}") }
    end

    def sleeves_for(mandate_name)
      mandate(mandate_name).fetch("sleeves")
    end

    def constraints_for(mandate_name)
      mandate(mandate_name).fetch("constraints")
    end

    def rebalancing_for(mandate_name)
      mandate(mandate_name).fetch("rebalancing")
    end

    def equity_band_for(mandate_name)
      band = rebalancing_for(mandate_name).fetch("equity_band_pct")
      [band[0].to_d, band[1].to_d]
    end

    def drift_threshold_for(mandate_name)
      rebalancing_for(mandate_name).fetch("drift_threshold_pct").to_d
    end

    # ---- validation (TDD §5.2) --------------------------------------------

    def validate!
      validate_execution!
      mandates.each { |name, m| validate_mandate!(name, m) }
      self
    end

    private

    def validate_execution!
      mode = execution.fetch("mode")
      unless %w[paper live].include?(mode)
        raise(Error, "execution.mode must be paper|live (got #{mode})")
      end
      if mode == "live" && ENV["INVESTING_LIVE_CONFIRMED"] != "yes"
        raise(Error, "execution.mode=live requires INVESTING_LIVE_CONFIRMED=yes (TDD §19.2)")
      end
      %w[max_order_value_inr max_orders_per_day].each do |key|
        v = execution.fetch(key)
        unless v.to_d.positive?
          raise(Error, "execution.#{key} must be positive (got #{v})")
        end
      end
    end

    def validate_mandate!(name, mandate)
      sleeves = mandate.fetch("sleeves") { raise(Error, "mandate #{name}: sleeves missing") }
      raise(Error, "mandate #{name}: sleeves must be a non-empty list") if sleeves.empty?

      keys = sleeves.map { |s| s.fetch("key") }
      dupes = keys.tally.select { |_k, count| count > 1 }.keys
      raise(Error, "mandate #{name}: duplicate sleeve keys #{dupes}") unless dupes.empty?

      sum = sleeves.sum { |s| s.fetch("target_weight_pct").to_d }
      unless sum == 100
        raise(Error, "mandate #{name}: sleeves must sum to exactly 100 (got #{sum})")
      end

      sleeves.each do |s|
        weight = s.fetch("target_weight_pct").to_d
        unless weight.positive? && weight <= 100
          raise(Error, "mandate #{name}: sleeve #{s['key']} weight must be in (0,100] (got #{weight})")
        end

        asset_class = s.fetch("asset_class")
        unless ASSET_CLASSES.include?(asset_class)
          raise(Error, "mandate #{name}: sleeve #{s['key']} asset_class must be one of #{ASSET_CLASSES}")
        end
      end

      band = mandate.fetch("rebalance_band_pct")
      lo = band[0].to_d
      hi = band[1].to_d
      unless lo < hi && lo >= 0 && hi <= 100
        raise(Error, "mandate #{name}: rebalance_band_pct must be sorted within [0,100]")
      end

      equity_target = sleeves.select { |s| s["asset_class"] == "equity" }.sum { |s| s["target_weight_pct"].to_d }
      unless equity_target.between?(lo, hi)
        raise(Error, "mandate #{name}: equity target #{equity_target} outside band [#{lo}, #{hi}]")
      end

      constraints = mandate.fetch("constraints")
      if constraints["max_single_stock_pct"].to_d > constraints["max_sector_pct"].to_d
        raise(Error, "mandate #{name}: max_single_stock_pct must be <= max_sector_pct")
      end

      deployment = mandate.fetch("deployment")
      unless deployment["equity_tranches"].to_i >= 1
        raise(Error, "mandate #{name}: equity_tranches must be >= 1")
      end
      return if deployment["tranche_spacing_weeks"].to_i >= 1

      raise(Error, "mandate #{name}: tranche_spacing_weeks must be >= 1")
    end

    def deep_merge(base, other)
      base.merge(other) do |_key, base_val, other_val|
        if base_val.is_a?(Hash) && other_val.is_a?(Hash)
          deep_merge(base_val, other_val)
        else
          other_val
        end
      end
    end
  end
end
