# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::EntryGuard do
  describe '.post_entry_wiring' do
    let(:feature_flags) do
      { feature_flags: { enable_auto_subscribe_unsubscribe: true }, risk: { sl_pct: 0.10, tp_pct: 0.20 } }
    end
    let(:hub) do
      instance_double(
        Live::MarketFeedHub,
        subscribe_instrument: true,
        subscribe: true,
        running?: true,
        connected?: true,
        start!: true,
        subscribed?: false
      )
    end
    let(:active_cache) { instance_double(Positions::ActiveCache, add_position: true) }

    let!(:option_watchable) { create(:derivative, :nifty_call_option, security_id: '99999') }
    let!(:equity_watchable) { create(:instrument, :equity, security_id: '55555') }

    let(:option_tracker) do
      create(
        :position_tracker,
        watchable: option_watchable,
        instrument: option_watchable.instrument,
        entry_price: BigDecimal('120.0'),
        segment: 'NSE_FNO',
        security_id: '99999',
        quantity: 25,
        status: 'active'
      )
    end

    let(:equity_tracker) do
      create(
        :position_tracker,
        watchable: equity_watchable,
        instrument: equity_watchable,
        entry_price: BigDecimal('150.0'),
        segment: 'NSE_EQ',
        security_id: '55555',
        quantity: 1,
        status: 'active'
      )
    end

    before do
      allow(Live::MarketFeedHub).to receive(:instance).and_return(hub)
      allow(Positions::ActiveCache).to receive(:instance).and_return(active_cache)
      allow(Orders::BracketPlacer).to receive(:place_bracket).and_return(success: true)
    end

    it 'subscribes option strikes and adds to ActiveCache when feature flag enabled' do
      allow(AlgoConfig).to receive(:fetch).and_return(feature_flags)

      described_class.send(:post_entry_wiring, tracker: option_tracker, side: 'long_ce', index_cfg: {})

      expect(hub).to have_received(:subscribe_instrument).with(segment: 'NSE_FNO', security_id: '99999')
      expect(active_cache).to have_received(:add_position).with(hash_including(tracker: option_tracker, sl_price: kind_of(Float), tp_price: kind_of(Float)))
      expect(Orders::BracketPlacer).to have_received(:place_bracket).with(hash_including(tracker: option_tracker, reason: 'initial_bracket'))
    end

    it 'skips subscription for non-option segments but still adds to ActiveCache' do
      allow(AlgoConfig).to receive(:fetch).and_return(feature_flags)

      described_class.send(:post_entry_wiring, tracker: equity_tracker, side: 'long_ce', index_cfg: {})

      expect(hub).not_to have_received(:subscribe_instrument)
      expect(active_cache).to have_received(:add_position).with(hash_including(tracker: equity_tracker))
      expect(Orders::BracketPlacer).to have_received(:place_bracket).with(hash_including(tracker: equity_tracker))
    end

    it 'does not autowire when feature flag disabled but still places bracket' do
      allow(AlgoConfig).to receive(:fetch).and_return(feature_flags.merge(feature_flags: { enable_auto_subscribe_unsubscribe: false }))

      described_class.send(:post_entry_wiring, tracker: option_tracker, side: 'long_ce', index_cfg: {})

      expect(hub).not_to have_received(:subscribe_instrument)
      expect(active_cache).not_to have_received(:add_position)
      expect(Orders::BracketPlacer).to have_received(:place_bracket).with(hash_including(tracker: option_tracker))
    end
  end
end
