# frozen_string_literal: true

module Api
  # On-demand AI snapshot for an index; operator token because it spends an LLM call.
  class AnalysisAiSnapshotsController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_operator_token!

    # POST /api/analysis/:index_key/ai_snapshots
    # On-demand AI analysis using current market context. Synchronous — may take up to 120s.
    # Does NOT write to AnalysisStore — snapshot is transient and display-only.
    def create
      index_key  = params[:index_key].to_s.upcase
      instrument = IndexConfigLoader.index_instrument(index_key)
      return render json: { error: 'Index not found' }, status: :not_found unless instrument

      ltp    = Live::TickCache.ltp(instrument.exchange_segment, instrument.security_id)
      stored = AnalysisStore.read_all(index_key)

      latest_run = CalibrationRun.where(symbol: index_key).order(created_at: :desc).first

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
        calibration_stats: latest_run&.raw_stats
      )

      ai_response = client.chat(messages: messages, temperature: 0.3)

      # OllamaClient#chat rescues all StandardError internally and returns nil on failure.
      # Treat nil as a service failure — exception-based rescues below are defense-in-depth only.
      if ai_response.nil?
        return render json: { error: 'AI service unavailable' }, status: :service_unavailable
      end

      render json: { snapshot: ai_response, generated_at: Time.current.iso8601 }
    rescue Net::ReadTimeout, Faraday::TimeoutError => e
      Rails.logger.warn("[AnalysisAiSnapshotsController] timeout: #{e.class}")
      render json: { error: 'AI service unavailable — timed out' }, status: :service_unavailable
    rescue StandardError => e
      Rails.logger.error("[AnalysisAiSnapshotsController] error: #{e.class} - #{e.message}")
      render json: { error: 'AI service unavailable' }, status: :service_unavailable
    end
  end
end
