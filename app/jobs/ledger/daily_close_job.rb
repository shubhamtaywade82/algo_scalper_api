# frozen_string_literal: true

module Ledger
  class DailyCloseJob < ApplicationJob
    queue_as :background

    def perform(trading_date: Time.zone.today)
      return unless Config.enabled? || Config.shadow_mode?

      snapshot = WalletReader.snapshot(mode: :paper)
      row = PaperDailyWallet.find_or_initialize_by(trading_date: trading_date)
      row.assign_attributes(
        opening_cash: row.opening_cash.presence || snapshot[:cash],
        closing_cash: snapshot[:cash],
        gross_pnl: snapshot[:realized_pnl],
        net_pnl: snapshot[:realized_pnl] - snapshot[:brokerage_expense],
        fees_total: snapshot[:brokerage_expense],
        trades_count: PositionTracker.paper.where(exited_at: trading_date.all_day).count,
        meta: { source: 'ledger_daily_close', equity: snapshot[:equity], mtm: snapshot[:mtm] }
      )
      row.save!
    rescue StandardError => e
      Rails.logger.error("[Ledger::DailyCloseJob] #{e.class} - #{e.message}")
    end
  end
end
