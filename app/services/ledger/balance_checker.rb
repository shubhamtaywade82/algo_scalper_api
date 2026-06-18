# frozen_string_literal: true

module Ledger
  class BalanceChecker
    class << self
      def compare_paper_wallet
        ledger = WalletReader.snapshot(mode: :paper)
        legacy = legacy_wallet_snapshot

        {
          ledger_cash: ledger[:cash],
          legacy_cash: legacy[:cash],
          cash_drift: (ledger[:cash].to_d - legacy[:cash].to_d).round(2),
          ledger_equity: ledger[:equity],
          legacy_equity: legacy[:equity],
          equity_drift: (ledger[:equity].to_d - legacy[:equity].to_d).round(2),
          shadow_mode: Config.shadow_mode?,
          paper_enabled: Config.paper_enabled?
        }
      end

      private

      def legacy_wallet_snapshot
        gateway = Orders::GatewayPaper.new
        snapshot = gateway.send(:legacy_wallet_snapshot)
        snapshot.merge(source: 'legacy')
      end
    end
  end
end
