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

    context 'with a short position' do
      let(:tracker) do
        create(:position_tracker, :paper, segment: 'NSE_FNO', quantity: 10, entry_price: 100.0, avg_price: 100.0,
                                          position_side: 'short', margin_required: 8000.0)
      end

      it 'credits cash for premium received and blocks margin out of free cash' do
        journal = described_class.post!(tracker: tracker, fill_price: 100, quantity: 10, order_no: tracker.order_no)

        expect(journal.ledger_postings.sum(:debit)).to eq(journal.ledger_postings.sum(:credit))

        cash = LedgerAccount.fetch!('cash')
        margin_blocked = LedgerAccount.fetch!('margin_blocked')
        premium_written = LedgerAccount.fetch!('premium_written')
        expect(margin_blocked.balance_cache.to_d).to eq(8000)
        expect(premium_written.balance_cache.to_d).to eq(1000)
        # +1000 premium received, -8000 margin locked, -20 fee
        expect(cash.balance_cache.to_d).to eq(100_000 + 1000 - 8000 - 20)
      end
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

    context 'with a short position that closes at a profit' do
      let(:tracker) do
        create(:position_tracker, :paper, :exited, segment: 'NSE_FNO', quantity: 10, entry_price: 100.0,
                                                   avg_price: 100.0, exit_price: 40.0,
                                                   position_side: 'short', margin_required: 8000.0)
      end

      before do
        Ledger::EntryPoster.post!(tracker: tracker, fill_price: 100, quantity: 10, order_no: tracker.order_no)
      end

      it 'releases margin, clears the written premium, and posts the correct gain' do
        journal = described_class.post!(tracker: tracker, exit_price: 40)

        expect(journal.ledger_postings.sum(:debit)).to eq(journal.ledger_postings.sum(:credit))

        realized = LedgerAccount.fetch!('realized_pnl')
        margin_blocked = LedgerAccount.fetch!('margin_blocked')
        premium_written = LedgerAccount.fetch!('premium_written')
        # gain = premium_received(1000) - buyback_cost(400) = 600
        expect(realized.balance_cache.to_d).to eq(600)
        expect(margin_blocked.balance_cache.to_d).to eq(0)
        expect(premium_written.balance_cache.to_d).to eq(0)
      end

      it 'reconciles cash back to opening balance plus the round trip P&L' do
        described_class.post!(tracker: tracker, exit_price: 40)

        cash = LedgerAccount.fetch!('cash')
        brokerage = LedgerAccount.fetch!('brokerage_expense')
        realized = LedgerAccount.fetch!('realized_pnl')
        expect(cash.balance_cache.to_d).to eq(100_000 + realized.balance_cache.to_d - brokerage.balance_cache.to_d)
      end
    end
  end
end
