# frozen_string_literal: true

module Api
  class EquityCurveController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_dashboard_token!

    # Built from exited trades' final P&L — the same source as Reports. The daily
    # wallet snapshots (PaperDailyWallet) recorded the drifted ledger cash cache and
    # showed ₹77k equity while trades + ledger postings both say ₹1.03L.
    def index
      date_from = parse_date(params[:date_from], 90.days.ago.to_date)
      date_to = parse_date(params[:date_to], Time.zone.today)

      render json: build_from_positions(date_from, date_to)
    end

    private

    def build_from_positions(date_from, date_to)
      daily_pnl = PositionTracker.exited
                                 .where(exited_at: date_from.beginning_of_day..date_to.end_of_day)
                                 .group("DATE(exited_at)")
                                 .sum(:last_pnl_rupees)
      return [] if daily_pnl.empty?

      equity = opening_equity(date_from)
      peak = equity

      daily_pnl.sort_by { |date, _| date }.map do |date, pnl|
        equity += pnl.to_f
        peak = [peak, equity].max
        {
          time: date.to_time.to_i,
          equity: equity.round(2),
          drawdown_pct: (((equity - peak) / peak) * 100).round(4),
          peak: peak.round(2)
        }
      end
    end

    # Ledger opening equity (the capital paper trading actually started with; the
    # paper_trading.balance setting can be changed afterwards) plus everything
    # realised before the window opens.
    def opening_equity(date_from)
      starting_balance = Ledger::WalletReader.account_balance('opening_equity').to_f
      starting_balance + PositionTracker.exited.where(exited_at: ...date_from.beginning_of_day).sum(:last_pnl_rupees).to_f
    end

    def parse_date(raw, default)
      return default if raw.blank?

      Date.parse(raw.to_s)
    rescue ArgumentError, TypeError
      default
    end
  end
end
