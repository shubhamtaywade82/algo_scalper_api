# frozen_string_literal: true

require 'rails_helper'

# Phase 2: Advanced Optimizations (TDD Approach)
# These tests define the desired behavior for Phase 2 optimizations:
# 1. Consolidated position iteration (single loop)
# 2. Batch API calls for LTP fetching
# 3. Consolidated exit checks (remove duplicates)
RSpec.describe Live::RiskManagerService, 'Phase 2 Optimizations' do
  let(:service) { described_class.new }
  let(:instrument) { create(:instrument, :nifty_future, security_id: '9999') }
  let(:tracker1) do
    create(
      :position_tracker,
      instrument: instrument,
      order_no: 'ORD001',
      security_id: '50074',
      segment: 'NSE_FNO',
      status: 'active',
      quantity: 75,
      entry_price: 100.0
    )
  end
  let(:tracker2) do
    create(
      :position_tracker,
      instrument: instrument,
      order_no: 'ORD002',
      security_id: '50075',
      segment: 'NSE_FNO',
      status: 'active',
      quantity: 50,
      entry_price: 200.0
    )
  end
  let(:position_data1) do
    Positions::ActiveCache::PositionData.new(
      tracker_id: tracker1.id,
      security_id: tracker1.security_id,
      segment: tracker1.segment,
      entry_price: tracker1.entry_price,
      quantity: tracker1.quantity,
      pnl: BigDecimal('500'),
      pnl_pct: 5.0,
      high_water_mark: BigDecimal('600'),
      last_updated_at: Time.current
    )
  end
  let(:position_data2) do
    Positions::ActiveCache::PositionData.new(
      tracker_id: tracker2.id,
      security_id: tracker2.security_id,
      segment: tracker2.segment,
      entry_price: tracker2.entry_price,
      quantity: tracker2.quantity,
      pnl: BigDecimal('1000'),
      pnl_pct: 10.0,
      high_water_mark: BigDecimal('1200'),
      last_updated_at: Time.current
    )
  end
  let(:active_cache) { instance_double(Positions::ActiveCache) }

  before do
    allow(Positions::ActiveCache).to receive(:instance).and_return(active_cache)
    allow(active_cache).to receive(:all_positions).and_return([position_data1, position_data2])
  end

  describe 'Optimization 1: Consolidated Position Iteration' do
    context 'when monitor_loop processes positions' do
      before do
        allow(service).to receive(:update_paper_positions_pnl_if_due)
        allow(service).to receive(:ensure_all_positions_in_redis)
        allow(service).to receive(:ensure_all_positions_in_active_cache)
        allow(service).to receive(:ensure_all_positions_subscribed)
        allow(service).to receive(:process_trailing_for_all_positions)
        allow(service).to receive(:enforce_session_end_exit)
        allow(service).to receive(:enforce_hard_limits)
        allow(service).to receive(:enforce_trailing_stops)
        allow(service).to receive(:enforce_time_based_exit)
      end

      it 'iterates positions only once per cycle' do
        # Track how many times positions are iterated
        iteration_count = 0
        allow(active_cache).to receive(:all_positions) do
          iteration_count += 1
          [position_data1, position_data2]
        end

        service.send(:monitor_loop, Time.current)

        # Should only call all_positions once (or minimal times)
        expect(iteration_count).to be <= 2 # Allow for early exit check + processing
      end

      it 'processes all positions in a single consolidated pass' do
        processed_tracker_ids = []
        allow(service).to receive(:process_position_in_cycle) do |position, tracker|
          processed_tracker_ids << tracker.id
        end

        # Mock the consolidated processing method
        allow(service).to receive(:process_all_positions_in_single_loop).and_call_original

        service.send(:monitor_loop, Time.current)

        # Both positions should be processed
        expect(processed_tracker_ids).to contain_exactly(tracker1.id, tracker2.id)
      end

      it 'syncs PnL from Redis once per position per cycle' do
        redis_fetch_count = Hash.new(0)
        allow(Live::RedisPnlCache.instance).to receive(:fetch_pnl) do |tracker_id|
          redis_fetch_count[tracker_id] += 1
          { pnl: BigDecimal('500'), pnl_pct: 5.0, timestamp: Time.current.to_i }
        end

        service.send(:monitor_loop, Time.current)

        # Each tracker should only fetch Redis PnL once
        expect(redis_fetch_count[tracker1.id]).to eq(1)
        expect(redis_fetch_count[tracker2.id]).to eq(1)
      end

      it 'loads trackers only once per cycle' do
        db_query_count = 0
        allow(PositionTracker).to receive(:where) do |*args|
          db_query_count += 1
          PositionTracker.where(id: [tracker1.id, tracker2.id])
        end

        service.send(:monitor_loop, Time.current)

        # Should only query DB once for trackers
        expect(db_query_count).to be <= 1
      end
    end
  end

  describe 'Optimization 2: Batch API Calls for LTP Fetching' do
    context 'when fetching LTP for multiple positions' do
      let(:paper_trackers) { [tracker1, tracker2] }
      let(:batch_ltp_response) do
        {
          'status' => 'success',
          'data' => {
            'NSE_FNO' => {
              '50074' => { 'last_price' => '110.0' },
              '50075' => { 'last_price' => '220.0' }
            }
          }
        }
      end

      before do
        allow(PositionTracker).to receive_message_chain(:paper, :active, :includes).and_return(
          double(to_a: paper_trackers)
        )
        allow(Live::TickCache).to receive(:ltp).and_return(nil)
        allow(Live::RedisTickCache.instance).to receive(:fetch_tick).and_return(nil)
      end

      it 'fetches LTP for multiple positions in a single API call' do
        api_call_count = 0
        allow(DhanHQ::Models::MarketFeed).to receive(:ltp) do |request_hash|
          api_call_count += 1
          expect(request_hash).to be_a(Hash)
          expect(request_hash['NSE_FNO']).to contain_exactly(50_074, 50_075)
          batch_ltp_response
        end

        service.send(:batch_update_paper_positions_pnl, paper_trackers)

        # Should only make 1 API call for both positions
        expect(api_call_count).to eq(1)
      end

      it 'handles batch API response correctly' do
        allow(DhanHQ::Models::MarketFeed).to receive(:ltp).and_return(batch_ltp_response)
        allow(service).to receive(:update_pnl_in_redis)

        ltps = service.send(:batch_fetch_ltp, [
          { segment: 'NSE_FNO', security_id: '50074' },
          { segment: 'NSE_FNO', security_id: '50075' }
        ])

        expect(ltps['50074']).to eq(BigDecimal('110.0'))
        expect(ltps['50075']).to eq(BigDecimal('220.0'))
      end

      it 'falls back to individual calls if batch fails' do
        allow(DhanHQ::Models::MarketFeed).to receive(:ltp).and_raise(StandardError, 'Batch failed')
        allow(service).to receive(:get_paper_ltp).and_return(BigDecimal('110.0'))

        expect { service.send(:batch_fetch_ltp, [{ segment: 'NSE_FNO', security_id: '50074' }]) }.not_to raise_error
      end

      it 'groups positions by segment for batch calls' do
        tracker3 = create(:position_tracker, segment: 'IDX_I', security_id: '13', status: 'active')
        trackers = [tracker1, tracker2, tracker3]

        api_calls = []
        allow(DhanHQ::Models::MarketFeed).to receive(:ltp) do |request_hash|
          api_calls << request_hash
          { 'status' => 'success', 'data' => {} }
        end

        service.send(:batch_update_paper_positions_pnl, trackers)

        # Should make 2 API calls: one for NSE_FNO, one for IDX_I
        expect(api_calls.length).to eq(2)
        expect(api_calls.map(&:keys).flatten).to contain_exactly('NSE_FNO', 'IDX_I')
      end
    end
  end

  describe 'Optimization 3: Consolidated Exit Checks' do
    let(:exit_engine) { instance_double(Live::ExitEngine) }

    before do
      allow(service).to receive(:risk_config).and_return(
        sl_pct: 0.1,
        tp_pct: 0.2,
        exit_drop_pct: 0.03
      )
      allow(service).to receive(:trackers_for_positions).and_return(
        { tracker1.id => tracker1, tracker2.id => tracker2 }
      )
      allow(service).to receive(:sync_position_pnl_from_redis)
    end

    context 'when checking exit conditions' do
      it 'checks all exit conditions in a single pass per position' do
        exit_checks_per_position = Hash.new(0)

        # Mock consolidated exit check method
        allow(service).to receive(:check_all_exit_conditions) do |position, tracker|
          exit_checks_per_position[tracker.id] += 1
          # Simulate checking SL, TP, trailing, time-based, session end
          false # No exit triggered
        end

        service.send(:monitor_loop, Time.current)

        # Each position should be checked exactly once
        expect(exit_checks_per_position[tracker1.id]).to eq(1)
        expect(exit_checks_per_position[tracker2.id]).to eq(1)
      end

      it 'does not duplicate SL/TP checks' do
        sl_tp_check_count = 0
        allow(service).to receive(:check_sl_tp_limits) do |*args|
          sl_tp_check_count += 1
          false
        end

        # Process positions through consolidated exit check
        allow(service).to receive(:check_all_exit_conditions) do |position, tracker|
          service.send(:check_sl_tp_limits, position, tracker, exit_engine)
        end

        service.send(:monitor_loop, Time.current)

        # Should only check SL/TP once per position (not in both
        # process_trailing and enforce_hard_limits)
        expect(sl_tp_check_count).to eq(2) # Once per position
      end

      it 'prioritizes exit conditions correctly' do
        exit_reasons = []
        allow(exit_engine).to receive(:execute_exit) do |tracker, reason|
          exit_reasons << reason
        end

        # Session end should take priority
        allow(TradingSession::Service).to receive(:should_force_exit?).and_return(
          { should_exit: true }
        )
        position_data1.pnl_pct = -15.0 # Also hits SL

        service.send(:monitor_loop, Time.current)

        # Should exit with session end reason, not SL
        expect(exit_reasons).to include(match(/session end/))
      end
    end

    context 'when ExitEngine is provided' do
      let(:service_with_exit_engine) { described_class.new(exit_engine: exit_engine) }

      before do
        allow(Positions::ActiveCache).to receive(:instance).and_return(active_cache)
        allow(active_cache).to receive(:all_positions).and_return([position_data1])
        allow(service_with_exit_engine).to receive(:trackers_for_positions).and_return(
          { tracker1.id => tracker1 }
        )
        allow(service_with_exit_engine).to receive(:sync_position_pnl_from_redis)
        allow(service_with_exit_engine).to receive(:update_paper_positions_pnl_if_due)
        allow(service_with_exit_engine).to receive(:ensure_all_positions_in_redis)
        allow(service_with_exit_engine).to receive(:ensure_all_positions_in_active_cache)
        allow(service_with_exit_engine).to receive(:ensure_all_positions_subscribed)
        allow(service_with_exit_engine).to receive(:process_trailing_for_all_positions)
        allow(service_with_exit_engine).to receive(:enforce_session_end_exit)
      end

      it 'still checks all exit conditions even with ExitEngine' do
        exit_check_called = false
        allow(service_with_exit_engine).to receive(:check_all_exit_conditions) do |*args|
          exit_check_called = true
          false
        end

        service_with_exit_engine.send(:monitor_loop, Time.current)

        # Exit conditions should still be checked
        expect(exit_check_called).to be true
      end
    end
  end

  describe 'Performance Metrics' do
    before do
      allow(service).to receive(:update_paper_positions_pnl_if_due)
      allow(service).to receive(:ensure_all_positions_in_redis)
      allow(service).to receive(:ensure_all_positions_in_active_cache)
      allow(service).to receive(:ensure_all_positions_subscribed)
      allow(service).to receive(:process_trailing_for_all_positions)
      allow(service).to receive(:enforce_session_end_exit)
      allow(service).to receive(:enforce_hard_limits)
      allow(service).to receive(:enforce_trailing_stops)
      allow(service).to receive(:enforce_time_based_exit)
    end

    it 'completes cycle faster with consolidated iteration' do
      start_time = Time.current
      service.send(:monitor_loop, Time.current)
      elapsed = Time.current - start_time

      # With 2 positions, cycle should complete in < 100ms (optimized)
      expect(elapsed).to be < 0.1
    end

    it 'reduces Redis fetch count significantly' do
      redis_fetch_count = 0
      allow(Live::RedisPnlCache.instance).to receive(:fetch_pnl) do |*args|
        redis_fetch_count += 1
        { pnl: BigDecimal('500'), pnl_pct: 5.0, timestamp: Time.current.to_i }
      end

      service.send(:monitor_loop, Time.current)

      # Should only fetch once per position (2 positions = 2 fetches max)
      expect(redis_fetch_count).to be <= 2
    end

    it 'reduces DB query count' do
      db_query_count = 0
      allow(PositionTracker).to receive(:where) do |*args|
        db_query_count += 1
        double(where: double(includes: double(to_a: [tracker1, tracker2])))
      end

      service.send(:monitor_loop, Time.current)

      # Should query DB minimal times (1-2 queries max)
      expect(db_query_count).to be <= 2
    end
  end

  describe 'Backward Compatibility' do
    it 'maintains same exit behavior as before' do
      exit_engine = instance_double(Live::ExitEngine)
      allow(exit_engine).to receive(:execute_exit)

      # Simulate SL hit
      position_data1.pnl_pct = -15.0
      allow(service).to receive(:risk_config).and_return(sl_pct: 0.1, tp_pct: 0.2)
      allow(service).to receive(:trackers_for_positions).and_return({ tracker1.id => tracker1 })
      allow(service).to receive(:sync_position_pnl_from_redis)

      service.send(:enforce_hard_limits, exit_engine: exit_engine)

      # Should still exit on SL hit
      expect(exit_engine).to have_received(:execute_exit).with(
        tracker1,
        match(/SL HIT/)
      )
    end

    it 'maintains throttling behavior' do
      # Throttled operations should still respect throttling
      service.instance_variable_set(:@last_ensure_all, Time.current - 2.seconds)

      allow(PositionTracker).to receive_message_chain(:active, :includes).and_return(
        double(to_a: [])
      )

      service.send(:ensure_all_positions_in_redis)

      # Should update throttle timestamp
      expect(service.instance_variable_get(:@last_ensure_all)).to be_within(1.second).of(Time.current)
    end

    it 'maintains error isolation' do
      # Errors in one position should not affect others
      allow(service).to receive(:process_position_in_cycle).and_raise(StandardError, 'Error for position 1')
      allow(Rails.logger).to receive(:error)

      expect { service.send(:monitor_loop, Time.current) }.not_to raise_error
      # Should log error but continue processing
      expect(Rails.logger).to have_received(:error).at_least(:once)
    end
  end
end
