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
      create_list(:position_tracker, 3, :exited, :paper, exited_at: trading_date.noon)
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

      it 'creates or updates the PaperDailyWallet record, tagged mode: paper' do
        expect { described_class.new.perform(trading_date: trading_date) }
          .to change(PaperDailyWallet, :count).by(1)

        row = PaperDailyWallet.find_by(trading_date: trading_date, mode: 'paper')
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
        row = PaperDailyWallet.find_by(trading_date: trading_date, mode: 'paper')
        expect(row.opening_cash).to eq(BigDecimal('100000.00'))
      end

      it 'uses yesterday closing cash as opening cash when prior row is present' do
        PaperDailyWallet.create!(
          trading_date: trading_date - 1.day,
          mode: 'paper',
          opening_cash: BigDecimal('100000.00'),
          closing_cash: BigDecimal('108159.25'),
          gross_pnl: BigDecimal('10159.25'),
          net_pnl: BigDecimal('8159.25'),
          fees_total: BigDecimal('2000.00')
        )

        described_class.new.perform(trading_date: trading_date)
        row = PaperDailyWallet.find_by(trading_date: trading_date, mode: 'paper')
        expect(row.opening_cash).to eq(BigDecimal('108159.25'))
        expect(row.max_equity).to eq(BigDecimal('120000.00'))
        expect(row.min_equity).to eq(BigDecimal('108159.25'))
      end
    end

    context 'mode: :live' do
      before do
        PositionTracker.paper.delete_all
        create(:position_tracker, :exited, exited_at: trading_date.noon, last_pnl_rupees: BigDecimal('1000.00'), charges_rupees: BigDecimal('50.00'))
        create(:position_tracker, :exited, exited_at: trading_date.noon, last_pnl_rupees: BigDecimal('-200.00'), charges_rupees: BigDecimal('30.00'))
      end

      it 'derives KPIs directly from live PositionTracker rows, not the paper wallet snapshot' do
        expect(Ledger::WalletReader).not_to receive(:snapshot)

        described_class.new.perform(trading_date: trading_date, mode: :live)

        row = PaperDailyWallet.find_by(trading_date: trading_date, mode: 'live')
        expect(row.gross_pnl).to eq(BigDecimal('800.00'))
        expect(row.fees_total).to eq(BigDecimal('80.00'))
        expect(row.net_pnl).to eq(BigDecimal('720.00'))
        expect(row.trades_count).to eq(2)
      end

      it 'stores win_rate/profit_factor/expectancy in meta' do
        described_class.new.perform(trading_date: trading_date, mode: :live)

        row = PaperDailyWallet.find_by(trading_date: trading_date, mode: 'live')
        expect(row.meta['win_rate_percent']).to eq(50.0)
        expect(row.meta['source']).to eq('live_position_trackers')
      end

      it 'creates a separate row from the paper-mode rollup for the same date, not a conflicting one' do
        described_class.new.perform(trading_date: trading_date, mode: :paper)

        expect { described_class.new.perform(trading_date: trading_date, mode: :live) }
          .to change(PaperDailyWallet, :count).by(1)
      end
    end
  end
end
