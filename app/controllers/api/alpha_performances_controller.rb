# frozen_string_literal: true

module Api
  # The dashboard's Alpha page is a view into the Strategies::Manager plugin platform
  # (Strategies::Record/Signal); there is no separate alpha signal engine.
  class AlphaPerformancesController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_dashboard_token!

    # GET /api/alpha/performance
    def show
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
      Rails.logger.error("[AlphaPerformancesController] error: #{e.class} - #{e.message}")
      render json: { error: "internal_error" }, status: :internal_server_error
    end

    private

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
