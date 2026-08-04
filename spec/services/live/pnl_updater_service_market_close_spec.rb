# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::PnlUpdaterService do
  let(:service) { described_class.instance }

  describe '#run_loop' do
    context 'when market is closed and no active positions' do
      before do
        allow(TradingSession::Service).to receive(:market_closed?).and_return(true)
        allow(PositionTracker).to receive_message_chain(:active, :count).and_return(0)
        allow(service).to receive(:flush!)
      end

      it 'does not call flush!' do
        service.start!
        sleep(0.1)
        expect(service).not_to have_received(:flush!)
        service.stop!
      end
    end

    context 'when market is closed but positions exist' do
      before do
        allow(TradingSession::Service).to receive(:market_closed?).and_return(true)
        allow(PositionTracker).to receive_message_chain(:active, :count).and_return(1)
        allow(service).to receive(:flush!).and_return(false)
      end

      it 'continues processing PnL updates' do
        service.start!
        sleep(0.1)
        expect(service).to have_received(:flush!).at_least(:once)
        service.stop!
      end
    end

    context 'when market is open' do
      before do
        allow(TradingSession::Service).to receive(:market_closed?).and_return(false)
        allow(service).to receive(:flush!).and_return(false)
      end

      it 'performs normal PnL updates' do
        service.start!
        sleep(0.1)
        expect(service).to have_received(:flush!).at_least(:once)
        service.stop!
      end
    end
  end
end
