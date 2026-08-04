# frozen_string_literal: true

module Api
  class AnalysisController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_dashboard_token!, only: %i[show historical risk_explorer]
    before_action :authenticate_operator_token!, only: %i[ai_snapshot]

    # GET /api/analysis/:index_key
    # Always returns instantly from cache. Triggers background refresh if stale.
    def show
      index_key = params[:index_key].to_s.upcase
      instrument = find_instrument(index_key)
      return render json: { error: 'Index not found' }, status: :not_found unless instrument

      # Read pre-computed results from store
      stored = AnalysisStore.read_all(index_key)

      # Trigger background refresh for stale components
      stale = AnalysisStore.stale_components(index_key)
      AnalysisJob.perform_later(index_key, force: params[:force] == 'true') if stale.any?

      # Fast lookups (no cache needed — instant)
      ltp = Live::TickCache.ltp(instrument.exchange_segment, instrument.security_id)
      time_regime = safe_call('time_regime') { Live::TimeRegimeService.instance.current_regime }
      active_positions = PositionTracker.active.by_index_key(index_key).count

      market_closed = TradingSession::Service.market_closed?
      generative_ai_gated = Ai::GenerativeAiMarketGate.skip?(force: false)

      render json: {
        index_key: index_key,
        symbol: instrument.symbol_name,
        ltp: ltp&.to_f,
        instruments_imported: instrument.persisted?,
        timestamp: Time.current.iso8601,
        session: {
          market_closed: market_closed,
          generative_ai_gated: generative_ai_gated
        },
        smc: stored[:smc]&.dig(:data),
        smc_validity: stored[:smc]&.dig(:validity),
        ai_analysis: stored[:ai]&.dig(:data),
        ai_validity: stored[:ai]&.dig(:validity),
        market_regime: stored[:regime]&.dig(:data),
        regime_validity: stored[:regime]&.dig(:validity),
        time_regime: time_regime,
        active_positions: active_positions,
        config: index_config_summary(index_key),
        background_refresh: stale.any? ? { refreshing: stale, message: 'Background refresh triggered' } : nil
      }
    rescue StandardError => e
      render_analysis_internal_error('show', e)
    end

    # GET /api/analysis/:index_key/risk_explorer
    # Expected value & risk report for intraday long CE/PE (config SL/TP, historical variance, limits).
    def risk_explorer
      index_key = params[:index_key].to_s.upcase
      return render json: { error: 'Index not found' }, status: :not_found unless index_known?(index_key)

      weeks = (params[:weeks] || 8).to_i.clamp(1, 24)
      win_p = params[:win_probability].presence&.to_f
      reward_r = params[:reward_multiple].presence&.to_f

      result = OptionsBuying::RiskExplorer.call(
        index_key: index_key,
        weeks: weeks,
        win_probability: win_p,
        reward_multiple: reward_r
      )
      return render json: { error: 'risk_explorer_failed' }, status: :internal_server_error if result.nil?

      render json: result
    rescue StandardError => e
      render_analysis_internal_error('risk_explorer', e)
    end

    # GET /api/analysis/:index_key/historical
    def historical
      index_key = params[:index_key].to_s.upcase
      weeks = (params[:weeks] || 8).to_i.clamp(1, 24)

      analyzer = HistoricalOptionsAnalyzer.new(index_key, weeks: weeks)
      result = analyzer.analyze

      render json: result
    rescue StandardError => e
      render_analysis_internal_error('historical', e)
    end

    # POST /api/analysis/:index_key/ai_snapshot
    # On-demand AI analysis using current market context. Synchronous — may take up to 120s.
    # Does NOT write to AnalysisStore — snapshot is transient and display-only.
    def ai_snapshot
      index_key  = params[:index_key].to_s.upcase
      instrument = find_instrument(index_key)
      return render json: { error: 'Index not found' }, status: :not_found unless instrument

      ltp    = Live::TickCache.ltp(instrument.exchange_segment, instrument.security_id)
      stored = AnalysisStore.read_all(index_key)

      client = Services::Ai::OllamaClient.instance
      unless client.enabled?
        return render json: { error: 'AI service not configured' }, status: :service_unavailable
      end

      force = params[:force].to_s == 'true'
      if Ai::GenerativeAiMarketGate.skip?(force: force)
        return render json: {
          error: 'market_closed',
          message: 'Generative AI is paused while the market is closed (ai.skip_generative_ai_when_market_closed). Pass force=true to override.'
        }, status: :unprocessable_content
      end

      messages = Ai::AiSnapshotPromptBuilder.build(
        index_key: index_key,
        ltp: ltp&.to_f,
        smc: stored[:smc]&.dig(:data),
        regime: stored[:regime]&.dig(:data),
        calibration_stats: nil
      )

      ai_response = client.chat(messages: messages, temperature: 0.3)

      # OllamaClient#chat rescues all StandardError internally and returns nil on failure.
      # Treat nil as a service failure — exception-based rescues below are defense-in-depth only.
      if ai_response.nil?
        return render json: { error: 'AI service unavailable' }, status: :service_unavailable
      end

      render json: { snapshot: ai_response, generated_at: Time.current.iso8601 }
    rescue Net::ReadTimeout, Faraday::TimeoutError => e
      Rails.logger.warn("[AnalysisController] ai_snapshot timeout: #{e.class}")
      render json: { error: 'AI service unavailable — timed out' }, status: :service_unavailable
    rescue StandardError => e
      Rails.logger.error("[AnalysisController] ai_snapshot error: #{e.class} - #{e.message}")
      render json: { error: 'AI service unavailable' }, status: :service_unavailable
    end

    # POST /api/analysis/:index_key/optimize
    # Runs indicator parameter sweeps or trailing stop calibrations
    def optimize
      index_key  = params[:index_key].to_s.upcase
      instrument = find_instrument(index_key)
      return render json: { error: 'Index not found' }, status: :not_found unless instrument

      lookback_days = (params[:lookback_days] || 5).to_i
      interval      = params[:interval] || '5'
      indicator     = params[:indicator] || 'all'

      results = {}
      if %w[all trailing].include?(indicator)
        # Run Trailing stop optimizer
        optimizer = Optimization::TrailingOptimizer.new(index_key: index_key)
        results[:trailing] = optimizer.optimize
      end

      if indicator == 'all' || %w[adx rsi macd supertrend].include?(indicator)
        # Run specific technical indicator optimization
        to_run = indicator == 'all' ? %i[adx rsi macd supertrend] : [indicator.to_sym]
        results[:indicators] = {}
        to_run.each do |ind|
          optimizer = Optimization::SingleIndicatorOptimizer.new(
            instrument: instrument,
            interval: interval,
            indicator: ind,
            lookback_days: lookback_days,
            dry_run: params[:dry_run] == 'true'
          )
          results[:indicators][ind] = optimizer.run
        end
      end

      render json: {
        index_key: index_key,
        results: results,
        optimized_at: Time.current.iso8601
      }
    rescue StandardError => e
      Rails.logger.error("[AnalysisController] optimize error: #{e.class} - #{e.message}")
      render json: { error: "Optimization failed: #{e.message}" }, status: :unprocessable_content
    end

    # POST /api/analysis/:index_key/ai_snapshot
    # On-demand AI analysis using current market context. Synchronous — may take up to 120s.
    # Does NOT write to AnalysisStore — snapshot is transient and display-only.
    def ai_snapshot
      index_key  = params[:index_key].to_s.upcase
      instrument = find_instrument(index_key)
      return render json: { error: 'Index not found' }, status: :not_found unless instrument

      ltp    = Live::TickCache.ltp(instrument.exchange_segment, instrument.security_id)
      stored = AnalysisStore.read_all(index_key)

      latest_run = CalibrationRun.where(symbol: index_key).order(created_at: :desc).first

      client = Services::Ai::OpenaiClient.instance
      unless client.enabled?
        return render json: { error: 'AI service not configured' }, status: :service_unavailable
      end

      messages = Ai::AiSnapshotPromptBuilder.build(
        index_key: index_key,
        ltp: ltp&.to_f,
        smc: stored[:smc]&.dig(:data),
        regime: stored[:regime]&.dig(:data),
        calibration_stats: latest_run&.raw_stats
      )

      ai_response = client.chat(messages: messages, temperature: 0.3)

      # OpenaiClient#chat rescues all StandardError internally and returns nil on failure.
      # Treat nil as a service failure — exception-based rescues below are defense-in-depth only.
      if ai_response.nil?
        return render json: { error: 'AI service unavailable' }, status: :service_unavailable
      end

      render json: { snapshot: ai_response, generated_at: Time.current.iso8601 }
    rescue Net::ReadTimeout, Faraday::TimeoutError => e
      Rails.logger.warn("[AnalysisController] ai_snapshot timeout: #{e.class}")
      render json: { error: 'AI service unavailable — timed out' }, status: :service_unavailable
    rescue StandardError => e
      Rails.logger.error("[AnalysisController] ai_snapshot error: #{e.class} - #{e.message}")
      render json: { error: 'AI service unavailable' }, status: :service_unavailable
    end

    private

    def find_instrument(index_key)
      index_cfg = IndexConfigLoader.load_indices.find { |idx| idx[:key].to_s.upcase == index_key }
      return nil unless index_cfg

      IndexInstrumentCache.instance.get_or_fetch(index_cfg)
    end

    def index_known?(index_key)
      IndexConfigLoader.load_indices.any? { |idx| idx[:key].to_s.upcase == index_key }
    end

    def index_config_summary(index_key)
      cfg = AlgoConfig.fetch
      risk = cfg[:risk] || {}
      index_cfg = (cfg[:indices] || []).find { |i| i[:key].to_s.upcase == index_key.to_s.upcase } || {}

      {
        trailing: risk.dig(:institutional_trailing, index_key.downcase.to_sym),
        time_stop: risk[:time_stop],
        profit_floor: risk[:profit_floor],
        risk_model: index_cfg[:risk_model],
        direction: index_cfg[:direction]
      }
    end

    def safe_call(label)
      yield
    rescue StandardError => e
      Rails.logger.warn("[AnalysisController] #{label} failed: #{e.class} - #{e.message}")
      nil
    end

    def render_analysis_internal_error(action_label, exception)
      Rails.logger.error(
        "[AnalysisController] #{action_label} error: #{exception.class} - #{exception.message}"
      )
      body = { error: 'internal_error' }
      body[:message] = exception.message unless Rails.env.production?
      render json: body, status: :internal_server_error
    end
  end
end
