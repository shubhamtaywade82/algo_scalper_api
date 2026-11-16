# frozen_string_literal: true

module Api
  class AnalysisController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_dashboard_token!

    # GET /api/analysis/:index_key
    # Always returns instantly from cache. Triggers background refresh if stale.
    def show
      index_key = params[:index_key].to_s.upcase
      instrument = IndexConfigLoader.index_instrument(index_key)
      return render json: { error: 'Index not found' }, status: :not_found unless instrument

      # Read pre-computed results from store
      stored = AnalysisStore.read_all(index_key)

      # Trigger background refresh for stale components
      stale = AnalysisStore.stale_components(index_key)
      if stale.any?
        Thread.new do
          Rails.application.executor.wrap do
            AnalysisJob.perform_now(index_key, force: params[:force] == 'true')
          end
        end
      end

      # Fast lookups (no cache needed — instant)
      ltp = Live::TickCache.ltp(instrument.exchange_segment, instrument.security_id)
      time_regime = safe_call('time_regime') { Live::TimeRegimeService.instance.current_regime }
      active_positions = PositionTracker.active.where(
        "meta->>'index_key' = ?", index_key
      ).count

      market_closed = TradingSession::Service.market_closed?
      generative_ai_gated = Ai::GenerativeAiMarketGate.skip?(force: false)

      render json: {
        index_key: index_key,
        symbol: instrument.symbol_name,
        ltp: ltp&.to_f,
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
      Rails.logger.error("[AnalysisController] show error: #{e.class} - #{e.message}")
      render json: { error: 'internal_error', message: e.message }, status: :internal_server_error
    end

    private

    def index_config_summary(index_key)
      cfg = AlgoConfig.fetch
      risk = cfg[:risk] || {}
      index_cfg = (cfg[:indices] || []).find { |i| i[:key] == index_key } || {}

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
  end
end
