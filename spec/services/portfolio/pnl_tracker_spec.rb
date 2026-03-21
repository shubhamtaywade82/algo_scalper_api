# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Portfolio::PnlTracker do
  let(:redis) { instance_double(Redis) }

  before do
    # Reset class-level redis memoization
    described_class.instance_variable_set(:@redis, redis)

    # Default stubs for a clean state
    allow(redis).to receive(:hset)
    allow(redis).to receive(:expire)
    allow(redis).to receive(:hdel)
    allow(redis).to receive(:del)
    allow(redis).to receive(:incrbyfloat)
    allow(redis).to receive(:get).and_return(nil)
    allow(redis).to receive(:hgetall).and_return({})
    allow(redis).to receive(:set)

    allow(AlgoConfig).to receive(:fetch).and_return({ profit_lock: { enabled: true } })
  end

  after do
    described_class.instance_variable_set(:@redis, nil)
  end

  describe '.update_unrealized' do
    it 'stores pnl in the UNREALIZED hash under the tracker key' do
      expect(redis).to receive(:hset).with(
        described_class::KEY_UNREALIZED,
        't42',
        '500.0'
      )
      described_class.update_unrealized(tracker_id: 42, pnl: 500.0)
    end

    it 'does nothing when profit_lock is disabled' do
      allow(AlgoConfig).to receive(:fetch).and_return({ profit_lock: { enabled: false } })
      expect(redis).not_to receive(:hset)
      described_class.update_unrealized(tracker_id: 1, pnl: 100.0)
    end

    it 'rescues Redis errors gracefully' do
      allow(redis).to receive(:hset).and_raise(Redis::ConnectionError, 'timeout')
      expect { described_class.update_unrealized(tracker_id: 1, pnl: 100.0) }.not_to raise_error
    end
  end

  describe '.mark_realized' do
    it 'increments the REALIZED key by the pnl amount' do
      expect(redis).to receive(:incrbyfloat).with(described_class::KEY_REALIZED, 2000.0)
      described_class.mark_realized(tracker_id: 99, pnl: 2000.0)
    end

    it 'removes the tracker from the UNREALIZED hash' do
      expect(redis).to receive(:hdel).with(described_class::KEY_UNREALIZED, 't99')
      described_class.mark_realized(tracker_id: 99, pnl: 2000.0)
    end

    it 'handles negative pnl (losses) correctly' do
      expect(redis).to receive(:incrbyfloat).with(described_class::KEY_REALIZED, -500.0)
      described_class.mark_realized(tracker_id: 7, pnl: -500.0)
    end
  end

  describe '.net_pnl' do
    it 'returns realized + sum of unrealized' do
      allow(redis).to receive(:get).with(described_class::KEY_REALIZED).and_return('8000.0')
      allow(redis).to receive(:hgetall).with(described_class::KEY_UNREALIZED)
                                       .and_return({ 't1' => '3000.0', 't2' => '-500.0' })
      expect(described_class.net_pnl).to eq(10_500.0)
    end

    it 'returns 0.0 when no state is set' do
      allow(redis).to receive(:get).and_return(nil)
      allow(redis).to receive(:hgetall).and_return({})
      expect(described_class.net_pnl).to eq(0.0)
    end
  end

  describe '.update_lock' do
    it 'sets peak when new_peak is higher' do
      allow(redis).to receive(:get).with(described_class::KEY_PEAK).and_return('5000.0')
      allow(redis).to receive(:get).with(described_class::KEY_FLOOR).and_return('3000.0')
      allow(redis).to receive(:get).with(described_class::KEY_LEVEL).and_return('1')

      expect(redis).to receive(:set).with(described_class::KEY_PEAK, '12000.0')
      described_class.update_lock(new_peak: 12_000.0, new_floor: 7_200.0, new_level: 1)
    end

    it 'does not decrease the peak (monotonic)' do
      allow(redis).to receive(:get).with(described_class::KEY_PEAK).and_return('20000.0')
      allow(redis).to receive(:get).with(described_class::KEY_FLOOR).and_return('14000.0')
      allow(redis).to receive(:get).with(described_class::KEY_LEVEL).and_return('2')

      expect(redis).not_to receive(:set).with(described_class::KEY_PEAK, anything)
      described_class.update_lock(new_peak: 15_000.0, new_floor: 10_500.0, new_level: 1)
    end

    it 'does not decrease the floor (monotonic)' do
      allow(redis).to receive(:get).with(described_class::KEY_PEAK).and_return('20000.0')
      allow(redis).to receive(:get).with(described_class::KEY_FLOOR).and_return('14000.0')
      allow(redis).to receive(:get).with(described_class::KEY_LEVEL).and_return('2')

      expect(redis).not_to receive(:set).with(described_class::KEY_FLOOR, anything)
      described_class.update_lock(new_peak: 21_000.0, new_floor: 13_000.0, new_level: 2)
    end
  end

  describe '.reset_day!' do
    it 'deletes all portfolio keys' do
      %w[portfolio:pnl:realized portfolio:pnl:unrealized portfolio:pnl:peak
         portfolio:pnl:floor portfolio:pnl:level].each do |key|
        expect(redis).to receive(:del).with(key)
      end
      described_class.reset_day!
    end
  end
end
