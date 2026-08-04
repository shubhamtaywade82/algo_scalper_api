# frozen_string_literal: true

class AlgoConfig
  CACHE_TTL = 30 # seconds
  PROFILES_DIR = 'config/profiles'

  class << self
    def fetch
      if @cached_config && @cache_expires_at && Time.current < @cache_expires_at
        return @cached_config
      end

      # 1. Load base configuration from YAML
      base_config = YAML.load_file(Rails.root.join('config/algo.yml')).deep_symbolize_keys

      # 2. Merge run-mode profile if present (exit_testing, entry_testing, production)
      base_config = apply_profile(base_config)

      # 3. Load dynamic overrides from the database (Settings table)
      override_json = Setting.fetch('algo_config_overrides', nil, ttl: CACHE_TTL)
      if override_json.present?
        begin
          overrides = JSON.parse(override_json).deep_symbolize_keys
          base_config = deep_merge_hashes_with_arrays(base_config, overrides)
        rescue StandardError => e
          Rails.logger.error("[AlgoConfig] Failed to parse algo_config_overrides: #{e.message}")
        end
      end

      @cached_config = base_config
      @cache_expires_at = Time.current + CACHE_TTL
      @cached_config
    end

    def mode
      fetch[:mode]
    end

    def run_mode
      base = (ENV['RUN_MODE'].presence || fetch[:run_mode] || 'production').to_s.strip
      base.presence || 'production'
    end

    def reset!
      @cached_config = nil
      @cache_expires_at = nil
    end

    private

    def apply_profile(config)
      mode = (ENV['RUN_MODE'].presence || config[:run_mode] || 'production').to_s.strip.presence || 'production'
      path = Rails.root.join(PROFILES_DIR, "#{mode}.yml")
      unless path.file?
        config[:run_mode] = mode
        return config
      end

      profile = YAML.load_file(path)
      profile = profile.deep_symbolize_keys if profile.is_a?(Hash)
      unless profile.is_a?(Hash)
        config[:run_mode] = mode
        return config
      end

      merged = deep_merge_hashes_with_arrays(config, profile)
      merged[:run_mode] = mode
      merged
    end

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

    def deep_merge_hashes_with_arrays(base, overrides)
      MergeUtil.deep_merge_hashes_with_arrays(base, overrides)
    end

    def merge_arrays(base_arr, override_arr)
      MergeUtil.merge_arrays(base_arr, override_arr)
    end
  end
end
