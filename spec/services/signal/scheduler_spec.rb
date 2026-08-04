# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Signal::Scheduler do
  let(:index_cfg) { { key: 'NIFTY', segment: 'IDX_I', sid: '13' } }
  let(:scheduler) { described_class.new(period: 1) }

  describe '#process_index' do
    before do
      allow(scheduler).to receive(:evaluate_supertrend_signal).and_return(signal)
      allow(scheduler).to receive(:process_signal)
    end

    context 'when evaluate_supertrend_signal returns nil' do
      let(:signal) { nil }

      it 'does not invoke process_signal' do
        scheduler.send(:process_index, index_cfg)
        expect(scheduler).not_to have_received(:process_signal)
      end
    end

    context 'when a signal is returned' do
      let(:signal) do
        { segment: 'NSE_FNO', security_id: '123', meta: { candidate_symbol: 'TEST', direction: :bullish } }
      end

      it 'passes signal to process_signal' do
        scheduler.send(:process_index, index_cfg)
        expect(scheduler).to have_received(:process_signal).with(index_cfg, signal)
      end
    end
  end

  describe '#process_signal' do
    let(:signal) do
      {
        segment: 'NSE_FNO',
        security_id: 12_345,
        reason: 'OI buildup',
        meta: { candidate_symbol: 'NIFTY24FEB20000CE', lot_size: 50, multiplier: 1 }
      }
    end

    before do
      allow(Entries::EntryGuard).to receive(:try_enter).and_return(true)
    end

    it 'calls EntryGuard with correct parameters' do
      scheduler.send(:process_signal, index_cfg, signal)

      expect(Entries::EntryGuard).to have_received(:try_enter).with(
        index_cfg: index_cfg,
        pick: hash_including(
          segment: 'NSE_FNO',
          security_id: 12_345,
          symbol: 'NIFTY24FEB20000CE',
          lot_size: 50
        ),
        direction: :bullish,
        scale_multiplier: 1
      )
    end
  end
end
