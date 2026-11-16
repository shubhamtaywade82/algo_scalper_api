# frozen_string_literal: true

module Api
  class FundWithdrawalsController < ApplicationController
    include Api::TokenAuthenticatable
    include Api::PaperFunds

    before_action :authenticate_dashboard_token!

    # POST /api/funds/withdrawals { amount } — paper mode only
    def create
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
      Rails.logger.error("[Api::FundWithdrawalsController] withdrawal failed: #{e.message}")
      render json: { error: 'withdraw_failed', message: e.message }, status: :internal_server_error
    end
  end
end
