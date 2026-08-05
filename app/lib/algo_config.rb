# frozen_string_literal: true

class AlgoConfig
  CACHE_TTL = 30 # seconds
  PROFILES_DIR = 'config/profiles'
  TIER_PRESETS_SETTING_KEY = 'signal_tier_presets'
  REGISTRY_SETTING_KEY = 'india_index_registry'
  # Credential-bearing sections excluded from the per-position snapshot persisted on trades.
  SENSITIVE_SECTIONS = %i[dhanhq telegram ai].freeze

  # Utility module for deep merging hashes with array handling
  module MergeUtil
    # Deep merge two hashes, handling arrays of hashes by matching on :key
    def self.deep_merge_hashes_with_arrays(base, overrides)
      merged = base.dup

      overrides.each do |key, val|
        if base[key].is_a?(Hash) && val.is_a?(Hash)
          merged[key] = deep_merge_hashes_with_arrays(base[key], val)
        elsif base[key].is_a?(Array) && val.is_a?(Array)
          merged[key] = merge_arrays(base[key], val)
        else
          merged[key] = val
        end
      end

      merged
    end

    # Merge two arrays of hashes by matching on :key or :name attribute
    def self.merge_arrays(base_arr, override_arr)
      return override_arr unless base_arr.is_a?(Array) && override_arr.is_a?(Array)
      return override_arr unless override_arr.all? { |item| item.is_a?(Hash) && (item[:key] || item[:name]) }

      merged = base_arr.dup
      override_arr.each do |override_item|
        match_key = override_item[:key] || override_item[:name]

        base_idx = merged.find_index do |item|
          item.is_a?(Hash) && (item[:key] || item[:name]) == match_key
        end
        if base_idx
          merged[base_idx] = deep_merge_hashes_with_arrays(merged[base_idx], override_item)
        else
          merged << override_item
        end
      end
      merged
    end
  end

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

      # 4. Merge the DB-canonical document (seeded from algo.yml + legacy overrides,
      #    patched via /api/settings/bulk, calibration runs, profitability slices).
      base_config = deep_merge_hashes_with_arrays(base_config, DocumentStore.current_mutable_document)

      @cached_config = base_config
      @cache_expires_at = Time.current + CACHE_TTL
      @cached_config
    end

    def mode
      if ENV.key?('LIVE_TRADING')
        ENV['LIVE_TRADING'].to_s == 'true' ? :live : :paper
      else
        paper_trading_enabled? ? :paper : :live
      end
    end

    def run_mode
      base = (ENV['RUN_MODE'].presence || fetch[:run_mode] || 'production').to_s.strip
      base.presence || 'production'
    end

    # Identity of the effective config at this moment — stamped on signals/positions so a
    # trade can be tied back to the exact gates/params that were active when it was taken.
    def version
      {
        hash: Digest::SHA256.hexdigest(fetch.to_json)[0, 16],
        change_log_id: latest_change_log_id
      }
    end

    # Effective config minus credential sections — pinned on a position at entry so its
    # exit/trailing math stays fixed for the life of the trade (see Positions::ExitConfigResolver).
    def position_snapshot
      fetch.except(*SENSITIVE_SECTIONS)
    end

    def paper_trading_enabled?
      fetch.dig(:paper_trading, :enabled) != false
    end

    # Tick-triggered AI (+Smc::TickAi::AnalysisService+) or explicit event-driven mode.
    # DB JSON overrides may store booleans as strings — treat "true" like true.
    def event_driven_intraday_ai?
      s = fetch[:signals] || {}
      truthy_signal_flag?(s[:tick_ai_analysis_enabled]) ||
        truthy_signal_flag?(s[:event_driven_ai_alerts])
    rescue StandardError
      false
    end

    # When true during open session, Solid Queue should not run 15m AI/SMC jobs; daemon tick path owns alerts.
    def defer_scheduled_intraday_ai_jobs?
      return false if market_closed_for_scheduling?

      event_driven_intraday_ai?
    rescue StandardError
      false
    end

    def scheduled_ai_technical_analysis_job_deferred?
      return false if ENV['SCHEDULED_AI_TECHNICAL_ANALYSIS'] == 'true'

      defer_scheduled_intraday_ai_jobs?
    end

    def scheduled_smc_scanner_job_deferred?
      return false if ENV['SCHEDULED_SMC_SCANNER'] == 'true'

      defer_scheduled_intraday_ai_jobs?
    end

    # Suppress +BiasEngine#notify+ (SendSmcAlertJob) from periodic daemon scans when event-driven.
    def suppress_smc_bias_notify_for_event_driven_ai?
      defer_scheduled_intraday_ai_jobs?
    end

    def market_closed_for_scheduling?
      TradingSession::Service.market_closed?
    rescue StandardError
      false
    end

    def reset!
      @cached_config = nil
      @cache_expires_at = nil
    end

    private

    def latest_change_log_id
      AlgoConfigChangeLog.maximum(:id)
    rescue StandardError
      nil
    end

    def truthy_signal_flag?(val)
      val == true || val.to_s.strip.casecmp('true').zero?
    end

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

      merged = MergeUtil.deep_merge_hashes_with_arrays(config, profile)
      merged[:run_mode] = mode
      merged
    end

    def deep_merge_hashes_with_arrays(base, overrides)
      MergeUtil.deep_merge_hashes_with_arrays(base, overrides)
    end

    def merge_arrays(base_arr, override_arr)
      MergeUtil.merge_arrays(base_arr, override_arr)
    end
  end
end
