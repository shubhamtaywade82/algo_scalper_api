# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::ReconciliationService do
  let(:service) { described_class.instance }

  describe '#run_loop' do
    context 'when market is closed and no active positions' do
      before do
        allow(TradingSession::Service).to receive(:market_closed?).and_return(true)
        allow(PositionTracker).to receive_message_chain(:active, :count).and_return(0)
        allow(service).to receive(:reconcile_all_positions)
      end

      it 'does not call reconcile_all_positions' do
        service.start
        sleep(0.1)
        expect(service).not_to have_received(:reconcile_all_positions)
        service.stop
      end
    end

    context 'when market is closed but positions exist' do
      before do
        allow(TradingSession::Service).to receive(:market_closed?).and_return(true)
        allow(PositionTracker).to receive_message_chain(:active, :count).and_return(1)
        allow(service).to receive(:reconcile_all_positions)
      end

      it 'continues reconciliation' do
        service.start
        sleep(0.1)
        expect(service).to have_received(:reconcile_all_positions).at_least(:once)
        service.stop
      end
    end

    context 'when market is open' do
      before do
        allow(TradingSession::Service).to receive(:market_closed?).and_return(false)
        allow(service).to receive(:reconcile_all_positions)
      end

      it 'performs normal reconciliation' do
        service.start
        sleep(0.1)
        expect(service).to have_received(:reconcile_all_positions).at_least(:once)
        service.stop
      end
    end
  end
end

