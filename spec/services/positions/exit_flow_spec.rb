# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Positions::ExitFlow do
  describe '.call' do
    let(:base_tracker_attrs) do
      {
        status: 'active',
        segment: 'NSE_FNO',
        security_id: '55111',
        order_no: "EXITFLOW#{SecureRandom.hex(4)}"
      }
    end

    before do
      allow(Live::RedisTickCache.instance).to receive(:clear_tick)
      allow(Live::TickCache).to receive(:delete)
      allow(Live::PositionIndex.instance).to receive(:remove)
    end

    it 'runs exit orchestration and returns tracker' do
      tracker = create(:position_tracker, :option_position, **base_tracker_attrs)
      cache = instance_double(
        Live::RedisPnlCache,
        fetch_pnl: { pnl: 10, pnl_pct: 0.2, hwm_pnl: 12, hwm_pnl_pct: 0.3 },
        sync_pnl_to_database: true,
        clear_tracker: nil
      )

      allow(Live::RedisPnlCache).to receive(:instance).and_return(cache)
      allow(Positions::DailyPnlRecorder).to receive(:call)
      allow(Positions::FeedSubscription).to receive(:unsubscribe)

      result = described_class.call(tracker: tracker, exit_price: BigDecimal('100'))

      expect(Positions::DailyPnlRecorder).to have_received(:call).with(tracker: tracker)
      expect(Positions::FeedSubscription).to have_received(:unsubscribe).with(tracker: tracker).at_least(:once)
      expect(tracker.reload.status).to eq('exited')
      expect(result).to eq(tracker)
    end

    context 'when exit_reason is missing everywhere' do
      it 'persists EXIT_REASON_UNSPECIFIED on meta and column' do
        tracker = create(:position_tracker, :option_position, **base_tracker_attrs, meta: {})
        cache = instance_double(
          Live::RedisPnlCache,
          fetch_pnl: {},
          sync_pnl_to_database: true,
          clear_tracker: nil
        )

        allow(Live::RedisPnlCache).to receive(:instance).and_return(cache)
        allow(Positions::DailyPnlRecorder).to receive(:call)
        allow(Positions::FeedSubscription).to receive(:unsubscribe)

        described_class.call(tracker: tracker, exit_price: BigDecimal('100'))

        tracker.reload
        expect(tracker.meta['exit_reason']).to eq(Positions::ExitFlow::FALLBACK_EXIT_REASON)
        expect(tracker.exit_reason).to eq(Positions::ExitFlow::FALLBACK_EXIT_REASON)
      end
    end

    context 'when meta has blank exit_reason string' do
      it 'uses fallback instead of empty string' do
        tracker = create(
          :position_tracker,
          :option_position,
          **base_tracker_attrs,
          meta: { 'exit_reason' => '  ' }
        )
        cache = instance_double(
          Live::RedisPnlCache,
          fetch_pnl: {},
          sync_pnl_to_database: true,
          clear_tracker: nil
        )

        allow(Live::RedisPnlCache).to receive(:instance).and_return(cache)
        allow(Positions::DailyPnlRecorder).to receive(:call)
        allow(Positions::FeedSubscription).to receive(:unsubscribe)

        described_class.call(tracker: tracker, exit_price: BigDecimal('100'))

        tracker.reload
        expect(tracker.meta['exit_reason']).to eq(Positions::ExitFlow::FALLBACK_EXIT_REASON)
      end
    end
  end
end
