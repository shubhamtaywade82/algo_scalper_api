# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TradingSystem::PositionHeartbeat do
  let(:service) { described_class.new }

  describe '#start' do
    after { service.stop }

    context 'when market is closed and no active positions' do
      before do
        allow(TradingSession::Service).to receive(:market_closed?).and_return(true)
        allow(PositionTracker).to receive_message_chain(:active, :count).and_return(0)
        allow(Live::PositionIndex.instance).to receive(:bulk_load_active!)
        allow(Live::PositionTrackerPruner).to receive(:call)
      end

      it 'does not call bulk_load_active! or pruner' do
        service.start
        sleep(0.1)
        expect(Live::PositionIndex.instance).not_to have_received(:bulk_load_active!)
        expect(Live::PositionTrackerPruner).not_to have_received(:call)
        service.stop
      end
    end

    context 'when market is closed but positions exist' do
      before do
        allow(TradingSession::Service).to receive(:market_closed?).and_return(true)
        allow(PositionTracker).to receive_message_chain(:active, :count).and_return(1)
        allow(Live::PositionIndex.instance).to receive(:bulk_load_active!)
        allow(Live::PositionTrackerPruner).to receive(:call)
      end

      it 'continues heartbeat operations' do
        service.start
        sleep(0.1)
        expect(Live::PositionIndex.instance).to have_received(:bulk_load_active!).at_least(:once)
        service.stop
      end
    end

    context 'when market is open' do
      before do
        allow(TradingSession::Service).to receive(:market_closed?).and_return(false)
        allow(Live::PositionIndex.instance).to receive(:bulk_load_active!)
        allow(Live::PositionTrackerPruner).to receive(:call)
      end

      it 'performs normal heartbeat' do
        service.start
        sleep(0.1)
        expect(Live::PositionIndex.instance).to have_received(:bulk_load_active!).at_least(:once)
        service.stop
      end
    end
  end
end

