# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Market::VixGate do
  let(:memory_cache) { ActiveSupport::Cache::MemoryStore.new }

  before do
    allow(Rails).to receive(:cache).and_return(memory_cache)
    memory_cache.clear

    allow(AlgoConfig).to receive(:fetch).and_return(
      market: {
        vix_gate: {
          enabled: true,
          security_id: '21',
          segment: 'IDX_I',
          entry_ceiling: 20.0,
          force_exit_above: 22.0
        }
      }
    )
  end

  describe '.evaluate!' do
    it 'locks entries when VIX is above ceiling' do
      allow(Live::TickCache).to receive(:ltp).and_return(21.5)

      described_class.evaluate!

      expect(described_class.entry_allowed?).to be(false)
      expect(described_class.force_exit_active?).to be(false)
    end

    it 'arms force-exit when VIX is above accelerator' do
      allow(Live::TickCache).to receive(:ltp).and_return(23.0)

      described_class.evaluate!

      expect(described_class.entry_allowed?).to be(false)
      expect(described_class.force_exit_active?).to be(true)
    end
  end
end
