# frozen_string_literal: true

module Trading
  class TrailingEngine
    # Default configs calibrated from 16-week historical ATM options intraday analysis.
    # These are fallbacks — live values are read from algo.yml[:risk][:institutional_trailing].
    DEFAULTS = {
      nifty: {
        early_trigger: 0.05, # +5% → survival SL
        early_sl_offset: -0.12, # SL at -12% from entry
        breakeven_trigger: 0.157, # +15.7% → breakeven (25% of avg max gain 62.88%)
        activation_trigger: 0.20, # +20% → HWM trailing active
        trailing_distance: 0.386 # 38.6% from HWM (80% of avg retrace 48.3%)
      }.freeze,
      sensex: {
        early_trigger: 0.06, # +6% → survival SL
        early_sl_offset: -0.10, # SL at -10% from entry
        breakeven_trigger: 0.12, # +12% → breakeven
        activation_trigger: 0.18, # +18% → HWM trailing active
        trailing_distance: 0.413 # 41.3% from HWM (80% of avg retrace 51.65%)
      }.freeze,
      banknifty: {
        early_trigger: 0.06, # +6% → survival SL
        early_sl_offset: -0.15, # SL at -15% (wider — BN is volatile)
        breakeven_trigger: 0.18, # +18% → breakeven
        activation_trigger: 0.25, # +25% → HWM trailing active
        trailing_distance: 0.35 # 35% from HWM
      }.freeze
    }.freeze

    def initialize(tracker:, ltp:)
      @tracker  = tracker
      @symbol   = tracker.symbol.to_s.upcase
      @entry    = tracker.entry_price.to_f
      @quantity = tracker.quantity.to_i.abs
      @ltp      = ltp.to_f
      @highest  = [tracker.highest_price.to_f, @entry].max
    end

    def call
      update_hwm

      config     = config_for_symbol
      profit_pct = (@ltp - @entry) / @entry

      maybe_log_smc_exit_advisory

      # PHASE 3: High Watermark Trailing (Most aggressive locking)
      return trailing_stop(config) if profit_pct >= config[:activation_trigger]

      # PHASE 2: Breakeven (Capital protection)
      return breakeven if profit_pct >= config[:breakeven_trigger]

      # PHASE 1: Survival (Avoid early stop-out)
      return early_stop(config) if profit_pct >= config[:early_trigger]

      nil # No trailing SL yet
    end

    private

    def update_hwm
      if @ltp > @highest
        @highest = @ltp
        @tracker.update_columns(meta: @tracker.meta.merge('highest_price' => @highest)) # rubocop:disable Rails/SkipsModelValidations
      end
    end

    def maybe_log_smc_exit_advisory
      instrument = @tracker.instrument
      return unless instrument

      Smc::Navigator.log_exit_advisory(tracker: @tracker, ltp: @ltp, instrument: instrument)
    rescue StandardError => e
      Rails.logger.error("[Trading::TrailingEngine] #{e.class} - #{e.message}")
    end

    # Resolve config: algo.yml > hardcoded DEFAULTS
    def config_for_symbol
      yml = begin
        AlgoConfig.fetch.dig(:risk, :institutional_trailing)
      rescue StandardError
        nil
      end

      key = symbol_key
      raw = yml&.[](key) || DEFAULTS[key]
      raw = raw.transform_keys(&:to_sym)
      merge_strategy_profile_override!(raw)
    end

    def merge_strategy_profile_override!(base)
      raw = @tracker.meta&.dig('strategy_profile') || @tracker.meta&.dig(:strategy_profile)
      profile = raw&.to_sym
      return base unless profile

      overrides = AlgoConfig.fetch.dig(:risk, :institutional_trailing, :profiles, profile)
      return base unless overrides.is_a?(Hash)

      base.merge!(overrides.symbolize_keys)
    rescue StandardError
      base
    end

    def symbol_key
      return :banknifty if @symbol.include?('BANKNIFTY')
      return :sensex if @symbol.include?('SENSEX')

      :nifty
    end

    # ── Phase 1: Survival ─────────────────────────────────────────────────────

    def early_stop(config)
      @entry * (1 + config[:early_sl_offset])
    end

    # ── Phase 2: Breakeven ────────────────────────────────────────────────────

    def breakeven
      @entry
    end

    # ── Phase 3: HWM Trailing ─────────────────────────────────────────────────
    # Trail distance is adjusted by session and expiry-day factors.

    def trailing_stop(config)
      base_distance = config[:trailing_distance]
      adjusted      = base_distance * session_factor * expiry_day_factor

      @highest * (1 - adjusted)
    end

    # Session-aware tightening: afternoon trails are tighter because
    # historical data shows options hit extreme peaks AND crash in the same session.
    # Morning 09:15-11:00: let the move breathe (1.0x)
    # Midday  11:01-13:00: slightly tighter (0.90x)
    # Afternoon 13:01+:    tighten — crash/decay risk (0.75x)
    def session_factor
      return 1.0 unless session_aware?

      mins = Time.current.in_time_zone('Asia/Kolkata').then { |t| (t.hour * 60) + t.min }
      case mins
      when ((9 * 60) + 15)..(11 * 60) then 1.0
      when ((11 * 60) + 1)..(13 * 60) then 0.90
      else 0.75
      end
    end

    # Expiry-day (Thursday) auto-tightening: historical data shows -99.96% max losses
    # on Thursday afternoons. Trail at a fraction of normal distance.
    def expiry_day_factor
      return 1.0 unless expiry_day_tightening_enabled?

      today = Time.current.in_time_zone('Asia/Kolkata').to_date
      return expiry_tightening_ratio if today.wday == 4 # Thursday

      1.0
    end

    def session_aware?
      AlgoConfig.fetch.dig(:risk, :institutional_trailing, :session_aware) == true
    rescue StandardError
      false
    end

    def expiry_day_tightening_enabled?
      AlgoConfig.fetch.dig(:risk, :institutional_trailing, :expiry_day_tightening).present?
    rescue StandardError
      false
    end

    def expiry_tightening_ratio
      AlgoConfig.fetch.dig(:risk, :institutional_trailing, :expiry_day_tightening).to_f
    rescue StandardError
      0.60
    end
  end
end
