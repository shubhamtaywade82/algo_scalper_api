# frozen_string_literal: true

module Api
  # View into the Strategies::Manager plugin platform, framed as "alpha intelligence"
  # for the dashboard's Alpha page. This controller has no signal generation of its
  # own — it reads Strategies::Record/Signal, the same data the Strategies page uses.
  # The legacy scan/execute actions (backed by SignalEngine, an intentional no-op
  # stub since the platform migration) were removed rather than faked.
  class AlphaController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_dashboard_token!

    DIRECTION_BY_ACTION = { "buy_call" => "bullish", "buy_put" => "bearish" }.freeze
    STATUS_BY_OUTCOME = {
      "executed" => "entered",
      "blocked_by_guard" => "blocked",
      "ignored_hold" => "skipped",
      "shadow" => "skipped"
    }.freeze

    # GET /api/alpha/status
    def status
      limits = AlgoConfig.fetch[:risk_limits] || {}

      render json: {
        enabled: ::Strategies::Record.where(desired_status: "running").exists?,
        indices: %w[nifty banknifty sensex],
        strategies: ::Strategies::Record.order(:slug).pluck(:slug),
        risk_stats: Risk::LimitsGuard.current_stats,
        risk_limits: {
          daily_max_trades: limits[:daily_max_trades] || 10,
          max_consecutive_losses: limits[:max_consecutive_losses] || 3,
          max_open_positions: limits[:max_open_positions] || 3
        }
      }
    rescue StandardError => e
      Rails.logger.error("[AlphaController] status error: #{e.class} - #{e.message}")
      render json: { error: "internal_error" }, status: :internal_server_error
    end

    # GET /api/alpha/history
    def history
      signals = ::Strategies::Signal.includes(:strategy_record, position_tracker: :instrument)
        .order(emitted_at: :desc).limit(100)

      render json: signals.map { |s| serialize_signal(s) }
    rescue StandardError => e
      Rails.logger.error("[AlphaController] history error: #{e.class} - #{e.message}")
      render json: { error: "internal_error" }, status: :internal_server_error
    end

    # GET /api/alpha/performance
    def performance
      signals = ::Strategies::Signal.includes(:strategy_record, :position_tracker)
        .where(outcome: "executed")

      by_slug = signals.group_by { |s| s.strategy_record&.slug || "unknown" }
      pnl_stats = by_slug.transform_values { |sigs| pnl_stats_for(sigs) }

      render json: {
        by_source: pnl_stats,
        total_executed: signals.size,
        timestamp: Time.current.iso8601
      }
    rescue StandardError => e
      Rails.logger.error("[AlphaController] performance error: #{e.class} - #{e.message}")
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

    def pnl_stats_for(signals)
      trackers = signals.filter_map(&:position_tracker)
      count = signals.size
      total_pnl = trackers.sum { |t| t.last_pnl_rupees.to_f }
      wins = trackers.count { |t| t.last_pnl_rupees.to_f.positive? }

      {
        count: count,
        total_pnl: total_pnl.round(2),
        win_rate: count.positive? ? (wins.to_f / count * 100).round(1) : 0,
        avg_pnl: count.positive? ? (total_pnl / count).round(2) : 0
      }
    end
  end
end
