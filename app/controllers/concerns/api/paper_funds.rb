# frozen_string_literal: true

module Api
  # Paper-wallet snapshot shared by the funds read and the paper deposit/withdrawal endpoints.
  module PaperFunds
    extend ActiveSupport::Concern

    private

    def paper_enabled?
      AlgoConfig.fetch.dig(:paper_trading, :enabled) == true
    rescue StandardError
      false
    end

    def paper_snapshot
      Ledger::Seeder.ensure_ready!
      snapshot = Ledger::WalletReader.snapshot(mode: :paper)
      cash = snapshot[:cash].to_f
      equity = snapshot[:equity].to_f
      mtm = snapshot[:mtm].to_f
      exposure = snapshot[:exposure].to_f
      margin_used = snapshot[:utilized].to_f
      available = equity - margin_used
      total_collateral = cash + mtm
      day_pnl = compute_day_pnl

      {
        cash: cash,
        equity: equity,
        mtm: mtm,
        exposure: exposure,
        margin_used: margin_used,
        available: available,
        total_collateral: total_collateral,
        day_pnl: day_pnl
      }
    rescue StandardError => e
      Rails.logger.error("[Api::FundsController] Ledger snapshot error: #{e.message}")
      { cash: 0.0, equity: 0.0, mtm: 0.0, exposure: 0.0, margin_used: 0.0, available: 0.0, total_collateral: 0.0, day_pnl: 0.0 }
    end

    def compute_day_pnl
      today_start = Time.zone.today.beginning_of_day
      closed_today = PositionTracker.exited.where(exited_at: today_start..)
      closed_today.sum(:last_pnl_rupees).to_f
    rescue StandardError
      0.0
    end
  end
end
