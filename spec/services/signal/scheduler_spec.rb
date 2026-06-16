# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Signal::Scheduler do
  let(:index_cfg) { { key: 'NIFTY', segment: 'IDX_I', sid: '13' } }
  let(:scheduler) { described_class.new(period: 1) }

  describe '#process_index' do
    before do
      allow(Signal::Engine).to receive(:run_for)
    end

    it 'delegates to Signal::Engine.run_for with regime state' do
      summary = Signal::CycleSummary.new(index_key: 'NIFTY').block!('supertrend_none')
      allow(Signal::Engine).to receive(:run_for).and_return(summary)
      allow(Rails.logger).to receive(:info)

      scheduler.send(:process_index, index_cfg)

      expect(Signal::Engine).to have_received(:run_for).with(
        index_cfg,
        regime_state: instance_of(Market::RegimeState)
      )
      expect(Rails.logger).to have_received(:info).with(summary.log_line)
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
          lot_size: 50,
          ltp: nil
        ),
        direction: :bullish,
        scale_multiplier: 1,
        permission: :scale_ready
      )
    end
  end
end
