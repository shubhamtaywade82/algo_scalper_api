# frozen_string_literal: true

class AlgoConfig
  CACHE_TTL = 30 # seconds
  ALLOWED_SIGNAL_TIERS = %i[exploratory standard selective].freeze
  SIGNAL_TIER_PRESETS_PATH = 'config/signal_tier_presets.yml'

  class << self
    def fetch
      if @cached_config && @cache_expires_at && Time.current < @cache_expires_at
        return @cached_config
      end

      # 1. Load base configuration from YAML
      base_config = YAML.load_file(Rails.root.join('config/algo.yml')).deep_symbolize_keys

      # 2. Load dynamic overrides from the database (Settings table)
      override_json = Setting.fetch('algo_config_overrides', nil, ttl: CACHE_TTL)
      if override_json.present?
        begin
          overrides = JSON.parse(override_json).deep_symbolize_keys
          base_config = deep_merge_hashes_with_arrays(base_config, overrides)
        rescue StandardError => e
          Rails.logger.error("[AlgoConfig] Failed to parse algo_config_overrides: #{e.message}")
        end
      end

      apply_signal_tier_preset!(base_config)
      apply_live_trading_env_override!(base_config)

      @cached_config = base_config
      @cache_expires_at = Time.current + CACHE_TTL
      @cached_config
    end

    def mode
      fetch[:mode]
    end

    def reset!
      @cached_config = nil
      @cache_expires_at = nil
    end

    private

    # Custom deep merge to handle arrays of hashes (like the indices array where we match by :key)
    def deep_merge_hashes_with_arrays(base, overrides)
      merged = base.dup

      overrides.each do |key, val|
        if base[key].is_a?(Hash) && val.is_a?(Hash)
          merged[key] = deep_merge_hashes_with_arrays(base[key], val)
        elsif base[key].is_a?(Array) && val.is_a?(Array)
          # Try to merge array of hashes by a common identifier, primarily :key
          merged[key] = merge_arrays(base[key], val)
        else
          merged[key] = val
        end
      end

      merged
    end

    def merge_arrays(base_arr, override_arr)
      # If they aren't arrays of hashes with :key, just overwrite
      return override_arr unless base_arr.all? { |i| i.is_a?(Hash) && i[:key] } && override_arr.all? { |i| i.is_a?(Hash) && i[:key] }

      merged_arr = base_arr.map(&:dup)

      override_arr.each do |over_item|
        existing_idx = merged_arr.index { |b_item| b_item[:key] == over_item[:key] }
        if existing_idx
          merged_arr[existing_idx] = deep_merge_hashes_with_arrays(merged_arr[existing_idx], over_item)
        else
          merged_arr << over_item
        end
      end

      merged_arr
    end

    # Merges config/signal_tier_presets.yml overlay for exploratory | standard | selective.
    # Tier resolution: ENV['SIGNAL_TIER'] (if valid) else signals.signal_tier else standard.
    def apply_signal_tier_preset!(config)
      tier = resolve_signal_tier(config)
      preset = load_signal_tier_presets[tier.to_sym]
      if preset.nil?
        Rails.logger.warn("[AlgoConfig] Missing preset for signal_tier #{tier} in #{SIGNAL_TIER_PRESETS_PATH}")
        return
      end

      return if preset.blank?

      merged = deep_merge_hashes_with_arrays(config, preset)
      config.replace(merged)
      Rails.logger.debug { "[AlgoConfig] signal_tier=#{tier}" }
    end

    def resolve_signal_tier(config)
      env_raw = ENV.fetch('SIGNAL_TIER', nil)
      env_tier = env_raw.to_s.strip.downcase
      if env_raw.present?
        return env_tier if ALLOWED_SIGNAL_TIERS.include?(env_tier.to_sym)

        Rails.logger.warn("[AlgoConfig] Invalid SIGNAL_TIER=#{env_raw.inspect}; using config or standard")
      end

      cfg_raw = config.dig(:signals, :signal_tier)
      cfg_tier = cfg_raw.to_s.strip.downcase
      return cfg_tier if cfg_raw.present? && ALLOWED_SIGNAL_TIERS.include?(cfg_tier.to_sym)

      Rails.logger.warn("[AlgoConfig] Invalid signals.signal_tier=#{cfg_raw.inspect}; using standard") if cfg_raw.present?

      'standard'
    end

    def load_signal_tier_presets
      path = Rails.root.join(SIGNAL_TIER_PRESETS_PATH)
      return {} unless File.exist?(path)

      YAML.load_file(path).deep_symbolize_keys
    rescue StandardError => e
      Rails.logger.error("[AlgoConfig] Failed to load #{SIGNAL_TIER_PRESETS_PATH}: #{e.message}")
      {}
    end

    # LIVE_TRADING env is the single switch for real broker execution (see .env.example).
    # When unset or false: paper_trading.enabled is forced true (simulated fills, GatewayPaper).
    # When true: paper_trading.enabled is forced false (GatewayLive — still subject to dhanhq.enable_orders).
    def apply_live_trading_env_override!(config)
      paper = !live_trading_env_truthy?
      config[:paper_trading] = (config[:paper_trading] || {}).merge(enabled: paper)
    end

    def live_trading_env_truthy?
      v = ENV.fetch('LIVE_TRADING', nil)
      return false if v.nil?
      return false if v.to_s.strip.empty?

      ActiveModel::Type::Boolean.new.cast(v)
    end
  end
end
