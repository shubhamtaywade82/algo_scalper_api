# frozen_string_literal: true

module Ledger
  class BalanceChecker
    class << self
      # Compares the cached account balances the wallet reads against balances
      # recomputed from postings (the source of truth). The previous "legacy wallet"
      # side was GatewayPaper#wallet_snapshot, which itself reads the ledger cache —
      # so drift was always 0 and a ₹26k cache drift went unnoticed.
      def compare_paper_wallet
        ledger = WalletReader.snapshot(mode: :paper)
        postings_cash = posted_balance('cash')
        postings_equity = (postings_cash + posted_balance('premium_deployed') + ledger[:mtm].to_d).round(2)

        {
          ledger_cash: ledger[:cash],
          postings_cash: postings_cash.round(2),
          cash_drift: (ledger[:cash].to_d - postings_cash).round(2),
          ledger_equity: ledger[:equity],
          postings_equity: postings_equity,
          equity_drift: (ledger[:equity].to_d - postings_equity).round(2),
          shadow_mode: Config.shadow_mode?,
          paper_enabled: Config.paper_enabled?
        }
      end

      # Asset-account balance (debit-normal) summed from postings.
      def posted_balance(code)
        postings = LedgerPosting.joins(:ledger_account).where(ledger_accounts: { code: code })
        postings.sum(:debit).to_d - postings.sum(:credit).to_d
      end
    end
  end
end
