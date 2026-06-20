# frozen_string_literal: true

class AlgoConfig
  CACHE_TTL = 30 # seconds
  ALLOWED_SIGNAL_TIERS = %i[exploratory standard selective].freeze
  SIGNAL_TIER_PRESETS_PATH = 'config/signal_tier_presets.yml'
  TIER_PRESETS_SETTING_KEY = 'signal_tier_presets'
  REGISTRY_SETTING_KEY = 'india_index_registry'
  CREDENTIAL_SECTIONS = %i[dhanhq telegram ai].freeze
  # Credential-bearing sections excluded from the per-position snapshot persisted on trades.
  SENSITIVE_SECTIONS = %i[dhanhq telegram ai].freeze

  class << self
    def fetch
      if @cached_config && @cache_expires_at && Time.current < @cache_expires_at
        return @cached_config
      end

      # 1. Canonical document from DB (seeded from config/algo.yml + legacy overrides on first use)
      base_config = AlgoConfig::DocumentStore.current_mutable_document

      apply_signal_tier_preset!(base_config)
      apply_live_trading_env_override!(base_config)
      apply_paper_research_overrides!(base_config)
      apply_india_index_registry!(base_config)

      @cached_config = base_config
      @cache_expires_at = Time.current + CACHE_TTL
      @cached_config
    end

    def mode
      fetch[:mode]
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

    def reset!
      @cached_config = nil
      @cache_expires_at = nil
      IndiaIndexRegistry.reset!
    end

    # Top-level keys allowed for API settings writes (excludes credential sections).
    def permitted_settings_keys
      yaml_keys = yaml_seed_top_level_keys
      doc_keys = document_top_level_keys
      (yaml_keys | doc_keys).uniq - CREDENTIAL_SECTIONS
    end

    def permitted_settings_structure
      permitted_settings_keys.index_with { {} }
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

    private

    def latest_change_log_id
      AlgoConfigChangeLog.maximum(:id)
    rescue StandardError
      nil
    end

    def truthy_signal_flag?(val)
      val == true || val.to_s.strip.casecmp('true').zero?
    end

    def deep_merge_hashes_with_arrays(base, overrides)
      MergeUtil.deep_merge_hashes_with_arrays(base, overrides)
    end

    def merge_arrays(base_arr, override_arr)
      MergeUtil.merge_arrays(base_arr, override_arr)
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

      merged = deep_merge_hashes_with_arrays(preset, config)
      config.replace(merged)
      Rails.logger.debug { "[AlgoConfig] signal_tier=#{tier}" }
    end

    # Single source of truth: the config document's signals.signal_tier.
    # ENV['SIGNAL_TIER'] is honored only as an explicit emergency override (SIGNAL_TIER_FORCE=true);
    # otherwise a divergent env value is logged and ignored.
    def resolve_signal_tier(config)
      doc_tier = normalize_signal_tier(config.dig(:signals, :signal_tier))
      env_tier = normalize_signal_tier(ENV.fetch('SIGNAL_TIER', nil))
      return env_tier if env_tier && signal_tier_env_forced?

      effective = doc_tier || 'standard'
      warn_ignored_signal_tier_env(env_tier, effective) if env_tier && env_tier != effective
      effective
    end

    def normalize_signal_tier(raw)
      return nil if raw.blank?

      tier = raw.to_s.strip.downcase
      return tier if ALLOWED_SIGNAL_TIERS.include?(tier.to_sym)

      Rails.logger.warn("[AlgoConfig] Invalid signal_tier #{raw.inspect}; ignoring")
      nil
    end

    def signal_tier_env_forced?
      ActiveModel::Type::Boolean.new.cast(ENV.fetch('SIGNAL_TIER_FORCE', 'false'))
    end

    def warn_ignored_signal_tier_env(env_tier, effective)
      Rails.logger.warn(
        "[AlgoConfig] SIGNAL_TIER=#{env_tier} ignored (effective signal_tier=#{effective}); " \
        'set SIGNAL_TIER_FORCE=true to override'
      )
    end

    def load_signal_tier_presets
      db_raw = Setting.fetch(TIER_PRESETS_SETTING_KEY, nil, ttl: CACHE_TTL)
      if db_raw.present?
        parsed = JSON.parse(db_raw, symbolize_names: true)
        return parsed if parsed.is_a?(Hash)
      end

      path = Rails.root.join(SIGNAL_TIER_PRESETS_PATH)
      return {} unless File.exist?(path)

      YAML.load_file(path).deep_symbolize_keys
    rescue StandardError => e
      Rails.logger.error("[AlgoConfig] Failed to load tier presets: #{e.message}")
      {}
    end

    def document_top_level_keys
      raw = Setting.fetch(AlgoConfig::DocumentStore::DOCUMENT_KEY, nil, ttl: CACHE_TTL)
      return [] if raw.blank?

      parsed = JSON.parse(raw, symbolize_names: true)
      parsed.is_a?(Hash) ? parsed.keys : []
    rescue StandardError
      []
    end

    def yaml_seed_top_level_keys
      YAML.load_file(Rails.root.join('config/algo.yml')).keys.map(&:to_sym)
    rescue StandardError
      []
    end

    # LIVE_TRADING env is the single switch for real broker execution (see .env.example).
    # When unset or false: paper_trading.enabled is forced true (simulated fills, GatewayPaper).
    # When true: paper_trading.enabled is forced false (GatewayLive — still subject to dhanhq.enable_orders).
    def apply_live_trading_env_override!(config)
      paper = !live_trading_env_truthy?
      config[:paper_trading] = (config[:paper_trading] || {}).merge(enabled: paper)
    end

    # Paper mode: relax direction gate so ranging/choppy sessions still generate candidates.
    # Opt back into live-like behavior with PAPER_STRICT_DIRECTION_GATE=true.
    def apply_paper_research_overrides!(config)
      return if paper_strict_direction_gate?
      return unless config.dig(:paper_trading, :enabled)

      signals = (config[:signals] || {}).dup
      signals[:enable_direction_gate] = false
      config[:signals] = signals
    end

    def apply_india_index_registry!(config)
      indices = Array(config[:indices])
      return if indices.empty?

      config[:indices] = IndiaIndexRegistry.merge_indices!(indices)
    rescue StandardError => e
      Rails.logger.error("[AlgoConfig] Failed to apply india_index_registry: #{e.class} - #{e.message}")
    end

    def paper_strict_direction_gate?
      ActiveModel::Type::Boolean.new.cast(ENV.fetch('PAPER_STRICT_DIRECTION_GATE', 'false'))
    end

    def live_trading_env_truthy?
      v = ENV.fetch('LIVE_TRADING', nil)
      return false if v.nil?
      return false if v.to_s.strip.empty?

      ActiveModel::Type::Boolean.new.cast(v)
    end
  end
end
