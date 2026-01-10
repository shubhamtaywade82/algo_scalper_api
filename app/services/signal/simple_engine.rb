# frozen_string_literal: true

# Simplified Signal Engine - KISS Principle
# Single clear path: Get signal → Validate → Select strikes → Enter
module Signal
  class SimpleEngine
    class << self
      def run_for(index_cfg)
        Rails.logger.info("[ENTRY] Starting analysis for #{index_cfg[:key]}")

        # 1. Get signal (single strategy)
        signal_result = get_signal(index_cfg)
        return unless signal_result[:signal] && signal_result[:signal] != :avoid

        signal = signal_result[:signal]
        strategy = signal_result[:strategy]
        timeframe = signal_result[:timeframe]

        Rails.logger.info("[ENTRY] #{index_cfg[:key]} | Strategy: #{strategy} | Timeframe: #{timeframe} | Signal: #{signal}")

        # 2. Validate signal (simple checks)
        validation = validate_signal(index_cfg, signal_result)
        unless validation[:valid]
          Rails.logger.warn("[ENTRY] #{index_cfg[:key]} | Validation failed: #{validation[:reason]}")
          return
        end

        # 3. Select strikes
        picks = Options::ChainAnalyzer.pick_strikes(index_cfg: index_cfg, direction: signal)
        if picks.empty?
          Rails.logger.warn("[ENTRY] #{index_cfg[:key]} | No suitable strikes found")
          return
        end

        Rails.logger.info("[ENTRY] #{index_cfg[:key]} | Found #{picks.size} strikes: #{picks.pluck(:symbol).join(', ')}")

        # 4. Enter positions
        picks.each do |pick|
          result = Entries::EntryGuard.try_enter(
            index_cfg: index_cfg,
            pick: pick,
            direction: signal,
            scale_multiplier: 1,
            permission: :scale_ready
          )

          if result
            Rails.logger.info("[ENTRY] #{index_cfg[:key]} | Entry successful: #{pick[:symbol]}")
          else
            Rails.logger.debug("[ENTRY] #{index_cfg[:key]} | Entry failed: #{pick[:symbol]}")
          end
        end

        # Track entry path for analysis
        track_entry_path(index_cfg, strategy, timeframe, signal, picks.size)
      rescue StandardError => e
        Rails.logger.error("[ENTRY] #{index_cfg[:key]} | Error: #{e.class} - #{e.message}")
      end

      private

      # Get signal using configured strategy
      def get_signal(index_cfg)
        config = entry_config
        strategy = config[:strategy] || 'supertrend_adx'
        timeframe = config[:timeframe] || '5m'

        case strategy
        when 'supertrend_adx'
          get_supertrend_adx_signal(index_cfg, timeframe)
        when 'simple_momentum'
          get_simple_momentum_signal(index_cfg, timeframe)
        when 'inside_bar'
          get_inside_bar_signal(index_cfg, timeframe)
        else
          Rails.logger.warn("[ENTRY] Unknown strategy: #{strategy}, falling back to supertrend_adx")
          get_supertrend_adx_signal(index_cfg, timeframe)
        end
      end

      def get_supertrend_adx_signal(index_cfg, timeframe)
        instrument = IndexInstrumentCache.instance.get_or_fetch(index_cfg)
        return { signal: :avoid, strategy: 'supertrend_adx', timeframe: timeframe } unless instrument

        signals_cfg = AlgoConfig.fetch[:signals] || {}
        supertrend_cfg = signals_cfg[:supertrend] || {}
        adx_cfg = signals_cfg[:adx] || {}
        adx_min = signals_cfg.fetch(:enable_adx_filter, true) ? adx_cfg[:min_strength].to_f : 0

        interval = normalize_interval(timeframe)
        return { signal: :avoid, strategy: 'supertrend_adx', timeframe: timeframe } unless interval

        series = instrument.candle_series(interval: interval)
        return { signal: :avoid, strategy: 'supertrend_adx', timeframe: timeframe } unless series&.candles&.any?

        st_service = Indicators::Supertrend.new(series: series, **supertrend_cfg)
        st = st_service.call
        adx_value = instrument.adx(14, interval: interval)

        direction = decide_direction(st, adx_value, min_strength: adx_min, timeframe_label: timeframe)

        {
          signal: direction,
          strategy: 'supertrend_adx',
          timeframe: timeframe,
          supertrend: st,
          adx: adx_value
        }
      end

      def get_simple_momentum_signal(index_cfg, timeframe)
        # Placeholder - implement if needed
        { signal: :avoid, strategy: 'simple_momentum', timeframe: timeframe }
      end

      def get_inside_bar_signal(index_cfg, timeframe)
        # Placeholder - implement if needed
        { signal: :avoid, strategy: 'inside_bar', timeframe: timeframe }
      end

      # Simple validation (single mode)
      def validate_signal(index_cfg, signal_result)
        config = entry_config
        validation_mode = config[:validation] || 'balanced'

        checks = []

        # Market timing (always check)
        unless Market::Calendar.trading_day_today?
          return { valid: false, reason: 'Not a trading day' }
        end

        # IV Rank check (if enabled)
        if validation_mode != 'aggressive'
          # Add IV rank check here if needed
        end

        # ADX check (if enabled)
        if signal_result[:adx] && config[:adx_min]
          if signal_result[:adx][:value].to_f < config[:adx_min].to_f
            return { valid: false, reason: "ADX too weak: #{signal_result[:adx][:value]}" }
          end
        end

        { valid: true, reason: 'All checks passed' }
      end

      def decide_direction(supertrend_result, adx_value, min_strength:, timeframe_label:)
        return :avoid if min_strength.positive? && adx_value.to_f < min_strength
        return :avoid unless supertrend_result&.dig(:trend)

        case supertrend_result[:trend]
        when :bullish then :bullish
        when :bearish then :bearish
        else :avoid
        end
      end

      def normalize_interval(timeframe)
        cleaned = timeframe.to_s.strip.downcase
        digits = cleaned.gsub(/[^0-9]/, '')
        digits.presence
      end

      def entry_config
        @entry_config ||= begin
          AlgoConfig.fetch[:entry] || {
            strategy: 'supertrend_adx',
            timeframe: '5m',
            validation: 'balanced',
            adx_min: 18
          }
        rescue StandardError
          {
            strategy: 'supertrend_adx',
            timeframe: '5m',
            validation: 'balanced',
            adx_min: 18
          }
        end
      end

      def track_entry_path(index_cfg, strategy, timeframe, signal, picks_count)
        TradingSignal.create(
          index_key: index_cfg[:key],
          direction: signal.to_s,
          timeframe: timeframe,
          confidence_score: 0.5,
          metadata: {
            strategy: strategy,
            entry_path: "#{strategy}_#{timeframe}",
            picks_count: picks_count
          }
        )
      rescue StandardError => e
        Rails.logger.error("[ENTRY] Failed to track entry path: #{e.message}")
      end
    end
  end
end
