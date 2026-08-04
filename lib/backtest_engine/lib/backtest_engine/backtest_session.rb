# frozen_string_literal: true

module BacktestEngine
  class BacktestSession
    Result = Struct.new(:portfolio, :metrics)
    DEFAULT_INDICATOR_PARAMS = {
      pullback_ema_period: 20,
      volume_spike_period: 10,
      iv_expansion_period: 10
    }.freeze

    def initialize(index_candles:, option_data:, starting_capital:, lot_size:, risk_per_trade_pct: 1.0)
      @index_candles = index_candles
      @option_data = option_data
      @portfolio = Portfolio::Portfolio.new(starting_capital: starting_capital)
      @execution_engine = ExecutionEngine.new(lot_size: lot_size)
      @risk_per_trade_pct = risk_per_trade_pct.to_f
      @lot_size = lot_size
      @metrics = Metrics.new
    end

    attr_reader :portfolio, :metrics

    def run(strategy_class, day_type: :normal, ltp_source: :options_close, structure_engine: :default, regime_scorer: false, strategy_router: false, indicator_params: {})
      indicator_series = Market::CandleSeries.new(index_candles)
      @indicator_series_ref = indicator_series
      iv_series = build_iv_series
      htf_bias_mapper = build_htf_bias_mapper
      structure_engine_v2 = structure_engine == :v2 ? Market::StructureEngineV2.new(indicator_series) : nil
      regime_scorer_instance = regime_scorer ? Market::RegimeScorer.new(indicator_series) : nil
      regime_state_instance = regime_scorer ? Market::RegimeState.new : nil
      router = strategy_router ? Strategies::Router.new : nil
      indicator_params = DEFAULT_INDICATOR_PARAMS.merge(indicator_params.transform_keys(&:to_sym))
      iv_expansion_signal = iv_series ? Market::IvExpansionSignal.new(iv_series, period: indicator_params[:iv_expansion_period]) : nil

      position = nil

      index_candles.each_with_index do |index_candle, index|
        indicators = build_indicators(
          indicator_series: indicator_series,
          iv_series: iv_series,
          iv_expansion_signal: iv_expansion_signal,
          htf_bias_mapper: htf_bias_mapper,
          structure_engine_v2: structure_engine_v2,
          regime_scorer: regime_scorer_instance,
          regime_state: regime_state_instance,
          indicator_params: indicator_params,
          candle_index: index,
          timestamp: index_candle.timestamp
        )

        ltp = resolve_ltp(ltp_source, index_candle, position)

        strategy_result = Strategies::Runner.new(
          index_candle: index_candle,
          indicators: indicators,
          ltp: ltp,
          strategy_class: strategy_class
        ).call

        context = strategy_result[:context]
        signal = strategy_result[:signal]

        if router && signal.is_a?(Hash) && signal[:action] == :buy
          regime = regime_for(context)
          unless router.tradable?(regime: regime)
            signal = {
              action: :skip,
              reason: "Regime not tradable (regime=#{regime.inspect})"
            }
          end
        end

        record_decision(signal, context, day_type: day_type)

        position = manage_position(
          position: position,
          signal: signal,
          context: context,
          timestamp: index_candle.timestamp,
          day_type: day_type,
          candle_index: index
        )
      end

      Result.new(portfolio: portfolio, metrics: metrics)
    end

    private

    attr_reader :index_candles, :option_data, :execution_engine, :risk_per_trade_pct, :lot_size

    def record_decision(signal, context, day_type:)
      return unless signal.is_a?(Hash)

      timestamp = context[:time]
      session = session_for(timestamp, day_type: day_type) if timestamp.respond_to?(:strftime)
      regime = regime_for(context)

      metrics.record_decision(
        action: signal[:action],
        day_type: day_type,
        session: session,
        regime: regime,
        reason: signal[:reason]
      )
    end

    def build_indicators(indicator_series:, iv_series:, htf_bias_mapper:, indicator_params:, candle_index:, timestamp:, iv_expansion_signal: nil, structure_engine_v2: nil, regime_scorer: nil, regime_state: nil)
      base = {
        structure: resolve_structure(indicator_series, candle_index, structure_engine_v2),
        pullback: indicator_series.pullback?(candle_index, ema_period: indicator_params[:pullback_ema_period]),
        volume_ratio: indicator_series.volume_ratio(
          candle_index,
          period: indicator_params[:volume_spike_period]
        ),
        iv_expansion: iv_expansion_signal&.modifier_at(timestamp),
        iv: iv_series&.iv_for(timestamp),
        iv_percentile: iv_series&.iv_percentile(timestamp),
        htf_bias: htf_bias_mapper&.bias_for(timestamp)
      }

      if regime_scorer && regime_state
        score = regime_scorer.score_at(candle_index)
        state = regime_state.update(candle_index, score[:direction])
        base[:regime_score] = score[:score]
        base[:regime_stable] = state[:allowed_to_trade]
      end

      base
    end

    def resolve_structure(series, index, engine_v2)
      return engine_v2.structure_at(index) if engine_v2

      structure_at_legacy(series, index)
    end

    def structure_at_legacy(series, index)
      return :range if index < 2

      series.structure[index - 2] || :range
    end

    def build_iv_series
      atm_call = option_data[["ATM", :call]]
      return nil if atm_call.blank?

      Market::IvSeries.new(atm_call)
    end

    def build_htf_bias_mapper
      htf_candles = resample_index_to_htf(index_candles, interval_minutes: 5)
      return nil if htf_candles.empty?

      structure_helper = Market::HtfStructureHelper.new(htf_candles)
      Market::HtfBiasMapper.new(htf_candles, structure_helper.structure)
    end

    def resample_index_to_htf(candles, interval_minutes:)
      return [] if candles.empty?
      return [] if interval_minutes.to_i <= 1

      candles.each_slice(interval_minutes.to_i).map do |group|
        {
          timestamp: group.first.timestamp,
          open: group.first.open,
          high: group.map(&:high).max,
          low: group.map(&:low).min,
          close: group.last.close,
          volume: group.sum(&:volume)
        }
      end
    end

    def resolve_ltp(source, index_candle, position)
      case source
      when :index_close
        index_candle.close
      when :options_close
        return nil unless position

        candle = option_candle_at(position[:strike], position[:option_type], index_candle.timestamp)
        candle && candle[:close].to_f
      end
    end

    def manage_position(position:, signal:, context:, timestamp:, day_type:, candle_index:)
      session = session_for(timestamp, day_type: day_type)
      regime = regime_for(context)

      updated_position = position && update_exit_rules(position, context, timestamp, candle_index)
      return nil if updated_position == :closed

      position = updated_position

      return position if position
      return position unless signal.is_a?(Hash) && signal[:action] == :buy

      open_position_from_signal(signal, context, timestamp, day_type, session, regime, candle_index)
    end

    def open_position_from_signal(signal, context, timestamp, day_type, session, regime, candle_index)
      strike_key = strike_key_for(signal[:strike])
      option_type = signal[:option_type]

      option_candle = option_candle_at(strike_key, option_type, timestamp)
      return nil unless option_candle

      raw_entry = option_candle[:close].to_f
      entry_price = execution_engine.entry_fill(raw_entry)
      required_capital = execution_engine.capital_required(entry_price)

      opened = portfolio.open_position!(signal, entry_price, lot_size, quantity_for_trade(required_capital))
      return nil unless opened

      opened.merge!(
        option_type: option_type,
        strike: strike_key,
        entry_time: timestamp,
        entry_index: candle_index,
        max_hold_minutes: signal[:max_hold_minutes],
        sl_pct: signal[:sl_pct],
        target_pct: signal[:target_pct],
        trail: signal[:trail],
        trail_trigger: signal[:trail_trigger],
        trail_type: signal[:trail_type],
        trail_value: signal[:trail_value],
        breakeven_trigger: signal[:breakeven_trigger],
        underlying_trend_exit: signal[:underlying_trend_exit],
        trailing_sl: nil,
        day_type: day_type,
        session: session,
        regime: regime,
        direction: context[:structure]
      )

      # Initialize TME
      opened[:tme] = TradeManagementEngine.new(
        opened,
        indicator_series: @indicator_series_ref,
        option_data: option_data,
        execution_engine: execution_engine
      )

      opened
    end

    def quantity_for_trade(required_capital)
      return 1 if required_capital <= 0.0

      risk_budget = (portfolio.cash * (risk_per_trade_pct / 100.0))
      return 1 if risk_budget <= 0.0

      [1, (risk_budget / required_capital).floor].max
    end

    def update_exit_rules(position, context, timestamp, candle_index)
      option_candle = option_candle_at(position[:strike], position[:option_type], timestamp)
      return position unless option_candle

      raw_ltp = option_candle[:close].to_f
      ltp = execution_engine.exit_fill(raw_ltp)

      tme = position[:tme] ||= TradeManagementEngine.new(
        position,
        indicator_series: @indicator_series_ref,
        option_data: option_data,
        execution_engine: execution_engine
      )

      index_candle = index_candles[candle_index]
      exit_decision = tme.evaluate(candle_index, index_candle, ltp, timestamp)

      # Keep tracking trailing_sl in the position hash for backward compatibility
      position[:trailing_sl] = tme.trailing_sl

      if exit_decision
        # Calculate exit metrics
        metrics_data = tme.exit_metrics(ltp)
        position[:mfe] = metrics_data[:mfe]
        position[:mae] = metrics_data[:mae]
        position[:exit_efficiency] = metrics_data[:exit_efficiency]
        position[:trend_capture_pct] = metrics_data[:trend_capture_pct]
        position[:exit_reason] = exit_decision[:reason]

        close_position!(position, ltp, timestamp, exit_decision[:reason])
        return :closed
      end

      position
    end

    def close_position!(position, exit_price, timestamp, exit_reason)
      pnl = portfolio.close_position!(position, exit_price, execution_engine)
      portfolio.record_equity(pnl: pnl)

      pnl_pct = ((exit_price - position[:entry_price]) / position[:entry_price]) * 100.0

      metrics.record_trade(
        Metrics::Trade.new(
          entry_time: position[:entry_time],
          exit_time: timestamp,
          side: :buy,
          option_type: position[:option_type],
          strike: position[:strike],
          entry_price: position[:entry_price],
          exit_price: exit_price,
          pnl: pnl,
          pnl_pct: pnl_pct,
          day_type: position[:day_type],
          session: position[:session],
          regime: position[:regime],
          mfe: position[:mfe],
          mae: position[:mae],
          exit_efficiency: position[:exit_efficiency],
          trend_capture_pct: position[:trend_capture_pct],
          exit_reason: exit_reason
        )
      )
    end

    def strike_key_for(mode)
      case mode
      when :atm
        "ATM"
      when :atm_plus_1
        "ATM+1"
      when :atm_minus_1
        "ATM-1"
      when :atm_plus_2
        "ATM+2"
      when :atm_minus_2
        "ATM-2"
      else
        "ATM"
      end
    end

    def option_candle_at(strike_key, option_type, timestamp)
      candles = option_data[[strike_key, option_type]]
      return nil unless candles

      candles.find { |c| c[:timestamp] == timestamp || c[:timestamp] == timestamp.to_i }
    end

    def regime_for(context)
      structure = context[:structure]
      return :chop if structure == :range || structure == :neutral || structure.nil?

      structure == :bullish ? :trend_bull : :trend_bear
    end

    def session_for(time, day_type:)
      hhmm = time.strftime("%H:%M")

      if day_type == :expiry
        return :e1 if hhmm >= "09:15" && hhmm < "09:30"
        return :e2 if hhmm >= "09:30" && hhmm < "11:00"
        return :e3 if hhmm >= "11:00" && hhmm < "13:30"
        return :e4 if hhmm.between?("13:30", "15:15")

        return :off
      end

      return :s1 if hhmm >= "09:15" && hhmm < "09:45"
      return :s2 if hhmm >= "09:45" && hhmm < "11:30"
      return :s3 if hhmm >= "11:30" && hhmm < "13:45"
      return :s4 if hhmm.between?("13:45", "15:15")

      :off
    end
  end
end

