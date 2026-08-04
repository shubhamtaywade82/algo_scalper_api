# frozen_string_literal: true

module Api
  class PositionsController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_dashboard_token!
    before_action :assign_filter_date!, only: :index

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
      PositionTracker
        .active
        .includes(:watchable, :instrument)
        .map { |tracker| Positions::Serializer.open(tracker) }
    end

    def closed_positions
      scope = PositionTracker.exited.includes(:watchable, :instrument)

      # Date filter (defaults to today)
      scope = scope.where(exited_at: filter_date.all_day)

      if params[:index_key].present?
        scope = scope.by_index_key(params[:index_key].upcase)
      end

      # Option type: CE or PE suffix on symbol
      if params[:option_type].present?
        type = params[:option_type].upcase
        scope = scope.where("symbol ILIKE ?", "%#{type}") if %w[CE PE].include?(type)
      end

      # Outcome filter based on last_pnl_rupees
      case params[:outcome]
      when "profit"
        scope = scope.where("last_pnl_rupees > 0")
      when "loss"
        scope = scope.where("last_pnl_rupees < 0")
      when "breakeven"
        scope = scope.where("last_pnl_rupees BETWEEN -1 AND 1")
      end

      # Side filter (BUY/SELL)
      scope = scope.where(side: params[:side].upcase) if params[:side].present?

      # Sorting
      col = ALLOWED_SORT_COLS.include?(params[:sort_by]) ? params[:sort_by] : "exited_at"
      dir = params[:sort_dir] == "asc" ? :asc : :desc
      scope = scope.order(col => dir)

      scope.map { |tracker| Positions::Serializer.closed(tracker) }
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

    # Day-level summary (ignores secondary filters — always for the full selected date).
    def filter_summary
      base = PositionTracker.exited.where(exited_at: filter_date.all_day)
      {
        date: filter_date.to_s,
        total: base.count,
        profit_count: base.where("last_pnl_rupees > 0").count,
        loss_count: base.where("last_pnl_rupees < 0").count,
        total_pnl: base.sum(:last_pnl_rupees).to_f.round(2)
      }
    end

    def filter_date
      @filter_date ||= Positions::IstScope.today_start.to_date
    end

    def assign_filter_date!
      if params[:date].blank?
        @filter_date = Positions::IstScope.today_start.to_date
        return
      end

      @filter_date = Date.parse(params[:date].to_s)
    rescue ArgumentError, TypeError => e
      Rails.logger.warn(
        "[PositionsController] invalid date param=#{params[:date].inspect}: #{e.class} - #{e.message}"
      )
      render json: { error: 'invalid_date', message: 'Use an ISO date (YYYY-MM-DD)' },
             status: :unprocessable_content
    end
  end
end
