# frozen_string_literal: true

module Api
  # GET /api/ledger/balance — paper wallet, account balances and reconciliation.
  class LedgerBalancesController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_dashboard_token!

    def show
      Ledger::Seeder.ensure_ready!
      snapshot = Ledger::WalletReader.snapshot(mode: :paper)
      accounts = LedgerAccount.order(:code).map do |account|
        {
          code: account.code,
          name: account.name,
          account_type: account.account_type,
          balance: account.balance_cache.to_f
        }
      end

      render json: {
        success: true,
        wallet: snapshot,
        accounts: accounts,
        reconciliation: Ledger::BalanceChecker.compare_paper_wallet,
        config: {
          enabled: Ledger::Config.enabled?,
          paper_enabled: Ledger::Config.paper_enabled?,
          shadow_mode: Ledger::Config.shadow_mode?
        }
      }
    end
  end
end
