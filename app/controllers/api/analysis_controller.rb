# frozen_string_literal: true

module Api
  class AnalysisController < ApplicationController
    # GET /api/analysis/:index_key
    # Live SMC + market regime + AI analysis for an index
    def show
      index_key = params[:index_key].to_s.upcase
      instrument = find_instrument(index_key)
      return render json: { error: 'Index not found' }, status: :not_found unless instrument

      render json: build_live_analysis(instrument, index_key)
    rescue StandardError => e
      Rails.logger.error("[AnalysisController] show error: #{e.class} - #{e.message}")
      render json: { error: 'internal_error', message: e.message }, status: :internal_server_error
    end

    # GET /api/analysis/:index_key/historical
    # Historical ATM options behavior analysis
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

    def build_live_analysis(instrument, index_key)
      # SMC Analysis
      engine = Smc::BiasEngine.new(instrument)
      smc_details = safe_call('smc') { engine.details }
      ai_analysis = safe_call('ai') { engine.analyze_with_ai }

      # Market Regime
      regime_data = safe_call('regime') { detect_market_regime(instrument) }

      # Current market data
      ltp = Live::TickCache.ltp(instrument.exchange_segment, instrument.security_id)
      time_regime = safe_call('time_regime') { Live::TimeRegimeService.instance.current_regime }

      # Position data
      active_positions = PositionTracker.active.where(
        "meta->>'index_key' = ? OR index_key = ?", index_key, index_key
      ).count

      {
        index_key: index_key,
        symbol: instrument.symbol_name,
        ltp: ltp&.to_f,
        timestamp: Time.current.iso8601,
        smc: smc_details,
        ai_analysis: ai_analysis,
        market_regime: regime_data,
        time_regime: time_regime,
        active_positions: active_positions,
        config: index_config_summary(index_key)
      }
    end

    def detect_market_regime(instrument)
      series = instrument.candle_series(interval: '5')
      return { regime: 'NO_DATA', confidence: 0 } unless series&.candles&.size&.>= 20

      MarketRegimeDetector.new(series).detect
    rescue StandardError => e
      Rails.logger.warn("[AnalysisController] regime detection failed: #{e.message}")
      { regime: 'ERROR', confidence: 0 }
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
