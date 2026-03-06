# frozen_string_literal: true

module Api
  class AnalysisController < ApplicationController
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
      if stale.any?
        AnalysisJob.perform_later(index_key, force: params[:force] == 'true')
      end

      # Fast lookups (no cache needed — instant)
      ltp = Live::TickCache.ltp(instrument.exchange_segment, instrument.security_id)
      time_regime = safe_call('time_regime') { Live::TimeRegimeService.instance.current_regime }
      active_positions = PositionTracker.active.where(
        "meta->>'index_key' = ?", index_key
      ).count

      render json: {
        index_key: index_key,
        symbol: instrument.symbol_name,
        ltp: ltp&.to_f,
        timestamp: Time.current.iso8601,
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

    # GET /api/analysis/:index_key/historical
    def historical
      index_key = params[:index_key].to_s.upcase
      weeks = (params[:weeks] || 8).to_i.clamp(1, 24)

      analyzer = HistoricalOptionsAnalyzer.new(index_key, weeks: weeks)
      result = analyzer.analyze

      render json: result
    rescue StandardError => e
      Rails.logger.error("[AnalysisController] historical error: #{e.class} - #{e.message}")
      render json: { error: 'internal_error', message: e.message }, status: :internal_server_error
    end

    private

    def find_instrument(index_key)
      index_cfg = IndexConfigLoader.load_indices.find { |idx| idx[:key].to_s.upcase == index_key }
      return nil unless index_cfg

      Instrument.find_by_sid_and_segment(
        security_id: index_cfg[:sid],
        segment_code: index_cfg[:segment]
      )
    end

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
