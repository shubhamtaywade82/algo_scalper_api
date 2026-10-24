# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::Guards::CooldownGuard do
  describe '.call' do
    let(:context) do
      {
        pick: { symbol: 'NIFTY24MAR24000CE' },
        index_cfg: { key: 'NIFTY', cooldown_sec: 180 }
      }
    end

    context 'when cooldown is active' do
      before do
        allow(Entries::EntryGuard).to receive(:cooldown_active?).with('NIFTY24MAR24000CE', 180).and_return(true)
      end

      it 'blocks entry due to cooldown' do
        result = described_class.call(context)
        expect(result).to include(blocked: /cooldown active for NIFTY/)
      end
    end

    context 'when cooldown is not active' do
      before do
        allow(Entries::EntryGuard).to receive(:cooldown_active?).with('NIFTY24MAR24000CE', 180).and_return(false)
      end

      it 'allows entry' do
        result = described_class.call(context)
        expect(result).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end
  end
end

