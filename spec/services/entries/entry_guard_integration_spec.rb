# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::EntryGuard do
  describe '.post_entry_wiring' do
    let(:watchable) { create(:derivative, :nifty_call_option, security_id: '52932') }
    let(:tracker) do
      create(
        :position_tracker,
        :option_position,
        watchable: watchable,
        instrument: watchable.instrument,
        entry_price: BigDecimal('120.0'),
        segment: 'NSE_FNO',
        security_id: watchable.security_id
      )
    end
    let(:active_cache) { instance_double(Positions::ActiveCache, add_position: true) }
    let(:bracket_placer) { instance_double(Orders::BracketPlacer, place_bracket: true) }

    before do
      allow(Live::MarketFeedHub.instance).to receive(:subscribe_instrument)
      allow(Positions::ActiveCache).to receive(:instance).and_return(active_cache)
      allow(Orders::BracketPlacer).to receive(:new).and_return(bracket_placer)
    end

    it 'subscribes instrument, adds tracker to ActiveCache and seeds bracket orders' do
      described_class.send(:post_entry_wiring, tracker: tracker, side: 'long_ce', index_cfg: {})

      expect(Live::MarketFeedHub.instance).to have_received(:subscribe_instrument).with(segment: tracker.segment, security_id: tracker.security_id)
      expect(active_cache).to have_received(:add_position).with(
        hash_including(
          tracker: tracker,
          sl_price: be > 0,
          tp_price: be > 0
        )
      )
      expect(bracket_placer).to have_received(:place_bracket).with(
        tracker: tracker,
        sl_price: be > 0,
        tp_price: be > 0,
        reason: 'initial_bracket'
      )
    end
  end
end

