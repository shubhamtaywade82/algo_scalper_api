# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::PaperPnlRefresher do
  let(:service) { described_class.new }

  describe '#run_loop' do
    before do
      # Stub demand-driven mode and ActiveCache to allow refresh_all to be called
      allow(service).to receive(:demand_driven_enabled?).and_return(false)
      allow(Positions::ActiveCache.instance).to receive(:empty?).and_return(false)
      allow(service).to receive(:refresh_all)
    end

    context 'when market is closed and no active positions' do
      before do
        allow(TradingSession::Service).to receive(:market_closed?).and_return(true)
        allow(PositionTracker).to receive_message_chain(:paper, :active, :count).and_return(0)
      end

      it 'does not call refresh_all' do
        service.start
        sleep(0.15) # Give thread time to check market status
        expect(service).not_to have_received(:refresh_all)
        service.stop
      end
    end

    context 'when market is closed but positions exist' do
      before do
        allow(TradingSession::Service).to receive(:market_closed?).and_return(true)
        allow(PositionTracker).to receive_message_chain(:paper, :active, :count).and_return(1)
      end

      it 'continues refreshing PnL' do
        service.start
        sleep(0.15) # Give thread time to process
        expect(service).to have_received(:refresh_all).at_least(:once)
        service.stop
      end
    end

    context 'when market is open' do
      before do
        allow(TradingSession::Service).to receive(:market_closed?).and_return(false)
      end

      it 'performs normal refresh' do
        service.start
        sleep(0.15) # Give thread time to process
        expect(service).to have_received(:refresh_all).at_least(:once)
        service.stop
      end
    end
  end
end
