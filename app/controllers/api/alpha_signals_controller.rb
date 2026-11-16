# frozen_string_literal: true

module Api
  # The dashboard's Alpha page is a view into the Strategies::Manager plugin platform
  # (Strategies::Record/Signal); there is no separate alpha signal engine.
  class AlphaSignalsController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_dashboard_token!

    DIRECTION_BY_ACTION = { "buy_call" => "bullish", "buy_put" => "bearish" }.freeze
    STATUS_BY_OUTCOME = {
      "executed" => "entered",
      "blocked_by_guard" => "blocked",
      "ignored_hold" => "skipped",
      "shadow" => "skipped"
    }.freeze

    # GET /api/alpha/history
    def index
      signals = ::Strategies::Signal.includes(:strategy_record, position_tracker: :instrument)
                                    .order(emitted_at: :desc).limit(100)

      render json: signals.map { |s| serialize_signal(s) }
    rescue StandardError => e
      Rails.logger.error("[AlphaSignalsController] error: #{e.class} - #{e.message}")
      render json: { error: "internal_error" }, status: :internal_server_error
    end

    private

    def serialize_signal(signal)
      tracker = signal.position_tracker

      {
        id: signal.id,
        created_at: signal.emitted_at&.iso8601,
        alpha_source: signal.strategy_record&.slug,
        index_key: signal.instrument_key,
        direction: DIRECTION_BY_ACTION[signal.action],
        confidence: signal.confidence&.to_f,
        status: STATUS_BY_OUTCOME[signal.outcome] || signal.outcome,
        strike_price: tracker&.atm_strike&.to_f,
        pnl: tracker&.last_pnl_rupees&.to_f,
        symbol: tracker&.symbol
      }
    end
  end
end
