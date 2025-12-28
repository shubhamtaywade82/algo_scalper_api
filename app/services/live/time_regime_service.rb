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

    def current_regime(time: nil)
      # Use IST timezone explicitly
      time ||= current_ist_time
      time_str = time.strftime('%H:%M')

      # Compare times in IST
      return PRE_MARKET if time_str < MARKET_OPEN
      return POST_MARKET if time_str >= MARKET_CLOSE

      # Get config directly to avoid recursion (regime_config calls current_regime)
      config = time_regime_config

      # Check each regime in order
      config.each do |regime_name, regime_cfg|
        start_time = regime_cfg[:start]
        end_time = regime_cfg[:end]

        if time_within_range?(time_str, start_time, end_time)
          return regime_name.to_sym
        end
      end

      # Fallback to trend continuation if no match
      TREND_CONTINUATION
    rescue StandardError => e
      Rails.logger.error("[TimeRegimeService] current_regime error: #{e.class} - #{e.message}")
      TREND_CONTINUATION
    end

    # Get session-specific configuration
    def regime_config(regime = nil)
      regime ||= current_regime
      config = time_regime_config

      # Return specific regime config or default
      regime_key = regime.to_s
      regime_cfg = config[regime_key] || config[regime_key.to_sym]

      return regime_cfg if regime_cfg

      # Return defaults if regime not found
      default_regime_config(regime)
    end

    # Check if entries are allowed in current regime
    def allow_entries?(regime = nil)
      regime ||= current_regime
      cfg = regime_config(regime)
      cfg[:allow_entries] != false
    rescue StandardError
      true # Default to allowing entries
    end

    # Get SL multiplier for current regime
    def sl_multiplier(regime = nil)
      regime ||= current_regime
      cfg = regime_config(regime)
      cfg[:sl_multiplier] || 1.0
    rescue StandardError
      1.0
    end

    # Get TP multiplier for current regime
    def tp_multiplier(regime = nil)
      regime ||= current_regime
      cfg = regime_config(regime)
      cfg[:tp_multiplier] || 1.0
    rescue StandardError
      1.0
    end

    # Check if trailing is allowed in current regime
    def allow_trailing?(regime = nil)
      regime ||= current_regime
      cfg = regime_config(regime)
      cfg[:allow_trailing] != false
    rescue StandardError
      true
    end

    # Check if runners are allowed in current regime
    def allow_runners?(regime = nil)
      regime ||= current_regime
      cfg = regime_config(regime)
      cfg[:allow_runners] != false
    rescue StandardError
      true
    end

    # Check if new trades are allowed (global override)
    def allow_new_trades?(time: nil)
      # Use IST timezone explicitly
      time ||= current_ist_time
      time_str = time.strftime('%H:%M')

      # No new trades after 14:50 IST (unless exceptional conditions)
      return false if time_str >= NO_NEW_TRADES_AFTER

      # Check regime-specific entry rules
      allow_entries?
    rescue StandardError
      true
    end

    # Get current time in IST timezone
    # Rails timezone is configured as "Asia/Kolkata" in config/application.rb
    # Time.current and Time.zone.now both return time in configured timezone
    def current_ist_time
      Time.zone.now # Returns time in IST (Asia/Kolkata)
    end

    # Get minimum ADX requirement for current regime
    def min_adx_requirement(regime = nil)
      regime ||= current_regime
      cfg = regime_config(regime)
      cfg[:min_adx] || 15.0
    rescue StandardError
      15.0
    end

    # Get maximum TP for current regime (in rupees)
    def max_tp_rupees(regime = nil)
      regime ||= current_regime
      cfg = regime_config(regime)
      cfg[:max_tp_rupees]
    rescue StandardError
      nil # No limit
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

    def time_regime_config
      AlgoConfig.fetch[:time_regimes] || {}
    rescue StandardError
      {}
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
        time_str >= start_str && time_str <= end_str
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
