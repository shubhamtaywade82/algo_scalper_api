# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OptionsBuying::BreakoutWatcher do
  let(:hub) { instance_spy(Live::MarketFeedHub) }
  let(:watcher) { described_class.new(hub: hub) }

  before do
    allow(OptionsBuying::Mode).to receive_messages(breakout_enabled?: true, config: {})
    allow(IndexConfigLoader).to receive(:load_indices).and_return([{ key: 'NIFTY', sid: '13', segment: 'IDX_I' }])
    watcher.instance_variable_set(:@running, true)
  end

  describe '#sync_radar_subscriptions!' do
    it 'subscribes radar strikes that are not already on the feed' do
      allow(OptionsBuying::StateStore).to receive(:radar_strikes).with('NIFTY').and_return(
        [
          { security_id: 'c2', segment: 'NSE_FNO', type: 'CE' },
          { security_id: 'p1', segment: 'NSE_FNO', type: 'PE' }
        ]
      )
      allow(hub).to receive(:subscribed?).with(segment: 'NSE_FNO', security_id: 'c2').and_return(false)
      allow(hub).to receive(:subscribed?).with(segment: 'NSE_FNO', security_id: 'p1').and_return(true)

      watcher.send(:sync_radar_subscriptions!)

      expect(hub).to have_received(:subscribe_many).with([{ segment: 'NSE_FNO', security_id: 'c2' }])
    end

    it 'does not call subscribe_many when everything is already subscribed' do
      allow(OptionsBuying::StateStore).to receive(:radar_strikes).with('NIFTY').and_return(
        [{ security_id: 'c2', segment: 'NSE_FNO', type: 'CE' }]
      )
      allow(hub).to receive(:subscribed?).and_return(true)

      watcher.send(:sync_radar_subscriptions!)

      expect(hub).not_to have_received(:subscribe_many)
    end

    it 'skips strikes missing a segment or security_id' do
      allow(OptionsBuying::StateStore).to receive(:radar_strikes).with('NIFTY').and_return(
        [{ security_id: '', segment: 'NSE_FNO' }, { security_id: 'x', segment: '' }]
      )

      watcher.send(:sync_radar_subscriptions!)

      expect(hub).not_to have_received(:subscribe_many)
    end

    it 'swallows hub errors so the sync loop survives' do
      allow(OptionsBuying::StateStore).to receive(:radar_strikes).and_raise(StandardError, 'boom')

      expect { watcher.send(:sync_radar_subscriptions!) }.not_to raise_error
    end
  end

  describe '#handle_tick' do
    let(:tick) { { security_id: 'opt1', ltp: 120.0 } }

    before do
      allow(OptionsBuying::StreamWriter).to receive(:record!)
      allow(OptionsBuying::MinuteBarAggregator).to receive(:record_tick!)
      allow(OptionsBuying::Mode).to receive(:compression_enabled?).and_return(false)
    end

    it 'always writes the tick to the stream' do
      allow(OptionsBuying::Mode).to receive(:streams_enabled?).and_return(true)
      watcher.send(:handle_tick, tick)
      expect(OptionsBuying::StreamWriter).to have_received(:record!).with(tick)
    end

    it 'falls back to the legacy minute-bar aggregator only when streams are disabled' do
      allow(OptionsBuying::Mode).to receive(:streams_enabled?).and_return(false)
      watcher.send(:handle_tick, tick)
      expect(OptionsBuying::MinuteBarAggregator).to have_received(:record_tick!).with(tick)
    end

    it 'does not use the legacy aggregator when streams are enabled' do
      allow(OptionsBuying::Mode).to receive(:streams_enabled?).and_return(true)
      watcher.send(:handle_tick, tick)
      expect(OptionsBuying::MinuteBarAggregator).not_to have_received(:record_tick!)
    end
  end

  describe '#compression_check_due?' do
    it 'allows the first check, throttles the next within the interval, per security_id' do
      expect(watcher.send(:compression_check_due?, 'a')).to be(true)
      expect(watcher.send(:compression_check_due?, 'a')).to be(false)
      expect(watcher.send(:compression_check_due?, 'b')).to be(true)
    end

    it 'never schedules a check for a blank security_id' do
      expect(watcher.send(:compression_check_due?, '')).to be(false)
    end
  end

  describe '#update_compression_arm' do
    let(:tick) { { security_id: '13', ltp: 24_500.0 } }
    let(:instrument) { instance_double(Instrument) }

    before do
      allow(OptionsBuying::Mode).to receive_messages(compression_enabled?: true, config: { breakout: { compression_arm: true } })
      allow(Instrument).to receive(:find_by).and_return(instrument)
      allow(OptionsBuying::StateStore).to receive(:set_compression_arm!)
    end

    it 'arms compression for the index when the ATR ratio is compressed' do
      allow(OptionsBuying::ATRCompressionChecker).to receive(:compressed?).with(instrument).and_return(true)
      watcher.send(:update_compression_arm, tick)
      expect(OptionsBuying::StateStore).to have_received(:set_compression_arm!).with('NIFTY')
    end

    it 'does not arm when the market is not compressed' do
      allow(OptionsBuying::ATRCompressionChecker).to receive(:compressed?).with(instrument).and_return(false)
      watcher.send(:update_compression_arm, tick)
      expect(OptionsBuying::StateStore).not_to have_received(:set_compression_arm!)
    end
  end
end
