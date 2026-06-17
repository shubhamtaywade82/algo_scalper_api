# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ledger do
  before do
    Ledger::Seeder.seed_accounts!
    Ledger::Seeder.seed_opening_balance!
  end

  describe Ledger::PostingService do
    describe '.post!' do
      it 'creates a balanced journal entry' do
        entry = described_class.post!(
          idempotency_key: 'test:balanced',
          event_type: 'test',
          mode: :paper,
          lines: [
            { account_code: 'cash', debit: 100 },
            { account_code: 'opening_equity', credit: 100 }
          ]
        )

        expect(entry.ledger_postings.count).to eq(2)
        expect(entry.ledger_postings.sum(:debit)).to eq(entry.ledger_postings.sum(:credit))
      end

      it 'is idempotent for the same key' do
        first = described_class.post!(
          idempotency_key: 'test:idempotent',
          event_type: 'test',
          mode: :paper,
          lines: [
            { account_code: 'cash', debit: 50 },
            { account_code: 'opening_equity', credit: 50 }
          ]
        )
        second = described_class.post!(
          idempotency_key: 'test:idempotent',
          event_type: 'test',
          mode: :paper,
          lines: [
            { account_code: 'cash', debit: 50 },
            { account_code: 'opening_equity', credit: 50 }
          ]
        )

        expect(second.id).to eq(first.id)
        expect(LedgerJournalEntry.where(idempotency_key: 'test:idempotent').count).to eq(1)
      end
    end
  end

  describe Ledger::EntryPoster do
    let(:tracker) do
      create(:position_tracker, :paper, segment: 'NSE_FNO', quantity: 10, entry_price: 100.0, avg_price: 100.0)
    end

    before do
      allow(AlgoConfig).to receive(:fetch).and_return(
        paper_trading: { enabled: true, balance: 100_000 },
        ledger: { enabled: false, shadow_mode: true, block_negative_cash: true },
        broker_fees: { enabled: true, fee_per_order: 20 }
      )
    end

    it 'posts entry fill journals' do
      described_class.post!(tracker: tracker, fill_price: 100, quantity: 10, order_no: tracker.order_no)

      cash = LedgerAccount.fetch!('cash')
      deployed = LedgerAccount.fetch!('premium_deployed')
      expect(deployed.balance_cache.to_d).to eq(1000)
      expect(cash.balance_cache.to_d).to eq(100_000 - 1000 - 20)
    end
  end

  describe Ledger::ExitPoster do
    let(:tracker) do
      create(:position_tracker, :paper, :exited, segment: 'NSE_FNO', quantity: 10, entry_price: 100.0,
                                                 avg_price: 100.0, exit_price: 110.0)
    end

    before do
      allow(AlgoConfig).to receive(:fetch).and_return(
        paper_trading: { enabled: true, balance: 100_000 },
        ledger: { enabled: false, shadow_mode: true },
        broker_fees: { enabled: true, fee_per_order: 20 }
      )
      Ledger::EntryPoster.post!(tracker: tracker, fill_price: 100, quantity: 10, order_no: tracker.order_no)
    end

    it 'posts exit fill journals with profit' do
      described_class.post!(tracker: tracker, exit_price: 110)

      realized = LedgerAccount.fetch!('realized_pnl')
      cash = LedgerAccount.fetch!('cash')
      expect(realized.balance_cache.to_d).to eq(100)
      expect(cash.balance_cache.to_d).to be > 98_000
    end
  end
end
