# frozen_string_literal: true

module Live
  # Time Regime Service
  # Determines current market session and provides session-specific rules
  # Implements time-conditioned rule system for options buying that respects Greek dominance
  #
  # IMPORTANT: All times are in IST (Indian Standard Time, UTC+5:30)
  # Rails timezone is configured as "Asia/Kolkata" in config/application.rb
  #
  # Market Session Segmentation (Indian Indices - IST):
  # S1: OPEN EXPANSION     → 09:15 – 09:45 IST (Delta + Gamma dominant)
  # S2: TREND CONTINUATION → 09:45 – 11:30 IST (Best zone - Delta stable, Theta low)
  # S3: CHOP / DECAY       → 11:30 – 13:45 IST (Theta dominant - danger zone)
  # S4: CLOSE / GAMMA      → 13:45 – 15:15 IST (Theta + IV crush - tight rules)
  #
  # Each regime gets different SL/TP/trailing rules based on Greek behavior
  class TimeRegimeService
    include Singleton

    # Session types
    OPEN_EXPANSION = :open_expansion
    TREND_CONTINUATION = :trend_continuation
    CHOP_DECAY = :chop_decay
    CLOSE_GAMMA = :close_gamma
    PRE_MARKET = :pre_market
    POST_MARKET = :post_market

    # Global override times (IST)
    # These are parsed in IST timezone via Time.zone.parse
    NO_NEW_TRADES_AFTER = '14:50' # IST
    MARKET_OPEN = '09:15' # IST
    MARKET_CLOSE = '15:15' # IST

    # Returns a human-readable label for the current closed-market session.
    # Display-path degrade: the label may fall back to 'CLOSED', but the
    # failure is logged — never silent.
    def self.closed_session_label
      regime = instance.current_regime
      case regime
      when POST_MARKET then 'POST_MARKET'
      when PRE_MARKET  then 'PRE_MARKET'
      else regime.to_s.upcase
      end
    rescue StandardError => e
      Rails.logger.error("[TimeRegimeService] closed_session_label error: #{e.class} - #{e.message}")
      'CLOSED'
    end

    # Whether regime rules are switched on. SINGLE SOURCE OF TRUTH — the entry
    # guards (Entries::Guards::TimeRegimeGuard) and other consumers delegate
    # here instead of re-reading the config path themselves.
    #
    # Contract (error-handling review wave 4):
    #   * section absent or enabled: false -> false (documented "no regime
    #     rules" state — NOT an error; the operator switched the feature off)
    #   * config document corrupt    -> raises via AlgoConfig.fetch (never
    #     "unknown == off")
    # @return [Boolean]
    def rules_enabled?
      time_regime_config[:enabled] == true
    end

    # Classifies the given IST time into a session regime.
    #
    # Contract (error-handling review wave 4):
    #   * before open / after close -> PRE_MARKET / POST_MARKET
    #   * rules disabled or section absent -> TREND_CONTINUATION (the
    #     documented "no regime rules" profile — same behaviour as before,
    #     but now an explicit contract instead of a rescue fallback)
    #   * rules enabled + malformed window (missing/non-'HH:MM' start or end)
    #     -> Errors::ConfigurationError
    #   * rules enabled + time matches no window (config coverage gap)
    #     -> Errors::ConfigurationError — the old code silently classified
    #       every unmatched moment as TREND_CONTINUATION ("best session",
    #       entries allowed), the most permissive possible guess
    # @return [Symbol]
    # @raise [Errors::ConfigurationError]
    def current_regime(time: nil)
      # Use IST timezone explicitly
      time ||= current_ist_time
      time_str = time.strftime('%H:%M')

      # Compare times in IST
      return PRE_MARKET if time_str < MARKET_OPEN
      return POST_MARKET if time_str >= MARKET_CLOSE

      # Get config directly to avoid recursion (regime_config calls current_regime)
      config = time_regime_config

      return TREND_CONTINUATION unless rules_enabled?

      # Check each regime in order (skip non-Hash entries like 'enabled: true')
      config.each do |regime_name, regime_cfg|
        next unless regime_cfg.is_a?(Hash)

        start_time = regime_cfg[:start]
        end_time = regime_cfg[:end]
        assert_valid_window!(regime_name, start_time, end_time)

        return regime_name.to_sym if time_within_range?(time_str, start_time, end_time)
      end

      raise Errors::ConfigurationError,
            "risk.time_regimes is enabled but no regime window covers #{time_str} IST " \
            "(windows: #{window_summary(config)}) — refusing to guess a regime"
    end

    # Get session-specific configuration
    def regime_config(regime = nil)
      regime ||= current_regime
      config = time_regime_config

      # Return specific regime config or the documented per-regime defaults
      regime_cfg = config[regime.to_s.to_sym]
      return regime_cfg if regime_cfg.is_a?(Hash)

      default_regime_config(regime)
    end

    # Check if entries are allowed in current regime.
    # Absent key = allowed (documented per-regime default); a corrupt config
    # document raises via regime_config/current_regime — never "error ==
    # entries allowed".
    def allow_entries?(regime = nil)
      regime ||= current_regime
      cfg = regime_config(regime)
      cfg[:allow_entries] != false
    end

    # Get SL multiplier for current regime (absent key = documented 1.0 default)
    def sl_multiplier(regime = nil)
      regime ||= current_regime
      cfg = regime_config(regime)
      cfg[:sl_multiplier] || 1.0
    end

    # Get TP multiplier for current regime (absent key = documented 1.0 default)
    def tp_multiplier(regime = nil)
      regime ||= current_regime
      cfg = regime_config(regime)
      cfg[:tp_multiplier] || 1.0
    end

    # Check if trailing is allowed in current regime (absent key = allowed)
    def allow_trailing?(regime = nil)
      regime ||= current_regime
      cfg = regime_config(regime)
      cfg[:allow_trailing] != false
    end

    # Check if runners are allowed in current regime (absent key = allowed)
    def allow_runners?(regime = nil)
      regime ||= current_regime
      cfg = regime_config(regime)
      cfg[:allow_runners] != false
    end

    # Check if new trades are allowed (global override).
    # Corrupt config raises (AlgoConfig.fetch is strict); a transient
    # infrastructure failure propagates to the caller's own boundary —
    # "unknown" must not read as "entries allowed".
    def allow_new_trades?(time: nil)
      # Use IST timezone explicitly
      time ||= current_ist_time
      time_str = time.strftime('%H:%M')

      overrides = AlgoConfig.fetch.dig(:risk, :time_overrides) || {}
      # Absent keys keep the documented operational defaults; present keys
      # must be zero-padded 'HH:MM' — the string comparisons below silently
      # mis-order against unpadded values like '9:15'.
      earliest = hhmm_or_default!(overrides[:earliest_entry_time], :earliest_entry_time, MARKET_OPEN)
      latest = hhmm_or_default!(overrides[:no_new_trades_after], :no_new_trades_after, NO_NEW_TRADES_AFTER)

      return false if time_str < earliest
      return false if time_str >= latest

      # Check regime-specific entry rules
      allow_entries?(current_regime(time: time))
    end

    # Get current time in IST timezone
    # Rails timezone is configured as "Asia/Kolkata" in config/application.rb
    # Time.current and Time.zone.now both return time in configured timezone
    def current_ist_time
      Time.zone.now # Returns time in IST (Asia/Kolkata)
    end

    # Get minimum ADX requirement for current regime (absent key = documented 15.0)
    def min_adx_requirement(regime = nil)
      regime ||= current_regime
      cfg = regime_config(regime)
      cfg[:min_adx] || 15.0
    end

    # Get maximum TP for current regime (in rupees; absent key = no limit)
    def max_tp_rupees(regime = nil)
      regime ||= current_regime
      cfg = regime_config(regime)
      cfg[:max_tp_rupees]
    end

    # Check if this is a high-risk session (chop/decay)
    def high_risk_session?(regime = nil)
      regime ||= current_regime
      regime == CHOP_DECAY
    end

    # Check if this is the best trading session (trend continuation)
    def best_trading_session?(regime = nil)
      regime ||= current_regime
      regime == TREND_CONTINUATION
    end

    private

    # NOTE (error-handling review wave 4): this used to read the TOP-LEVEL
    # :time_regimes key, but config/algo.yml ships the section under risk:.
    # The mismatch made every window lookup silently miss (rescue -> {}) and
    # current_regime permanently degraded to the TREND_CONTINUATION fallback —
    # meaning the chop_decay entry ban, decay-aware position sizing and the
    # S3 edge-failure circuit were all dead config. Reads the real path now,
    # with no rescue: a corrupt document raises instead of masquerading as
    # "feature off".
    def time_regime_config
      AlgoConfig.fetch.dig(:risk, :time_regimes) || {}
    end

    # Zero-padded 'HH:MM' — required for the lexicographic time comparisons
    # used throughout this service ('9:15' sorts AFTER '14:50').
    HHMM_PATTERN = /\A\d{2}:\d{2}\z/.freeze

    def assert_valid_window!(regime_name, start_time, end_time)
      [[:start, start_time], [:end, end_time]].each do |label, value|
        next if value.is_a?(String) && value.match?(HHMM_PATTERN)

        raise Errors::ConfigurationError,
              "risk.time_regimes.#{regime_name}.#{label} must be a zero-padded 'HH:MM' string " \
              "(got #{value.inspect})"
      end
    end

    def hhmm_or_default!(value, key, default)
      return default if value.nil?
      return value if value.is_a?(String) && value.match?(HHMM_PATTERN)

      raise Errors::ConfigurationError,
            "risk.time_overrides.#{key} must be a zero-padded 'HH:MM' string (got #{value.inspect})"
    end

    def window_summary(config)
      config
        .select { |_, cfg| cfg.is_a?(Hash) }
        .map { |name, cfg| "#{name} #{cfg[:start].inspect}-#{cfg[:end].inspect}" }
        .join(', ')
    end

    def time_within_range?(time_str, start_str, end_str)
      # All times are in IST (HH:MM format)
      # For single-day ranges (all our regimes), string comparison works correctly
      # Example: "09:15" < "10:30" < "11:30" is true
      # This avoids timezone/date parsing issues for same-day comparisons

      # Handle wrap-around (e.g., 23:00 to 01:00) - not applicable to our regimes
      if start_str > end_str
        # Wrap-around case: parse as Time objects for proper comparison
        time = parse_time(time_str)
        start_time = parse_time(start_str)
        end_time = parse_time(end_str)
        return false unless time && start_time && end_time

        time >= start_time || time <= end_time
      else
        # Normal case: simple string comparison works for HH:MM format
        time_str.between?(start_str, end_str)
      end
    end

    def parse_time(time_str)
      return nil unless time_str

      parts = time_str.split(':')
      return nil unless parts.size == 2

      hour = parts[0].to_i
      min = parts[1].to_i

      # Parse time in IST timezone (Rails timezone is configured as "Asia/Kolkata")
      # Time.zone.parse interprets the time string in the configured timezone
      Time.zone.parse("#{hour}:#{min}")
    rescue StandardError
      nil
    end

    # Fallback profile for regimes NOT present in the config section — in
    # practice the PRE_MARKET/POST_MARKET symbols and a partially-configured
    # disabled section. When rules are ENABLED, every in-session regime
    # resolves from risk.time_regimes itself (see #current_regime), so these
    # hardcoded profiles never override operator config during market hours.
    def default_regime_config(regime)
      case regime
      when OPEN_EXPANSION
        {
          start: '09:15',
          end: '09:45',
          sl_multiplier: 1.3,
          tp_multiplier: 1.0,
          allow_trailing: false,
          allow_runners: false,
          allow_entries: true,
          min_adx: 20.0,
          max_tp_rupees: 2000
        }
      when TREND_CONTINUATION
        {
          start: '09:45',
          end: '11:30',
          sl_multiplier: 1.0,
          tp_multiplier: 1.0,
          allow_trailing: true,
          allow_runners: true,
          allow_entries: true,
          min_adx: 15.0,
          max_tp_rupees: nil
        }
      when CHOP_DECAY
        {
          start: '11:30',
          end: '13:45',
          sl_multiplier: 0.8,
          tp_multiplier: 0.8,
          allow_trailing: false,
          allow_runners: false,
          allow_entries: false,
          min_adx: 22.0,
          max_tp_rupees: 1500
        }
      when CLOSE_GAMMA
        {
          start: '13:45',
          end: '15:15',
          sl_multiplier: 0.7,
          tp_multiplier: 0.75,
          allow_trailing: false,
          allow_runners: false,
          allow_entries: true,
          min_adx: 18.0,
          max_tp_rupees: 2000
        }
      else
        {
          sl_multiplier: 1.0,
          tp_multiplier: 1.0,
          allow_trailing: true,
          allow_runners: true,
          allow_entries: true,
          min_adx: 15.0
        }
      end
    end
  end
end
