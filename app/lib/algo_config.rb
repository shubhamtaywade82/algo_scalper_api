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

    def reset!
      @cached_config = nil
      @cache_expires_at = nil
      IndiaIndexRegistry.reset!
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
