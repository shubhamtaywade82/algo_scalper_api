# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Positions::ExitFlow do
  describe '.call' do
    it 'runs exit orchestration and returns tracker' do
      tracker = instance_double(PositionTracker, id: 12)
      state_machine = instance_double(Positions::States::PositionStateMachine, transition_to!: true)
      cache = instance_double(
        Live::RedisPnlCache,
        fetch_pnl: { pnl: 10, pnl_pct: 0.2, hwm_pnl: 12, hwm_pnl_pct: 0.3 },
        sync_pnl_to_database: true
      )

      allow(tracker).to receive_messages(state_machine: state_machine, send: nil)
      allow(Live::RedisPnlCache).to receive(:instance).and_return(cache)
      allow(Positions::DailyPnlRecorder).to receive(:call)
      allow(Positions::FeedSubscription).to receive(:unsubscribe)

      result = described_class.call(tracker: tracker)

      expect(state_machine).to have_received(:transition_to!).with(:exited)
      expect(Positions::DailyPnlRecorder).to have_received(:call).with(tracker: tracker)
      expect(Positions::FeedSubscription).to have_received(:unsubscribe).with(tracker: tracker)
      expect(result).to eq(tracker)
    end

    context 'when exit_reason is missing everywhere' do
      it 'persists EXIT_REASON_UNSPECIFIED on exit_reason and exit_triggered_at' do
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
        expect(tracker.exit_reason).to eq(Positions::ExitFlow::FALLBACK_EXIT_REASON)
        expect(tracker.exit_triggered_at).to be_present
      end
    end

    context 'when exit completes' do
      it 'stamps exit analytics on decision' do
        tracker = create(
          :position_tracker,
          :option_position,
          **base_tracker_attrs,
          meta: {}
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
        allow(Positions::ExitAnalyticsBuilder).to receive(:build).and_return(
          vix_at_exit: 13.2,
          dte_at_exit: 0,
          tier_at_exit: 'standard'
        )

        described_class.call(tracker: tracker, exit_price: BigDecimal('100'))

        tracker.reload
        expect(tracker.decision['vix_at_exit']).to eq(13.2)
        expect(tracker.decision['dte_at_exit']).to eq(0)
        expect(tracker.decision['tier_at_exit']).to eq('standard')
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
        expect(tracker.exit_reason).to eq(Positions::ExitFlow::FALLBACK_EXIT_REASON)
      end
    end

    context 'when redis cache has stale peak pnl' do
      it 'persists final pnl from exit_price instead of cache' do
        tracker = create(
          :position_tracker,
          :option_position,
          **base_tracker_attrs,
          entry_price: BigDecimal('150'),
          quantity: 25,
          last_pnl_rupees: BigDecimal('1998'),
          last_pnl_pct: BigDecimal('0.54')
        )
        cache = instance_double(
          Live::RedisPnlCache,
          fetch_pnl: { pnl: 1998, pnl_pct: 0.54, hwm_pnl: 1998, hwm_pnl_pct: 0.54 },
          sync_pnl_to_database: true,
          clear_tracker: nil
        )

        allow(Live::RedisPnlCache).to receive(:instance).and_return(cache)
        allow(Positions::DailyPnlRecorder).to receive(:call)
        allow(Positions::FeedSubscription).to receive(:unsubscribe)

        described_class.call(
          tracker: tracker,
          exit_price: BigDecimal('127.5'),
          exit_reason: 'PREMIUM_MOMENTUM_FAILURE'
        )

        tracker.reload
        expected = Positions::FinalPnl.from_exit_price(
          entry_price: tracker.entry_price,
          quantity: tracker.quantity,
          exit_price: BigDecimal('127.5'),
          is_exited: true
        )

        expect(tracker.last_pnl_rupees).to eq(expected[:pnl])
        expect(tracker.last_pnl_pct.to_f).to be_within(0.0001).of(expected[:pnl_pct].to_f)
        expect(tracker.last_pnl_rupees).not_to eq(BigDecimal('1998'))
      end
    end
  end
end
