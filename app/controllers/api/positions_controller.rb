# frozen_string_literal: true

module Api
  class PositionsController < ApplicationController
    def index
      render json: {
        open: open_positions,
        closed: closed_positions
      }
    end

    private

    def open_positions
      PositionTracker
        .active
        .includes(:watchable, :instrument)
        .map { |tracker| Positions::Serializer.open(tracker) }
    end

    def closed_positions
      today = Time.zone.today
      PositionTracker.exited
                     .where(exited_at: today.all_day)
                     .includes(:watchable, :instrument)
                     .order(exited_at: :desc)
                     .map { |tracker| Positions::Serializer.closed(tracker) }
    end
  end
end
