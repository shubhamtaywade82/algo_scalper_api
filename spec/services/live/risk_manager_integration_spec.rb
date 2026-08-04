# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Live::RiskManagerService Integration" do
  let(:exit_engine) { double('ExitEngine', execute_exit: true) }
  let(:service) { Live::RiskManagerService.new(exit_engine: exit_engine) }
  let(:instrument) { create(:instrument, symbol_name: 'NIFTY', exchange: :nse, segment: :index) }
  let!(:tracker) { create(:position_tracker, :active, instrument: instrument, security_id: '12345', symbol: 'NIFTY24MAR22000CE', segment: 'NSE_FNO') }
  
  before do
    # Completely clear EventBus to ensure no duplicate subscriptions from any source
    Core::EventBus.instance.clear
    
    # Ensure ActivePositionsCache has our tracker
    allow(Positions::ActivePositionsCache.instance).to receive(:active_trackers).and_return([tracker])
    
    # Mock systems that have side effects
    allow(Portfolio::PnlTracker).to receive(:update_unrealized)
    allow(Portfolio::ProfitLockEngine).to receive(:evaluate!)
    allow(Live::UnifiedExitChecker).to receive(:check_exit_conditions).and_return(nil)
    
    # Stub the background enforcement to isolate the sub-second event path
    allow(service).to receive(:run_enforcement_for_tracker)
    
    # Stub Thread.new for the service to avoid background loop noise
    # We only care about the event subscription which happens in the same thread as service.start
    allow(service).to receive(:start_watchdog)
    allow(Thread).to receive(:new).and_wrap_original do |m, *args, &block|
      # Only allow the real Thread.new if it's NOT named 'risk-manager' (which is the service loop)
      # In the spec, we name our threads manually if needed.
      m.call(*args, &block)
    end
    
    # To stop the service loop from starting, we mock start to only do the subscribe part
    # but keep it realistic.
    allow(service).to receive(:start).and_wrap_original do |m|
      # Execute only the subscription logic if we want to avoid the thread
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
    it 'reacts to :ltp events by checking exit conditions' do
      Core::EventBus.instance.publish(:ltp, { tracker_id: tracker.id, ltp: 150.0, pnl: 500.0 })
      
      expect(Live::UnifiedExitChecker).to have_received(:check_exit_conditions).with(tracker).once
    end

    it 'dispatches exit when UnifiedExitChecker recommends it' do
      allow(Live::UnifiedExitChecker).to receive(:check_exit_conditions).and_return({ exit: true, reason: 'Test Exit' })
      
      # The event-driven path should call dispatch_exit exactly once due to atomic guard
      Core::EventBus.instance.publish(:ltp, { tracker_id: tracker.id, ltp: 150.0, pnl: -1000.0 })
      
      expect(exit_engine).to have_received(:execute_exit).with(tracker, 'Test Exit (Sub-second Trigger)').once
    end

    it 'updates Portfolio::PnlTracker on every tick' do
      Core::EventBus.instance.publish(:ltp, { tracker_id: tracker.id, ltp: 155.0, pnl: 750.0 })
      
      expect(Portfolio::PnlTracker).to have_received(:update_unrealized).with(tracker_id: tracker.id, pnl: 750.0)
      expect(Portfolio::ProfitLockEngine).to have_received(:evaluate!)
    end
  end

  describe 'Concurrency protection' do
    it 'prevents re-entrant processing for the same tracker' do
      # Mock check_exit_conditions to block and verify concurrency guard
      call_count = 0
      allow(Live::UnifiedExitChecker).to receive(:check_exit_conditions) do
        call_count += 1
        sleep 0.2
        nil
      end
      
      # Publish 2 events rapidly in separate threads
      # Since we're using real threads here, the atomic guard (put_if_absent) must work
      t1 = Thread.new { Core::EventBus.instance.publish(:ltp, { tracker_id: tracker.id, ltp: 150.0 }) }
      sleep 0.05
      t2 = Thread.new { Core::EventBus.instance.publish(:ltp, { tracker_id: tracker.id, ltp: 151.0 }) }
      
      t1.join
      t2.join
      
      # The second one must have been skipped
      expect(call_count).to eq(1)
    end
  end
end
