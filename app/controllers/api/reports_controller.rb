# frozen_string_literal: true

require 'csv'

module Api
  class ReportsController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_dashboard_token!

    def index
      render json: {
        success: true,
        message: "Reports index endpoints available"
      }
    end

    def pnl
      closed_trackers = PositionTracker.exited
      total_trades = closed_trackers.count
      winning_trades = closed_trackers.where("last_pnl_rupees > 0").count
      losing_trades = closed_trackers.where("last_pnl_rupees <= 0").count

      net_pnl = closed_trackers.sum(:last_pnl_rupees).to_f
      win_rate = total_trades.positive? ? (winning_trades.to_f / total_trades * 100).round(2) : 0.0

      gross_profit = closed_trackers.where("last_pnl_rupees > 0").sum(:last_pnl_rupees).to_f
      gross_loss = closed_trackers.where("last_pnl_rupees <= 0").sum(:last_pnl_rupees).to_f

      render json: {
        success: true,
        summary: {
          total_trades: total_trades,
          winning_trades: winning_trades,
          losing_trades: losing_trades,
          win_rate_percent: win_rate,
          net_pnl: net_pnl,
          gross_profit: gross_profit,
          gross_loss: gross_loss,
          total_brokerage: total_trades * 40.0
        }
      }
    end

    def trades
      scope = PositionTracker.exited.includes(:watchable, :instrument)
                             .order(exited_at: :desc)

      scope = scope.where(exited_at: params[:since].presence&.to_time..) if params[:since].present?
      scope = scope.where(exited_at: ..params[:until].presence&.to_time) if params[:until].present?
      scope = scope.where(side: params[:side].upcase) if params[:side].present?

      page = [params[:page].to_i, 1].max
      per_page = [params[:per_page].to_i, 1].max
      per_page = [per_page, 100].min

      total = scope.count
      total_pages = [1, (total.to_f / per_page).ceil].max
      page = [page, total_pages].min
      offset = (page - 1) * per_page

      trades = scope.offset(offset).limit(per_page).map do |tracker|
        Positions::Serializer.closed(tracker)
      end

      render json: {
        success: true,
        trades: trades,
        meta: { total: total, page: page, per_page: per_page, pages: total_pages }
      }
    end

    def performance
      closed_trackers = PositionTracker.exited

      total = closed_trackers.count
      wins = closed_trackers.where("last_pnl_rupees > 0").count
      losses = closed_trackers.where("last_pnl_rupees <= 0").count
      win_rate = total.positive? ? (wins.to_f / total * 100).round(2) : 0.0

      net_pnl = closed_trackers.sum(:last_pnl_rupees).to_f
      avg_win = wins.positive? ? (closed_trackers.where("last_pnl_rupees > 0").sum(:last_pnl_rupees).to_f / wins).round(2) : 0.0
      avg_loss = losses.positive? ? (closed_trackers.where("last_pnl_rupees <= 0").sum(:last_pnl_rupees).to_f / losses).round(2) : 0.0

      max_win = closed_trackers.maximum(:last_pnl_rupees).to_f
      max_loss = closed_trackers.minimum(:last_pnl_rupees).to_f

      profit_factor = if avg_loss.negative?
                        (avg_win / avg_loss.abs).round(2)
                      else
                        0.0
                      end

      # Daily breakdown (last 30 days)
      daily = closed_trackers.where(exited_at: 30.days.ago..)
                             .group(Arel.sql("DATE(exited_at)"))
                             .pluck(Arel.sql("DATE(exited_at)"), Arel.sql("SUM(last_pnl_rupees)"))
                             .map { |date, pnl| { date: date.to_s, pnl: pnl.to_f.round(2) } }
                             .sort_by { |d| d[:date] }

      render json: {
        success: true,
        summary: {
          total_trades: total,
          wins: wins,
          losses: losses,
          win_rate_percent: win_rate,
          net_pnl: net_pnl,
          avg_win: avg_win,
          avg_loss: avg_loss,
          max_win: max_win,
          max_loss: max_loss,
          profit_factor: profit_factor,
          expectancy: total.positive? ? (net_pnl / total).round(2) : 0.0
        },
        daily: daily
      }
    end

    def export
      scope = PositionTracker.exited.includes(:watchable, :instrument)
                             .order(exited_at: :desc)

      scope = scope.where(exited_at: params[:since].presence&.to_time..) if params[:since].present?
      scope = scope.where(exited_at: ..params[:until].presence&.to_time) if params[:until].present?

      format = params[:format].to_s.downcase == 'csv' ? :csv : :json

      trades = scope.map do |tracker|
        Positions::Serializer.closed(tracker)
      end

      if format == :csv
        csv_string = CSV.generate do |csv|
          csv << %w[ID Symbol Side Quantity Entry Exit PnL PnL% ExitReason ExitedAt]
          trades.each do |t|
            csv << [t[:id], t[:symbol], t[:side], t[:quantity],
                    t[:entry_price], t[:exit_price], t[:pnl], t[:pnl_pct],
                    t[:exit_reason], t[:exited_at]]
          end
        end
        send_data csv_string, filename: "trade_export_#{Time.zone.today}.csv", type: 'text/csv'
      else
        render json: { success: true, trades: trades, count: trades.size }
      end
    end
  end
end
