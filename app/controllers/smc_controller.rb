# frozen_string_literal: true

class SmcController < ApplicationController
  # Optional entry point for SMC context/decision (alerts, scanners, debugging).
  #
  # IMPORTANT:
  # - This does not fetch any new data sources; it uses Instrument#candles.
  # - It does not mutate candles/series; it only composes Smc services.
  #
  # Params:
  # - security_id: underlying security id (string/int)
  # - segment: exchange segment code (e.g. "IDX_I")
  # - symbol_name (optional): fallback lookup by symbol
  def decision
    security_id = params[:security_id].to_s.presence
    segment = params[:segment].to_s.presence
    symbol_name = params[:symbol_name].to_s.presence

    if security_id.blank? || segment.blank?
      return render json: { ok: false, error: 'security_id and segment are required' }, status: :unprocessable_entity
    end

    instrument = Instrument.find_by_sid_and_segment(security_id: security_id, segment_code: segment,
                                                    symbol_name: symbol_name)
    return render json: { ok: false, error: 'instrument not found' }, status: :not_found unless instrument

    engine = Smc::BiasEngine.new(instrument)

    payload =
      if params[:details].to_s == '1'
        { ok: true }.merge(engine.details)
      else
        { ok: true, decision: engine.decision }
      end

    # Add AI analysis if requested
    if params[:ai].to_s == '1'
      ai_analysis = engine.analyze_with_ai
      payload[:ai_analysis] = ai_analysis if ai_analysis
    end

    render json: payload, status: :ok
  rescue StandardError => e
    Rails.logger.error("[SmcController] #{e.class} - #{e.message}")
    render json: { ok: false, error: 'internal_error' }, status: :internal_server_error
  end
end
