# frozen_string_literal: true

module Api
  class FundsController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_dashboard_token!

    def index
      paper_mode = paper_enabled?

      if paper_mode
        render json: paper_snapshot
      else
        render json: live_snapshot
      end
    end

    def add
      return render json: { error: 'only_supported_in_paper_mode', message: 'Funds can only be added in paper trading mode' }, status: :bad_request unless paper_enabled?

      amount = BigDecimal(params[:amount].to_s)
      return render json: { error: 'invalid_amount', message: 'Amount must be positive' }, status: :unprocessable_content unless amount.positive?

      Ledger::Seeder.ensure_ready!
      Ledger::PostingService.post!(
        idempotency_key: "funds:add:#{SecureRandom.uuid}",
        event_type: 'fund_adjustment',
        mode: :paper,
        trading_date: Time.zone.today,
        meta: { note: 'Dashboard add funds' },
        lines: [
          { account_code: 'cash', debit: amount },
          { account_code: 'opening_equity', credit: amount }
        ]
      )
      ActionCable.server.broadcast("funds", { type: "funds_changed", timestamp: Time.current.iso8601 })
      render json: { success: true, cash: paper_snapshot[:cash] }
    rescue StandardError => e
      Rails.logger.error("[Api::FundsController] add failed: #{e.message}")
      render json: { error: 'add_failed', message: e.message }, status: :internal_server_error
    end

    def withdraw
      return render json: { error: 'only_supported_in_paper_mode', message: 'Funds can only be withdrawn in paper trading mode' }, status: :bad_request unless paper_enabled?

      amount = BigDecimal(params[:amount].to_s)
      return render json: { error: 'invalid_amount', message: 'Amount must be positive' }, status: :unprocessable_content unless amount.positive?

      Ledger::Seeder.ensure_ready!
      snapshot = Ledger::WalletReader.snapshot(mode: :paper)
      return render json: { error: 'insufficient_funds', message: "Available cash: #{snapshot[:cash].to_f}" }, status: :unprocessable_content if amount > snapshot[:cash]

      Ledger::PostingService.post!(
        idempotency_key: "funds:withdraw:#{SecureRandom.uuid}",
        event_type: 'fund_adjustment',
        mode: :paper,
        trading_date: Time.zone.today,
        meta: { note: 'Dashboard withdraw funds' },
        lines: [
          { account_code: 'cash', credit: amount },
          { account_code: 'opening_equity', debit: amount }
        ]
      )
      ActionCable.server.broadcast("funds", { type: "funds_changed", timestamp: Time.current.iso8601 })
      render json: { success: true, cash: paper_snapshot[:cash] }
    rescue StandardError => e
      Rails.logger.error("[Api::FundsController] withdraw failed: #{e.message}")
      render json: { error: 'withdraw_failed', message: e.message }, status: :internal_server_error
    end

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

    def live_snapshot
      funds = DhanHQ::Models::Funds.fetch
      # Calculate active MTM from live position trackers if any
      mtm = begin
        Positions::ActivePositionsCache.instance.active_trackers.sum { |t| t.unrealized_pnl.to_f }
      rescue StandardError
        0.0
      end

      cash = funds.available_balance.to_f
      equity = funds.sod_limit.to_f
      margin_used = funds.utilized_amount.to_f
      exposure = (funds.collateral_amount.to_f + funds.receiveable_amount.to_f)
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
      Rails.logger.error("[Api::FundsController] Error fetching live funds: #{e.message}")
      { cash: 0.0, equity: 0.0, mtm: 0.0, exposure: 0.0, margin_used: 0.0, available: 0.0, total_collateral: 0.0, day_pnl: 0.0, error: e.message }
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
