# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Orders::MfeExitEngine do
  let(:tracker) { instance_double('PositionTracker', symbol: symbol, entry_price: 100.0, highest_price: 100.0, meta: {}) }
  let(:symbol) { 'NIFTY24MAR22000CE' }
  let(:ltp) { 100.0 }
  let(:engine) { described_class.new(position: tracker, ltp: ltp) }

  before do
    allow(tracker).to receive(:update_columns)
  end

  describe '#call' do
    context 'with NIFTY (retrace_ratio 0.35)' do
      it 'returns stop based on MFE retrace' do
        # Entry 100, Peak 300
        # MFE = 200
        # stop = 300 - (200 * 0.35) = 300 - 70 = 230
        engine = described_class.new(position: tracker, ltp: 300.0)
        expect(engine.call).to eq(230.0)
      end

      it 'returns nil if no MFE' do
        expect(engine.call).to be_nil
      end
    end

    context 'with SENSEX (retrace_ratio 0.45)' do
      let(:symbol) { 'SENSEX24MAR72000CE' }
      it 'returns stop based on MFE retrace' do
        # Entry 100, Peak 300
        # MFE = 200
        # stop = 300 - (200 * 0.45) = 300 - 90 = 210
        engine = described_class.new(position: tracker, ltp: 300.0)
        expect(engine.call).to eq(210.0)
      end
    end
  end
end
