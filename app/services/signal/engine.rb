# frozen_string_literal: true

module Signal
  # Stock Supertrend options-buying pipeline: 1m flip → chop gate → ATM strike → EntryGuard.
  class Engine
    class << self
      def run_for(index_cfg, regime_state: nil)
        summary = CycleSummary.new(index_key: index_cfg[:key])
        Thread.current[:signal_cycle_summary] = summary

        unless tradable_session?(index_cfg)
          summary.skip!('market_closed')
          return summary
        end

        instrument = fetch_instrument(index_cfg)
        unless instrument
          summary.block!('missing_instrument')
          return summary
        end

        signals_cfg = AlgoConfig.fetch[:signals] || {}
        context = initialize_analysis_context(signals_cfg)
        primary_tf = context[:primary_tf]

        result = execute_supertrend_only_flow(index_cfg, instrument, signals_cfg, primary_tf)
        return summary.finalize_pending! unless result

        final_direction = result[:direction]
        primary_analysis = result[:primary_analysis]
        primary_series = result[:primary_series]
        regime = result[:regime]
        validation_result = result[:validation_result]
        effective_validation_mode = result[:effective_validation_mode]
        effective_timeframe = primary_tf
        quality_result = stock_quality_result
        permission = :scale_ready
        smc_decision = final_direction == :bullish ? :call : :put

        nearest_expiry = resolve_nearest_expiry_date(index_cfg: index_cfg)
        if entry_dte_guard_blocks?(index_cfg: index_cfg, signals_cfg: signals_cfg, nearest_expiry: nearest_expiry)
          Signal::StateTracker.reset(index_cfg[:key])
          record_cycle_block!('entry_dte_guard', regime: regime, direction: final_direction)
          return summary
        end

        state_snapshot = Signal::StateTracker.record(
          index_key: index_cfg[:key],
          direction: final_direction,
          candle_timestamp: primary_analysis[:last_candle_timestamp],
          config: signals_cfg
        )

        options_analysis = execute_options_analysis(
          index_cfg,
          expiry_date: nearest_expiry,
          expiry_blocked: expiry_trade_allowed?(index_cfg[:key]) == false
        )

        diagnostic_metadata = build_diagnostic_metadata(
          index_cfg: index_cfg,
          final_direction: final_direction,
          primary_analysis: primary_analysis,
          regime: regime,
          options_analysis: options_analysis,
          validation_result: validation_result,
          state_snapshot: state_snapshot,
          effective_validation_mode: effective_validation_mode,
          signals_cfg: signals_cfg,
          primary_tf: primary_tf,
          effective_timeframe: effective_timeframe,
          smc_decision: smc_decision,
          permission: permission
        )

        signal = TradingSignal.create_from_analysis(
          index_key: index_cfg[:key],
          direction: final_direction.to_s,
          timeframe: effective_timeframe,
          supertrend_value: primary_analysis[:supertrend][:last_value],
          adx_value: primary_analysis[:adx_value],
          candle_timestamp: primary_analysis[:last_candle_timestamp],
          confidence_score: calculate_confidence_score(
            primary_analysis: primary_analysis,
            validation_result: validation_result,
            index_cfg: index_cfg
          ),
          metadata: diagnostic_metadata
        )

        gate_result = execute_stock_entry_gate(
          index_cfg: index_cfg,
          signal: signal,
          final_direction: final_direction,
          options_analysis: options_analysis,
          permission: permission
        )
        unless gate_result
          record_cycle_block!('entry_gate', regime: regime, direction: final_direction)
          return summary
        end

        entered = trigger_entry_flow(
          index_cfg: index_cfg,
          signal: signal,
          picks: gate_result[:picks],
          final_direction: final_direction,
          primary_series: primary_series,
          primary_tf: primary_tf,
          diagnostic_metadata: diagnostic_metadata,
          quality_result: quality_result,
          execution_permission: permission
        )
        if entered
          summary.entered!(direction: final_direction, regime: regime)
        else
          record_cycle_block!('entry_guard', regime: regime, direction: final_direction)
        end
        summary
      rescue StandardError => e
        Rails.logger.fatal("[FATAL_SIGNAL_ERROR] #{e.class}: #{e.message}\n#{e.backtrace.first(10).join(%(\n))}")
        Rails.logger.error("[Signal] #{index_cfg[:key]} #{e.class} #{e.message}")
        summary&.block!('error')
        summary
      ensure
        Thread.current[:signal_cycle_summary] = nil
      end

      private

      def record_cycle_block!(code, regime: nil, direction: nil)
        Thread.current[:signal_cycle_summary]&.block!(code, regime: regime, direction: direction)
      end

      def tradable_session?(index_cfg)
        if TradingSession::Service.market_closed?
          Rails.logger.debug { "[Signal] Market closed - skipping analysis for #{index_cfg[:key]}" }
          return false
        end

        Rails.logger.info(
          "\n\n[Signal] ----------------------------------------------------- " \
          "Starting analysis for #{index_cfg[:key]} (IDX_I) " \
          '--------------------------------------------------------'
        )
        true
      end

      def fetch_instrument(index_cfg)
        instrument = IndexInstrumentCache.instance.get_or_fetch(index_cfg)
        Rails.logger.error("[Signal] Could not find instrument for #{index_cfg[:key]}") unless instrument
        instrument
      end

      def initialize_analysis_context(signals_cfg)
        primary_tf = (signals_cfg[:primary_timeframe] || signals_cfg[:timeframe] || '1m').to_s
        { primary_tf: primary_tf }
      end

      def execute_supertrend_only_flow(index_cfg, instrument, signals_cfg, primary_tf)
        supertrend_cfg = signals_cfg[:supertrend]
        unless supertrend_cfg
          Rails.logger.error("[Signal] Supertrend configuration missing for #{index_cfg[:key]}")
          record_cycle_block!('supertrend_config_missing')
          return
        end

        primary_analysis = analyze_timeframe(
          index_cfg: index_cfg,
          instrument: instrument,
          timeframe: primary_tf,
          supertrend_cfg: supertrend_cfg,
          adx_min_strength: 0
        )
        unless primary_analysis[:status] == :ok
          Rails.logger.warn(
            "[Signal] Primary timeframe analysis unavailable for #{index_cfg[:key]}: #{primary_analysis[:message]}"
          )
          Signal::StateTracker.reset(index_cfg[:key])
          record_cycle_block!('analysis_unavailable')
          return
        end

        trend_direction = SupertrendTrend.direction(
          series: primary_analysis[:series],
          supertrend_result: primary_analysis[:supertrend]
        )
        if trend_direction == :none
          Rails.logger.info("[Signal] SupertrendTrend :none — no trade for #{index_cfg[:key]}")
          Signal::StateTracker.reset(index_cfg[:key])
          record_cycle_block!('supertrend_none')
          return
        end

        final_direction = trend_direction == :long ? :bullish : :bearish

        {
          direction: final_direction,
          primary_analysis: primary_analysis,
          primary_series: primary_analysis[:series],
          regime: :trending,
          validation_result: { valid: true },
          effective_validation_mode: 'stock'
        }
      end

      def stock_quality_result
        { pass: true, score: 100, breakdown: { stock_mode: true } }
      end

      def analyze_timeframe(index_cfg:, instrument:, timeframe:, supertrend_cfg:, adx_min_strength:)
        interval = normalize_interval(timeframe)
        if interval.blank?
          message = "Invalid timeframe '#{timeframe}'"
          Rails.logger.error("[Signal] #{message} for #{index_cfg[:key]}")
          return { status: :error, message: message }
        end

        series = instrument.candle_series(interval: interval)
        unless series&.candles&.any?
          message = "No candle data (#{timeframe})"
          Rails.logger.warn("[Signal] #{message} for #{index_cfg[:key]}")
          return { status: :no_data, message: message }
        end

        signals_cfg = AlgoConfig.fetch[:signals] || {}
        supertrend_cfg = resolved_supertrend_cfg(instrument, interval, signals_cfg)
        st = Indicators::Supertrend.new(series: series, **supertrend_cfg).call

        adx_min = resolved_adx_min(instrument, interval, index_cfg, timeframe)
        adx_value = instrument.adx(14, interval: interval)
        direction = decide_direction(
          st,
          adx_value,
          min_strength: adx_min_strength.positive? ? adx_min_strength : adx_min,
          timeframe_label: timeframe
        )

        {
          status: :ok,
          series: series,
          supertrend: st,
          adx_value: adx_value,
          direction: direction,
          last_candle_timestamp: series.candles.last&.timestamp
        }
      rescue StandardError => e
        Rails.logger.error(
          "[Signal] Timeframe analysis failed for #{index_cfg[:key]} @ #{timeframe}: #{e.class} - #{e.message}"
        )
        { status: :error, message: e.message }
      end

      def normalize_interval(timeframe)
        return if timeframe.blank?

        cleaned = timeframe.to_s.strip.downcase
        digits = cleaned.gsub(/[^0-9]/, '')
        digits.presence
      end

      def decide_direction(supertrend_result, adx_value, min_strength:, timeframe_label:)
        min_required = min_strength.to_f
        adx_numeric = adx_value.to_f

        if min_required.positive? && adx_numeric < min_required
          return :avoid
        end

        if supertrend_result.blank? || supertrend_result[:trend].nil?
          Rails.logger.warn("[Signal] Supertrend result invalid on #{timeframe_label}: #{supertrend_result}")
          return :avoid
        end

        case supertrend_result[:trend]
        when :bullish then :bullish
        when :bearish then :bearish
        else :avoid
        end
      end

      def macd_confidence_factor(direction, series)
        result = Indicators::MacdIndicator.new(series: series).calculate_at(-1)
        return 0.0 if result.nil?

        histogram = result.dig(:value, :histogram).to_f
        return 0.10 if direction == :bullish && histogram.positive?
        return 0.10 if direction == :bearish && histogram.negative?

        0.0
      rescue StandardError => e
        Rails.logger.debug("[Signal::Engine] MACD factor error: #{e.message}")
        0.0
      end

      def smc_bias_confidence_factor(direction, index_cfg)
        smc_direction = get_smc_bias_direction(index_cfg)
        return 0.20 if smc_direction == direction
        return 0.05 if smc_direction == :neutral

        0.0
      rescue StandardError => e
        Rails.logger.debug("[Signal::Engine] SMC bias factor error: #{e.message}")
        0.0
      end

      def get_smc_bias_direction(index_cfg)
        instrument = Instrument.find_by(tradingsymbol: index_cfg[:key])
        return :neutral unless instrument

        decision = Smc::BiasEngine.new(instrument).decision
        case decision
        when :call then :bullish
        when :put then :bearish
        else :neutral
        end
      rescue StandardError
        :neutral
      end

      def calculate_confidence_score(primary_analysis:, validation_result:, index_cfg: nil)
        base_confidence = 0.5
        adx_factor = adx_confidence_factor(primary_analysis[:adx_value])
        validation_factor = validation_result[:valid] ? 0.1 : 0.0
        supertrend_factor = supertrend_confidence_factor(primary_analysis[:supertrend])

        direction = primary_analysis[:direction]
        series = primary_analysis[:series]
        macd_factor = series && direction ? macd_confidence_factor(direction, series) : 0.0
        smc_factor = index_cfg && direction ? smc_bias_confidence_factor(direction, index_cfg) : 0.0

        capped = [base_confidence + adx_factor + validation_factor + supertrend_factor + macd_factor + smc_factor, 1.0].min
        return capped if validation_result[:valid]

        [capped, 0.79].min
      end

      def adx_confidence_factor(adx_value)
        return 0.0 unless adx_value

        case adx_value.to_f
        when 30.. then 0.3
        when 20...30 then 0.2
        when 15...20 then 0.1
        else 0.0
        end
      end

      def supertrend_confidence_factor(supertrend)
        return 0.0 unless supertrend&.dig(:last_value)

        st_value = supertrend[:last_value].to_f
        [st_value / 1000.0, 0.1].min
      end

      def expiry_trade_allowed?(symbol)
        expiry_model = 'Strategies::ExpiryModel'.safe_constantize
        return true unless expiry_model

        expiry_model.trade_allowed?(symbol: symbol)
      rescue StandardError => e
        Rails.logger.error("[Signal] ExpiryModel unavailable (#{e.class}: #{e.message}); allowing trade")
        true
      end

      def resolve_nearest_expiry_date(index_cfg:)
        Options::DerivativeChainAnalyzer.new(index_key: index_cfg[:key]).nearest_expiry
      rescue StandardError => e
        Rails.logger.warn("[Signal] resolve_nearest_expiry_date #{index_cfg[:key]}: #{e.class} — #{e.message}")
        nil
      end

      def entry_dte_guard_blocks?(index_cfg:, signals_cfg:, nearest_expiry:)
        cfg = signals_cfg[:entry_dte_guard] || {}
        return false unless cfg[:enabled]

        threshold = cfg.fetch(:reject_when_days_to_expiry_lte, 1).to_i
        return false if nearest_expiry.blank?

        today = Time.zone.today
        expiry_day = nearest_expiry.is_a?(Date) ? nearest_expiry : Date.parse(nearest_expiry.to_s)
        dte = (expiry_day - today).to_i
        if dte <= threshold
          Rails.logger.info("[Signal] entry_dte_guard BLOCKED #{index_cfg[:key]}: DTE=#{dte} (<= #{threshold})")
          return true
        end

        false
      rescue ArgumentError, TypeError => e
        Rails.logger.warn("[Signal] entry_dte_guard parse error #{index_cfg[:key]}: #{e.message}")
        false
      end

      def execute_options_analysis(index_cfg, expiry_date:, expiry_blocked:)
        {
          gamma_pressure: { score: 0.0, strike: nil },
          iv_rank: { valid: true },
          theta_risk: { valid: true },
          expiry_blocked: expiry_blocked,
          expiry_date: expiry_date,
          chain_data: nil
        }
      end

      def build_diagnostic_metadata(index_cfg:, final_direction:, primary_analysis:, regime:, options_analysis:,
                                    validation_result:, state_snapshot:, effective_validation_mode:,
                                    signals_cfg:, primary_tf:, effective_timeframe:, smc_decision:, permission:)
        Signal::MetadataBuilder.build(
          index_cfg: index_cfg,
          final_direction: final_direction,
          primary_analysis: primary_analysis,
          confirmation_analysis: nil,
          regime: regime,
          regime_result: { regime: regime },
          ta_result: nil,
          options_analysis: options_analysis,
          validation_result: validation_result,
          state_snapshot: state_snapshot,
          effective_validation_mode: effective_validation_mode,
          signals_cfg: signals_cfg,
          primary_tf: primary_tf,
          effective_timeframe: effective_timeframe,
          confirmation_tf: nil,
          enable_confirmation: false,
          smc_decision: smc_decision,
          permission: permission,
          smc_confluence_ltf_summary: nil,
          strategy_name: 'supertrend',
          strategy_mode: 'stock'
        )
      end

      def record_signal_skip(signal, reason, stage: nil, code: nil)
        extra = {}
        extra['entry_skip_stage'] = stage.to_s if stage.present?
        extra['entry_skip_code'] = code.to_s if code.present?
        signal&.record_entry_outcome('skipped', reason, extra_metadata: extra.presence)
      end

      def execute_stock_entry_gate(index_cfg:, signal:, final_direction:, options_analysis:, permission:)
        if options_analysis[:expiry_blocked]
          Rails.logger.info("[Signal] ExpiryModel BLOCKED #{index_cfg[:key]}: Midday decay period")
          record_signal_skip(
            signal,
            'expiry_midday_decay: Midday decay period blocked entry for this expiry',
            stage: 'expiry_model',
            code: 'expiry_midday_decay'
          )
          Signal::StateTracker.reset(index_cfg[:key])
          return nil
        end

        picks = Options::ChainAnalyzer.pick_strikes(index_cfg: index_cfg, direction: final_direction)
        if picks.blank?
          skip_reason = 'No ATM option strike available'
          Rails.logger.warn("[Signal] #{skip_reason} for #{index_cfg[:key]} #{final_direction}")
          record_signal_skip(signal, skip_reason, stage: 'strike_selection', code: 'no_strikes')
          Signal::StateTracker.reset(index_cfg[:key])
          return nil
        end

        Rails.logger.info("[Signal] Stock strike pick #{index_cfg[:key]}: #{picks.pluck(:symbol).join(', ')}")
        { picks: picks, execution_permission: permission }
      end

      def trigger_entry_flow(index_cfg:, signal:, picks:, final_direction:, primary_series:, primary_tf:,
                             diagnostic_metadata:, quality_result:, execution_permission:)
        entry_metadata = diagnostic_metadata.merge(
          entry_contract: Entries::EntryGuard::SUPERTREND_CONTRACT,
          permission: execution_permission,
          entry_quality_score: quality_result[:score],
          entry_quality_breakdown: quality_result[:breakdown],
          fast_entry_mode: FastEntryMode.enabled?,
          bos_id: "st_#{index_cfg[:key]}_#{Time.current.to_i}",
          bos_timeframe: primary_tf,
          bos_origin_price: primary_series.candles.last&.close,
          bos_level: primary_series.candles.last&.close,
          entry_underlying_price: primary_series.candles.last&.close
        )

        picks.each do |pick|
          entered = Entries::EntryGuard.try_enter(
            index_cfg: index_cfg,
            pick: pick,
            direction: final_direction,
            scale_multiplier: 1,
            entry_metadata: entry_metadata,
            permission: execution_permission,
            signal: signal
          )
          return true if entered
        end
        false
      end

      def dynamic_config_enabled?
        AlgoConfig.fetch.dig(:signals, :use_optimized_params) != false
      end

      def resolved_supertrend_cfg(instrument, interval, signals_cfg)
        base_cfg = (signals_cfg[:supertrend] || { period: 7, multiplier: 3.0 }).dup
        return base_cfg unless dynamic_config_enabled?

        optimized = BestIndicatorParam.best_for_indicator(instrument.id, interval, :supertrend).first
        return base_cfg unless optimized&.params.is_a?(Hash)

        params = optimized.params.symbolize_keys
        base_cfg[:period] = params[:atr_period] if params[:atr_period]
        base_cfg[:base_multiplier] = params[:multiplier] if params[:multiplier]
        base_cfg
      end

      def resolved_adx_min(instrument, interval, index_cfg, timeframe_label)
        signals_cfg = AlgoConfig.fetch[:signals] || {}
        adx_cfg = signals_cfg[:adx] || {}
        static_min = index_cfg.dig(:adx_thresholds, timeframe_label.to_sym) || adx_cfg[:min_strength] || 0

        return static_min unless dynamic_config_enabled?

        optimized = BestIndicatorParam.best_for_indicator(instrument.id, interval, :adx).first
        return static_min unless optimized&.params.is_a?(Hash)

        optimized_min = optimized.params.symbolize_keys[:min_strength]
        optimized_min || static_min
      end
    end
  end
end
