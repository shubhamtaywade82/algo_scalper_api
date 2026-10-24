# frozen_string_literal: true

module Ledger
  class Seeder
    ACCOUNTS = [
      { code: 'cash', name: 'Cash', account_type: 'asset' },
      { code: 'premium_deployed', name: 'Premium Deployed', account_type: 'asset' },
      { code: 'margin_blocked', name: 'Margin Blocked', account_type: 'asset' },
      { code: 'premium_written', name: 'Premium Written', account_type: 'equity' },
      { code: 'brokerage_expense', name: 'Brokerage Expense', account_type: 'expense' },
      { code: 'realized_pnl', name: 'Realized PnL', account_type: 'income' },
      { code: 'opening_equity', name: 'Opening Equity', account_type: 'equity' }
    ].freeze

    class << self
      def seed_accounts!
        ACCOUNTS.each do |attrs|
          LedgerAccount.find_or_create_by!(code: attrs[:code]) do |account|
            account.name = attrs[:name]
            account.account_type = attrs[:account_type]
            account.currency = 'INR'
            account.balance_cache = 0
          end
        end
      end

      def seed_opening_balance!
        seed_accounts!
        amount = opening_balance_amount
        return if amount <= 0

        PostingService.post!(
          idempotency_key: 'opening_balance:paper',
          event_type: 'opening_balance',
          mode: :paper,
          trading_date: Time.zone.today,
          meta: { source: 'seeder' },
          lines: [
            { account_code: 'cash', debit: amount },
            { account_code: 'opening_equity', credit: amount }
          ]
        )
      end

      def ensure_ready!
        seed_accounts!
        cash = LedgerAccount.fetch!('cash')
        return cash if cash.balance_cache.to_d.positive?

        seed_opening_balance!
        cash.reload
      end

      private

      def opening_balance_amount
        BigDecimal((AlgoConfig.fetch.dig(:paper_trading, :balance) || 100_000).to_s)
      rescue StandardError
        BigDecimal('100000')
      end
    end
  end
end
