# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::ReconciliationService do
  let(:service) { described_class.instance }

  before do
    # Ensure service is stopped before each test
    service.stop if service.running?
  end

  after(:each) do
    service.stop
    # Reset singleton state
    service.instance_variable_set(:@last_reconciliation, nil)
  end

  describe '#run_loop' do
    context 'when market is closed and no active positions' do
      before do
        allow(TradingSession::Service).to receive(:market_closed?).and_return(true)
        allow(Positions::ActivePositionsCache.instance).to receive(:active_trackers).and_return([])
        allow(service).to receive(:reconcile_all_positions)
      end

      it 'does not call reconcile_all_positions' do
        service.start
        sleep(0.2)
        expect(service).not_to have_received(:reconcile_all_positions)
      end
    end

    context 'when market is closed but positions exist' do
      before do
        allow(TradingSession::Service).to receive(:market_closed?).and_return(true)
        # Mock active_trackers to return a list with one item
        tracker = instance_double(PositionTracker, id: 1)
        allow(Positions::ActivePositionsCache.instance).to receive(:active_trackers).and_return([tracker])
        allow(service).to receive(:reconcile_all_positions)
      end

      it 'continues reconciliation' do
        service.start
        sleep(0.2)
        expect(service).to have_received(:reconcile_all_positions).at_least(:once)
      end
    end

    context 'when market is open' do
      before do
        allow(TradingSession::Service).to receive(:market_closed?).and_return(false)
        allow(service).to receive(:reconcile_all_positions)
      end

      it 'performs normal reconciliation' do
        service.start
        sleep(0.2)
        expect(service).to have_received(:reconcile_all_positions).at_least(:once)
      end
    end
  end
end
