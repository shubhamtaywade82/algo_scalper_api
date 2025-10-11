# frozen_string_literal: true

module Api
  class HealthController < ApplicationController
    def show
      render json: {
        mode: AlgoConfig.mode,
        watchlist: WatchlistItem.where(active: true).count,
        active_positions: PositionTracker.where(status: PositionTracker::STATUSES[:active]).count,
        scheduler: scheduler_status
      }
    end

    private

    def scheduler_status
      Thread.list.any? { |thread| thread.name == "signal-scheduler" } ? "running" : "unknown"
    end
  end
end
