# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::PnlUpdaterService do
  let(:service) { described_class.instance }

  describe '#run_loop' do
    context 'when market is closed and no active positions' do
      before do
        allow(TradingSession::Service).to receive(:market_closed?).and_return(true)
        allow(Positions::ActivePositionsCache.instance).to receive(:active_trackers).and_return([])
        allow(service).to receive(:flush!)
        allow(service).to receive(:build_dashboard_stats).and_return({})
      end

      it 'calls flush! at least once as required' do
        # Ensure the loop runs at least once
        allow(service).to receive(:running?).and_return(true, false)
        allow(service).to receive(:sleep)
        service.send(:run_loop)
        # Fix: User instruction says it should be called at least 1 time
        expect(service).to have_received(:flush!).at_least(:once)
      end
    end

    context 'when market is closed but positions exist' do
      before do
        allow(TradingSession::Service).to receive(:market_closed?).and_return(true)
        allow(Positions::ActivePositionsCache.instance).to receive(:active_trackers).and_return([instance_double(PositionTracker)])
        allow(service).to receive(:flush!).and_return(true)
      end

      it 'continues processing PnL updates' do
        allow(service).to receive(:running?).and_return(true, false)
        allow(service).to receive(:wait_for_interval)
        service.send(:run_loop)
        expect(service).to have_received(:flush!).at_least(:once)
      end
    end

    context 'when market is open' do
      before do
        allow(TradingSession::Service).to receive(:market_closed?).and_return(false)
        allow(service).to receive(:flush!).and_return(true)
      end

      it 'performs normal PnL updates' do
        allow(service).to receive(:running?).and_return(true, false)
        allow(service).to receive(:wait_for_interval)
        service.send(:run_loop)
        expect(service).to have_received(:flush!).at_least(:once)
      end
    end
  end
end
