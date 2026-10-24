# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Options::ChainWatchRegistry do
  after { described_class.reset! }

  describe '.register and .snapshot_for' do
    it 'returns the registered service\'s snapshot, keyed case-insensitively' do
      service = instance_double(Options::ChainWatchService, snapshot: { index_key: 'NIFTY', spot: 24_800.0 })

      described_class.register('nifty', service)

      expect(described_class.snapshot_for('NIFTY')).to eq({ index_key: 'NIFTY', spot: 24_800.0 })
      expect(described_class.snapshot_for('nifty')).to eq({ index_key: 'NIFTY', spot: 24_800.0 })
    end

    it 'returns nil for an index that was never registered' do
      expect(described_class.snapshot_for('BANKNIFTY')).to be_nil
    end

    it 'returns nil if the registered service raises when snapshotting' do
      service = instance_double(Options::ChainWatchService)
      allow(service).to receive(:snapshot).and_raise(StandardError, 'boom')

      described_class.register('SENSEX', service)

      expect(described_class.snapshot_for('SENSEX')).to be_nil
    end
  end
end
