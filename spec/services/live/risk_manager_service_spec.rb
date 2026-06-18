# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::RiskManagerService do
  let(:exit_engine) { double('ExitEngine') }
  let(:service) { described_class.new(exit_engine: exit_engine) }
  let(:event_bus) { Core::EventBus.instance }
  let(:active_cache) { instance_double(Positions::ActivePositionsCache) }
  let(:mock_thread) { double('Thread', alive?: true, name: 'risk-manager', kill: true) }

  before do
    allow(Positions::ActivePositionsCache).to receive(:instance).and_return(active_cache)
    allow(AlgoConfig).to receive(:fetch).and_return({ paper_trading: { enabled: true } })
    allow(Notifications::TelegramNotifier.instance).to receive(:notify_error)
    # Avoid starting actual threads in most tests
    allow(Thread).to receive(:new).and_return(mock_thread)
  end

  describe '#initialize' do
    it 'sets initial state' do
      expect(service.instance_variable_get(:@running)).to be false
      expect(service.instance_variable_get(:@exit_engine)).to eq(exit_engine)
    end
  end

  describe '#start' do
    it 'sets running to true and starts a thread' do
      expect(Thread).to receive(:new)
      service.start
      expect(service.instance_variable_get(:@running)).to be true
    end

    it 'subscribes to ltp events' do
      expect(event_bus).to receive(:subscribe).with(:ltp).and_call_original
      service.start
    end
  end

  describe '#stop' do
    before { service.start }

    it 'sets running to false' do
      service.stop
      expect(service.instance_variable_get(:@running)).to be false
    end

    it 'unsubscribes from event bus' do
      expect(event_bus).to receive(:unsubscribe)
      service.stop
    end
  end

  describe '#handle_pnl_event' do
    let(:tracker) { build_stubbed(:position_tracker, :active, id: 1) }
    let(:event) { { tracker_id: 1, pnl: 50.0, ltp: 100.0 } }
    let(:position_data) { OpenStruct.new(current_ltp: 100.0, pnl: 50.0) }

    before do
      service.instance_variable_set(:@running, true)
      allow(active_cache).to receive(:active_trackers).and_return([tracker])
      allow(Positions::ActiveCache.instance).to receive(:get_by_tracker_id).with(1).and_return(position_data)
      allow(service).to receive(:should_run_realtime_enforcement?).and_return(true)
    end

    it 'runs core exit enforcement for the tracker' do
      expect(service).to receive(:run_enforcement_for_tracker).with(
        tracker,
        exit_engine,
        position_data: position_data
      )
      service.send(:handle_pnl_event, event)
    end
  end

  describe '#evaluate_signal_risk' do
    it 'returns low risk for high confidence' do
      result = service.send(:evaluate_signal_risk, { confidence: 0.9, entry_price: 100 })
      expect(result[:risk_level]).to eq(:low)
      expect(result[:max_position_size]).to eq(100)
    end

    it 'returns medium risk for medium confidence' do
      result = service.send(:evaluate_signal_risk, { confidence: 0.7, entry_price: 100 })
      expect(result[:risk_level]).to eq(:medium)
      expect(result[:max_position_size]).to eq(50)
    end

    it 'returns high risk for low confidence' do
      result = service.send(:evaluate_signal_risk, { confidence: 0.5, entry_price: 100 })
      expect(result[:risk_level]).to eq(:high)
      expect(result[:max_position_size]).to eq(25)
    end
  end
end
