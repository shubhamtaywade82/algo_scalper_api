# frozen_string_literal: true

module Ledger
  class WalletReader
    class << self
      def snapshot(mode: :paper)
        Seeder.ensure_ready!

        cash = account_balance('cash')
        utilized = account_balance('premium_deployed')
        mtm = unrealized_rupees(mode)
        equity = (cash + utilized + mtm).round(2)

        {
          cash: cash.round(2),
          equity: equity,
          mtm: mtm.round(2),
          exposure: utilized.round(2),
          utilized: utilized.round(2),
          margin: 0,
          realized_pnl: account_balance('realized_pnl').round(2),
          brokerage_expense: account_balance('brokerage_expense').round(2),
          source: 'ledger'
        }
      end

      def account_balance(code)
        LedgerAccount.fetch!(code).balance_cache.to_d
      rescue ActiveRecord::RecordNotFound
        BigDecimal(0)
      end

      private

      def unrealized_rupees(mode)
        scope = if mode.to_s == 'paper'
                  PositionTracker.paper.active
                else
                  PositionTracker.live.active
                end
        scope.sum { |tracker| tracker.current_pnl_rupees.to_f }
      end
    end
  end
end
