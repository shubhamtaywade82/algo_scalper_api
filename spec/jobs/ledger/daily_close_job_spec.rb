# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ledger::DailyCloseJob do
  describe '#perform' do
    let(:trading_date) { Time.zone.today }
    let(:snapshot_data) do
      {
        cash: BigDecimal('120000.00'),
        equity: BigDecimal('120000.00'),
        mtm: BigDecimal('0.00'),
        exposure: BigDecimal('0.00'),
        utilized: BigDecimal('0.00'),
        margin: 0,
        realized_pnl: BigDecimal('22000.00'),
        brokerage_expense: BigDecimal('2000.00'),
        source: 'ledger'
      }
    end

    before do
      allow(Ledger::Config).to receive(:enabled?).and_return(true)
      allow(Ledger::WalletReader).to receive(:snapshot).with(mode: :paper).and_return(snapshot_data)
      # Stub position trackers count cleanly without message chain
      scope = instance_double(ActiveRecord::Relation, count: 3)
      allow(PositionTracker).to receive(:paper).and_return(scope)
      allow(scope).to receive(:where).and_return(scope)
    end

    context 'when ledger config is disabled' do
      before do
        allow(Ledger::Config).to receive_messages(enabled?: false, shadow_mode?: false)
      end

      it 'does not create a PaperDailyWallet record' do
        expect { described_class.new.perform(trading_date: trading_date) }
          .not_to change(PaperDailyWallet, :count)
      end
    end

    context 'when ledger config is enabled or shadow_mode is true' do
      before do
        allow(Ledger::Config).to receive(:enabled?).and_return(true)
      end

      it 'creates or updates the PaperDailyWallet record' do
        expect { described_class.new.perform(trading_date: trading_date) }
          .to change(PaperDailyWallet, :count).by(1)

        row = PaperDailyWallet.find_by(trading_date: trading_date)
        expect(row.attributes.symbolize_keys).to include(
          closing_cash: BigDecimal('120000.00'),
          gross_pnl: BigDecimal('22000.00'),
          net_pnl: BigDecimal('20000.00'),
          fees_total: BigDecimal('2000.00'),
          trades_count: 3
        )
      end

      it 'uses yesterday closing cash as opening cash when no prior row is found' do
        described_class.new.perform(trading_date: trading_date)
        row = PaperDailyWallet.find_by(trading_date: trading_date)
        expect(row.opening_cash).to eq(BigDecimal('100000.00'))
      end

      it 'uses yesterday closing cash as opening cash when prior row is present' do
        PaperDailyWallet.create!(
          trading_date: trading_date - 1.day,
          opening_cash: BigDecimal('100000.00'),
          closing_cash: BigDecimal('108159.25'),
          gross_pnl: BigDecimal('10159.25'),
          net_pnl: BigDecimal('8159.25'),
          fees_total: BigDecimal('2000.00')
        )

        described_class.new.perform(trading_date: trading_date)
        row = PaperDailyWallet.find_by(trading_date: trading_date)
        expect(row.opening_cash).to eq(BigDecimal('108159.25'))
        expect(row.max_equity).to eq(BigDecimal('120000.00'))
        expect(row.min_equity).to eq(BigDecimal('108159.25'))
      end
    end
  end
end
