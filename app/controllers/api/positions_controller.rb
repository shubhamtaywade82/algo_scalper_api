# frozen_string_literal: true

module Api
  class PositionsController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_dashboard_token!

    ALLOWED_SORT_COLS = %w[exited_at last_pnl_rupees entry_price symbol side quantity].freeze

    def index
      render json: {
        open: open_positions,
        closed: closed_positions,
        available_dates: available_dates,
        summary: filter_summary
      }
    end

    def show
      tracker = PositionTracker.includes(:watchable, :instrument, :meta_snapshot).find_by(id: params[:id])
      return render json: { error: "not_found" }, status: :not_found unless tracker

      render json: Positions::Serializer.detail(tracker)
    end

    def close
      outcome = Positions::ManualCloseService.call(tracker_id: params[:id])
      render json: outcome[:json], status: outcome[:status]
    end

    private

    def open_positions
      PositionTracker.active.includes(:watchable, :instrument).map { |tracker| serialize_open(tracker) }
    end

    def closed_positions
      today = Time.zone.today
      PositionTracker.exited
                     .where(exited_at: today.all_day)
                     .includes(:watchable, :instrument)
                     .order(exited_at: :desc)
                     .map { |tracker| serialize_closed(tracker) }
    end

    # Unique trade dates, newest first. Capped at 90 days for the dropdown.
    def available_dates
      PositionTracker
        .exited
        .where.not(exited_at: nil)
        .group(Arel.sql("DATE(exited_at)"))
        .order(Arel.sql("DATE(exited_at) DESC"))
        .limit(90)
        .pluck(Arel.sql("DATE(exited_at)"))
        .map(&:to_s)
    rescue StandardError
      [Positions::IstScope.today_start.to_date.to_s]
    end

    def serialize_closed(tracker)
      entry = tracker.entry_price.to_f
      exit_p = tracker.exit_price.to_f

      base_attributes(tracker).merge(
        entry_price: entry.round(2),
        exit_price: exit_p.round(2),
        pnl: tracker.last_pnl_rupees.to_f.round(2),
        pnl_pct: pnl_pct(entry, exit_p),
        hwm_pnl: tracker.high_water_mark_pnl.to_f.round(2),
        exit_reason: tracker.exit_reason || tracker.meta&.dig('exit_reason'),
        exited_at: tracker.exited_at&.iso8601
      )
    end

    def filter_date
      @filter_date ||= Positions::IstScope.today_start.to_date
    end

    def assign_filter_date!
      if params[:date].blank?
        @filter_date = Positions::IstScope.today_start.to_date
        return
      end

      (((current - entry) / entry) * 100).round(2)
    end
  end
end
