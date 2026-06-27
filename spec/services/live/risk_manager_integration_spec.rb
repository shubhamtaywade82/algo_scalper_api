# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Live::RiskManagerService Integration" do
  let(:exit_engine) { double('ExitEngine', execute_exit: true) }
  let(:service) { Live::RiskManagerService.new(exit_engine: exit_engine) }
  let(:instrument) { create(:instrument, symbol_name: 'NIFTY', exchange: :nse, segment: :index) }
  let!(:tracker) { create(:position_tracker, :active, instrument: instrument, security_id: '12345', symbol: 'NIFTY24MAR22000CE', segment: 'NSE_FNO') }
  let(:position_data) { OpenStruct.new(current_ltp: 150.0, pnl: 500.0) }

  before do
    Core::EventBus.instance.clear

    allow(Positions::ActivePositionsCache.instance).to receive(:active_trackers).and_return([tracker])
    allow(Positions::ActiveCache.instance).to receive(:get_by_tracker_id).with(tracker.id).and_return(position_data)
    allow(service).to receive(:should_run_realtime_enforcement?).and_return(true)

    allow(service).to receive(:start_watchdog)
    allow(Thread).to receive(:new).and_wrap_original do |m, *args, &block|
      m.call(*args, &block)
    end

    allow(service).to receive(:start).and_wrap_original do |_m|
      service.instance_variable_set(:@running, true)
      service.instance_variable_set(:@event_subscription, Core::EventBus.instance.subscribe(:ltp) { |e| service.send(:handle_pnl_event, e) })
    end

    service.start
  end

  after do
    service.stop
    Core::EventBus.instance.clear
  end

  describe 'Event-driven risk evaluation' do
    it 'reacts to :ltp events by running core exit enforcement' do
      expect(service).to receive(:run_enforcement_for_tracker).with(
        tracker,
        exit_engine,
        position_data: position_data
      ).once

      Core::EventBus.instance.publish(:ltp, { tracker_id: tracker.id, ltp: 150.0, pnl: 500.0 })
    end

    it 'dispatches exit when core enforcement recommends it' do
      allow(service).to receive(:run_enforcement_for_tracker) do |tracked, engine, position_data:|
        service.send(:dispatch_exit, engine, tracked, 'Test Exit')
      end

      Core::EventBus.instance.publish(:ltp, { tracker_id: tracker.id, ltp: 150.0, pnl: -1000.0 })

      expect(exit_engine).to have_received(:execute_exit).with(tracker, 'Test Exit').once
    end
  end

  describe 'Concurrency protection' do
    it 'prevents re-entrant processing for the same tracker' do
      call_count = 0
      allow(service).to receive(:run_enforcement_for_tracker) do
        call_count += 1
        sleep 0.2
      end

      t1 = Thread.new { Core::EventBus.instance.publish(:ltp, { tracker_id: tracker.id, ltp: 150.0 }) }
      sleep 0.05
      t2 = Thread.new { Core::EventBus.instance.publish(:ltp, { tracker_id: tracker.id, ltp: 151.0 }) }

      t1.join
      t2.join

      expect(call_count).to eq(1)
    end
  end
end
