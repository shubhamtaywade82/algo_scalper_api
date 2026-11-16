# frozen_string_literal: true

require 'csv'

module Api
  # GET /api/reports/export(?format=csv)
  class ReportExportsController < ApplicationController
    include Api::TokenAuthenticatable
    include Api::ReportDateRange

    before_action :authenticate_dashboard_token!

    def show
      scope = date_filtered_scope(PositionTracker.exited.includes(:watchable, :instrument).order(exited_at: :desc))

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
