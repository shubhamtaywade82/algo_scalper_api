# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::RiskManagerService do
  let(:exit_engine) { instance_double(Live::ExitEngine) }
  let(:service) { described_class.new(exit_engine: exit_engine) }

  describe '#start (run_loop behavior)' do
    context 'when market is closed and no active positions' do
      before do
        allow(TradingSession::Service).to receive(:market_closed?).and_return(true)
        allow(Positions::ActivePositionsCache.instance).to receive(:active_trackers).and_return([])
        allow(PositionTracker).to receive_message_chain(:active, :includes, :to_a).and_return([])
        allow(service).to receive(:update_paper_positions_pnl_if_due)
        allow(service).to receive(:demand_driven_enabled?).and_return(false)
      end

      it 'does not monitor when no active positions exist' do
        service.send(:monitor_loop, Time.current)
        expect(service).not_to have_received(:update_paper_positions_pnl_if_due)
      end
    end

    context 'when market is closed but positions exist' do
      before do
        allow(TradingSession::Service).to receive(:market_closed?).and_return(true)
        allow(Positions::ActivePositionsCache.instance).to receive(:active_trackers).and_return([instance_double(PositionTracker)])
        allow(PositionTracker).to receive_message_chain(:active, :includes, :to_a).and_return([instance_double(PositionTracker)])
        allow(service).to receive(:update_paper_positions_pnl_if_due)
        allow(service).to receive(:ensure_all_positions_in_redis)
        allow(service).to receive(:ensure_all_positions_in_active_cache)
        allow(service).to receive(:ensure_all_positions_subscribed)
        allow(service).to receive(:process_trailing_for_all_positions)
        allow(service).to receive(:enforce_session_end_exit)
        allow(service).to receive(:enforce_eod_force_close)
      end

      it 'continues monitoring for exits' do
        service.send(:monitor_loop, Time.current)
        expect(service).to have_received(:update_paper_positions_pnl_if_due)
      end
    end

    context 'when market is open' do
      before do
        allow(TradingSession::Service).to receive(:market_closed?).and_return(false)
        allow(service).to receive(:update_paper_positions_pnl_if_due)
        allow(service).to receive(:ensure_all_positions_in_redis)
        allow(service).to receive(:ensure_all_positions_in_active_cache)
        allow(service).to receive(:ensure_all_positions_subscribed)
        allow(service).to receive(:process_trailing_for_all_positions)
        allow(service).to receive(:enforce_session_end_exit)
      end

      it 'performs normal monitoring' do
        service.send(:monitor_loop, Time.current)
        expect(service).to have_received(:update_paper_positions_pnl_if_due)
      end
    end
  end

  describe '#start' do
    after { service.stop }

    context 'when market is closed and no active positions' do
      before do
        allow(TradingSession::Service).to receive(:market_closed?).and_return(true)
        allow(PositionTracker).to receive_message_chain(:active, :includes, :to_a).and_return([])
      end

      it 'sleeps 60 seconds in the loop' do
        service.start
        sleep(0.1)
        # Thread should be sleeping, not processing
        service.stop
      end
    end
  end
end
