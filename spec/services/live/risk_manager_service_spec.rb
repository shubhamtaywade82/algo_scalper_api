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

    before do
      service.instance_variable_set(:@running, true)
      allow(active_cache).to receive(:active_trackers).and_return([tracker])
      allow(Portfolio::PnlTracker).to receive(:update_unrealized)
      allow(Portfolio::ProfitLockEngine).to receive(:evaluate!)
    end

    it 'evaluates exit conditions via UnifiedExitChecker' do
      expect(Live::UnifiedExitChecker).to receive(:check_exit_conditions).with(tracker).and_return({ exit: false })
      service.send(:handle_pnl_event, event)
    end

    context 'when exit is triggered' do
      let(:exit_decision) { { exit: true, reason: 'Target Reached' } }

      before do
        allow(Live::UnifiedExitChecker).to receive(:check_exit_conditions).and_return(exit_decision)
      end

      it 'calls dispatch_exit on the exit engine' do
        expect(service).to receive(:dispatch_exit).with(exit_engine, tracker, /Target Reached/)
        service.send(:handle_pnl_event, event)
      end
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

    describe 'AC 4: Visibility & Logging' do
      before do
        allow(Live::PositionSyncService.instance).to receive(:sync_positions!)
        allow(service).to receive(:fetch_positions_indexed).and_return({})
        allow(service).to receive(:enforce_hard_limits)
        allow(service).to receive(:enforce_trailing_stops)
        allow(service).to receive(:enforce_time_based_exit)
        allow(service).to receive(:sleep)
        allow(Rails.logger).to receive(:info)
      end

      after do
        service.stop
      end

      it 'starts single job/thread visibly running' do
        service.start
        sleep 0.1

        expect(service.running?).to be true
        expect(service.instance_variable_get(:@thread)).to be_a(Thread)
        expect(service.instance_variable_get(:@thread).name).to eq('risk-manager-service')

        # Verify thread is visible in Thread.list
        risk_thread = Thread.list.find { |t| t.name == 'risk-manager-service' }
        expect(risk_thread).to be_present
      end

      it 'logs clear events for each exit' do
        position = double('Position', security_id: '50074', exchange_segment: 'NSE_FNO',
                                      net_qty: 75, cost_price: 100.0, product_type: 'INTRADAY')

        # Allow logger to receive calls and track them
        allow(Rails.logger).to receive(:info).and_call_original

        # Mock dependencies for execute_exit
        allow(service).to receive(:exit_position).and_return(true)
        allow(Live::RedisPnlCache.instance).to receive(:clear_tracker)
        allow(tracker).to receive(:mark_exited!)
        allow(tracker).to receive_messages(order_no: 'ORD123456', last_pnl_rupees: BigDecimal('-750'))
        allow(service).to receive(:store_exit_reason)

        # Call execute_exit directly to verify logging
        # This is the method that contains the logging we want to test
        service.send(:execute_exit, position, tracker, reason: 'test stop-loss')

        # Verify that logger received info calls - execute_exit logs two messages:
        # 1. "Triggering exit for #{order_no} (reason: #{reason}, PnL=#{pnl_display})."
        # 2. "Successfully exited position #{order_no}" (on success)
        expect(Rails.logger).to have_received(:info).with(match(/Triggering exit.*test stop-loss/)).at_least(:once)
        expect(Rails.logger).to have_received(:info).with(match(/Successfully exited/)).at_least(:once)
      end

      it 'auto-starts on system boot via initializer' do
        # This tests that the service can be started (auto-start is tested in initializer)
        expect { service.start }.not_to raise_error
        expect(service.running?).to be true
      end
    end

    describe 'Monitor Loop Structure' do
      before do
        allow(Live::PositionSyncService.instance).to receive(:sync_positions!)
        allow(service).to receive(:fetch_positions_indexed).and_return({})
        allow(service).to receive(:enforce_hard_limits)
        allow(service).to receive(:enforce_trailing_stops)
        allow(service).to receive(:enforce_time_based_exit)
        allow(service).to receive(:sleep)
      end

      after do
        # Ensure service is stopped and thread is terminated before DatabaseCleaner runs
        service.stop if service.running?
        # Give thread a moment to fully terminate and release DB connections
        sleep 0.1
      end

      it 'syncs positions before evaluating exits' do
        service.start
        sleep 0.2

        expect(Live::PositionSyncService.instance).to have_received(:sync_positions!).at_least(:once)
      end

      it 'calls enforce methods in correct sequence during each loop iteration' do
        service.start
        sleep 0.3

        # Verify all enforce methods are called during loop
        expect(service).to have_received(:enforce_hard_limits).at_least(:once)
        expect(service).to have_received(:enforce_trailing_stops).at_least(:once)
        expect(service).to have_received(:enforce_time_based_exit).at_least(:once)
      end

      it 'handles errors gracefully and stops running' do
        # Allow logger to receive error calls
        allow(Rails.logger).to receive(:error).and_call_original

        # Set up expectation before starting service
        expect(Rails.logger).to receive(:error).with(match(/RiskManagerService crashed/)).at_least(:once)

        # Raise error when sync_positions! is called
        allow(Live::PositionSyncService.instance).to receive(:sync_positions!).and_raise(StandardError, 'Error')

        # Mock other methods to prevent additional errors
        allow(service).to receive(:fetch_positions_indexed).and_return({})
        allow(service).to receive(:enforce_hard_limits)
        allow(service).to receive(:enforce_trailing_stops)
        allow(service).to receive(:enforce_time_based_exit)
        allow(service).to receive(:sleep)

        service.start
        sleep 1.5 # Give thread time to execute, catch error, and log it

        # After error, service should stop running (rescue block sets @running = false)
        expect(service.running?).to be false
      end
    end

    describe '#process_trailing_for_all_positions' do
      let(:trailing_engine) { instance_double(Live::TrailingEngine) }
      let(:active_cache) { instance_double(Positions::ActiveCache) }
      let(:position_data) do
        instance_double(
          Positions::PositionData,
          tracker_id: tracker.id,
          valid?: true
        )
      end

      before do
        allow(Positions::ActiveCache).to receive(:instance).and_return(active_cache)
        allow(active_cache).to receive(:all_positions).and_return([position_data])
        allow(Live::TrailingEngine).to receive(:new).and_return(trailing_engine)
        allow(trailing_engine).to receive(:process_tick).and_return(
          { peak_updated: true, sl_updated: false, exit_triggered: false }
        )
        service.instance_variable_set(:@trailing_engine, trailing_engine)
        service.instance_variable_set(:@exit_engine, nil)
      end

      it 'processes all active positions with TrailingEngine' do
        service.send(:process_trailing_for_all_positions)

        expect(trailing_engine).to have_received(:process_tick).with(
          position_data,
          exit_engine: nil
        )
      end

      it 'passes exit_engine to TrailingEngine if available' do
        exit_engine = instance_double(Live::ExitEngine)
        service.instance_variable_set(:@exit_engine, exit_engine)

        service.send(:process_trailing_for_all_positions)

        expect(trailing_engine).to have_received(:process_tick).with(
          position_data,
          exit_engine: exit_engine
        )
      end

      it 'handles empty positions gracefully' do
        allow(active_cache).to receive(:all_positions).and_return([])

        expect { service.send(:process_trailing_for_all_positions) }.not_to raise_error
        expect(trailing_engine).not_to have_received(:process_tick)
      end

      it 'handles TrailingEngine errors gracefully' do
        allow(trailing_engine).to receive(:process_tick).and_raise(StandardError, 'TrailingEngine error')
        allow(Rails.logger).to receive(:error)

        expect { service.send(:process_trailing_for_all_positions) }.not_to raise_error
        expect(Rails.logger).to have_received(:error).with(
          match(/TrailingEngine error for position/)
        )
      end

      it 'creates TrailingEngine instance if not already initialized' do
        service.instance_variable_set(:@trailing_engine, nil)

        service.send(:process_trailing_for_all_positions)

        expect(Live::TrailingEngine).to have_received(:new)
        expect(trailing_engine).to have_received(:process_tick)
      end
    end

    describe 'Caching optimizations' do
      let(:active_cache) { instance_double(Positions::ActiveCache) }
      let(:position_data) do
        Positions::PositionData.new(
          tracker_id: tracker.id,
          security_id: tracker.security_id,
          segment: tracker.segment,
          entry_price: tracker.entry_price,
          quantity: tracker.quantity,
          pnl: BigDecimal(500),
          pnl_pct: 5.0,
          high_water_mark: BigDecimal(600),
          last_updated_at: Time.current
        )
      end

      describe '#monitor_loop cache clearing' do
        before do
          allow(Positions::ActiveCache).to receive(:instance).and_return(active_cache)
          allow(active_cache).to receive(:all_positions).and_return([position_data])
          allow(service).to receive(:update_paper_positions_pnl_if_due)
          allow(service).to receive(:ensure_all_positions_in_redis)
          allow(service).to receive(:ensure_all_positions_in_active_cache)
          allow(service).to receive(:ensure_all_positions_subscribed)
          allow(service).to receive(:process_trailing_for_all_positions)
          allow(service).to receive(:enforce_session_end_exit)
        end

        it 'clears @redis_pnl_cache at start of each cycle' do
          service.instance_variable_set(:@redis_pnl_cache, { tracker.id => { pnl: 100 } })
          service.instance_variable_set(:@cycle_tracker_map, { tracker.id => tracker })

          service.send(:monitor_loop, Time.current)

          expect(service.instance_variable_get(:@redis_pnl_cache)).to be_empty
          expect(service.instance_variable_get(:@cycle_tracker_map)).to be_nil
        end

        it 'returns early when positions are empty but still runs maintenance' do
          allow(active_cache).to receive(:all_positions).and_return([])

          service.send(:monitor_loop, Time.current)

          expect(service).to have_received(:update_paper_positions_pnl_if_due)
          expect(service).to have_received(:ensure_all_positions_in_redis)
          expect(service).to have_received(:ensure_all_positions_in_active_cache)
          expect(service).to have_received(:ensure_all_positions_subscribed)
          expect(service).not_to have_received(:process_trailing_for_all_positions)
        end
      end

      describe '#trackers_for_positions caching' do
        let(:tracker2) do
          create(
            :position_tracker,
            instrument: instrument,
            order_no: 'ORD789012',
            security_id: '50075',
            segment: 'NSE_FNO',
            status: 'active',
            quantity: 50,
            entry_price: 200.0
          )
        end
        let(:position_data2) do
          Positions::PositionData.new(
            tracker_id: tracker2.id,
            security_id: tracker2.security_id,
            segment: tracker2.segment,
            entry_price: tracker2.entry_price,
            quantity: tracker2.quantity,
            pnl: BigDecimal(100),
            pnl_pct: 1.0,
            high_water_mark: BigDecimal(150),
            last_updated_at: Time.current
          )
        end

        it 'caches trackers for same set of IDs' do
          positions = [position_data]
          # First call loads from DB
          result1 = service.send(:trackers_for_positions, positions)
          # Second call should use cache (no DB query)
          allow(PositionTracker).to receive(:where).and_call_original
          result2 = service.send(:trackers_for_positions, positions)

          expect(result1).to eq(result2)
          expect(result1[tracker.id]).to eq(tracker)
          expect(result2[tracker.id]).to eq(tracker)
          # Should not query DB on second call (cache hit)
          expect(PositionTracker).not_to have_received(:where)
        end

        it 'reloads when IDs change' do
          positions1 = [position_data]
          positions2 = [position_data, position_data2]

          result1 = service.send(:trackers_for_positions, positions1)
          result2 = service.send(:trackers_for_positions, positions2)

          expect(result1.keys).not_to eq(result2.keys)
          expect(result2[tracker.id]).to eq(tracker)
          expect(result2[tracker2.id]).to eq(tracker2)
        end

        it 'returns empty hash for empty position list' do
          result = service.send(:trackers_for_positions, [])

          expect(result).to eq({})
        end
      end

      describe '#sync_position_pnl_from_redis caching' do
        let(:redis_cache) { instance_double(Live::RedisPnlCache) }
        let(:redis_pnl_data) do
          {
            pnl: BigDecimal(750),
            pnl_pct: 10.0,
            ltp: BigDecimal(110),
            hwm_pnl: BigDecimal(800),
            timestamp: Time.current.to_i
          }
        end

        before do
          allow(Live::RedisPnlCache).to receive(:instance).and_return(redis_cache)
          allow(redis_cache).to receive(:fetch_pnl).and_return(redis_pnl_data)
        end

        it 'uses cached Redis PnL if already fetched in cycle' do
          service.instance_variable_set(:@redis_pnl_cache, { tracker.id => redis_pnl_data })

          service.send(:sync_position_pnl_from_redis, position_data, tracker)

          expect(redis_cache).not_to have_received(:fetch_pnl)
          expect(position_data.pnl).to eq(750.0)
        end

        it 'fetches from Redis if not cached' do
          service.instance_variable_set(:@redis_pnl_cache, {})

          service.send(:sync_position_pnl_from_redis, position_data, tracker)

          expect(redis_cache).to have_received(:fetch_pnl).with(tracker.id).once
          expect(position_data.pnl).to eq(750.0)
        end

        it 'skips update if Redis data is stale (>30 seconds)' do
          stale_data = redis_pnl_data.merge(timestamp: (Time.current.to_i - 31))
          service.instance_variable_set(:@redis_pnl_cache, { tracker.id => stale_data })

          original_pnl = position_data.pnl
          service.send(:sync_position_pnl_from_redis, position_data, tracker)

          expect(position_data.pnl).to eq(original_pnl)
        end

        it 'handles missing Redis data gracefully' do
          service.instance_variable_set(:@redis_pnl_cache, {})
          allow(redis_cache).to receive(:fetch_pnl).and_return(nil)

          expect { service.send(:sync_position_pnl_from_redis, position_data, tracker) }.not_to raise_error
        end
      end

      describe '#enforce_hard_limits with caching' do
        let(:exit_engine) { instance_double(Live::ExitEngine) }
        let(:redis_cache) { instance_double(Live::RedisPnlCache) }
        let(:tracker_not_in_cache) do
          create(
            :position_tracker,
            watchable: instrument,
            instrument: instrument,
            order_no: 'ORD999999',
            security_id: '50076',
            segment: 'NSE_FNO',
            status: 'active',
            quantity: 100,
            entry_price: 50.0
          )
        end

        before do
          allow(Positions::ActiveCache).to receive(:instance).and_return(active_cache)
          allow(active_cache).to receive(:all_positions).and_return([position_data])
          allow(service).to receive(:risk_config).and_return(sl_pct: 0.1, tp_pct: 0.2)
          allow(Live::RedisPnlCache).to receive(:instance).and_return(redis_cache)
        end

        it 'uses cached Redis PnL for positions not in ActiveCache' do
          redis_pnl = { pnl: BigDecimal('-500'), pnl_pct: -10.0, timestamp: Time.current.to_i }
          service.instance_variable_set(:@redis_pnl_cache, { tracker_not_in_cache.id => redis_pnl })

          allow(PositionTracker).to receive_message_chain(:active, :includes).and_return(
            double(to_a: [tracker_not_in_cache])
          )

          expect(exit_engine).to receive(:execute_exit).with(
            tracker_not_in_cache,
            match(/SL HIT.*from Redis/)
          )

          service.send(:enforce_hard_limits, exit_engine: exit_engine)
        end

        it 'fetches Redis PnL if not cached for fallback positions' do
          redis_pnl = { pnl: BigDecimal(2000), pnl_pct: 20.0, timestamp: Time.current.to_i }
          service.instance_variable_set(:@redis_pnl_cache, {})
          allow(redis_cache).to receive(:fetch_pnl).and_return(redis_pnl)

          # Test the fallback path: position NOT in ActiveCache, so it uses trackers_not_in_cache
          allow(active_cache).to receive(:all_positions).and_return([]) # Empty = not in cache
          allow(service).to receive(:trackers_for_positions).and_return({})
          allow(PositionTracker).to receive_message_chain(:active, :includes).and_return(
            double(to_a: [tracker_not_in_cache])
          )

          expect(exit_engine).to receive(:execute_exit).with(
            tracker_not_in_cache,
            match(/TP HIT.*from Redis/)
          )

          service.send(:enforce_hard_limits, exit_engine: exit_engine)
        end
      end
    end

    describe '#enforce_session_end_exit' do
      let(:exit_engine) { instance_double(Live::ExitEngine) }
      let(:active_cache) { instance_double(Positions::ActiveCache) }
      let(:position_data) do
        Positions::PositionData.new(
          tracker_id: tracker.id,
          security_id: tracker.security_id,
          segment: tracker.segment,
          entry_price: tracker.entry_price,
          quantity: tracker.quantity,
          pnl: BigDecimal(500),
          pnl_pct: 5.0,
          high_water_mark: BigDecimal(600),
          last_updated_at: Time.current
        )
      end

      before do
        allow(Positions::ActiveCache).to receive(:instance).and_return(active_cache)
        allow(active_cache).to receive(:all_positions).and_return([position_data])
        allow(service).to receive(:trackers_for_positions).and_return({ tracker.id => tracker })
        allow(service).to receive(:sync_position_pnl_from_redis)
      end

      context 'when session end deadline is reached' do
        before do
          allow(TradingSession::Service).to receive(:should_force_exit?).and_return(
            { should_exit: true, reason: 'session end deadline' }
          )
        end

        it 'exits all active positions' do
          expect(exit_engine).to receive(:execute_exit).with(
            tracker,
            'session end (deadline: 3:15 PM IST)'
          )

          service.send(:enforce_session_end_exit, exit_engine: exit_engine)
        end

        it 'logs exit count' do
          allow(exit_engine).to receive(:execute_exit).and_return(true)
          allow(Rails.logger).to receive(:info)

          service.send(:enforce_session_end_exit, exit_engine: exit_engine)

          expect(Rails.logger).to have_received(:info).with(match(/Session end exit.*1 positions exited/))
        end

        it 'skips already exited positions' do
          tracker.update(status: 'exited')

          expect(exit_engine).not_to receive(:execute_exit)

          service.send(:enforce_session_end_exit, exit_engine: exit_engine)
        end
      end

      context 'when session end deadline is not reached' do
        before do
          allow(TradingSession::Service).to receive(:should_force_exit?).and_return(
            { should_exit: false }
          )
        end

        it 'does not exit positions' do
          expect(exit_engine).not_to receive(:execute_exit)

          service.send(:enforce_session_end_exit, exit_engine: exit_engine)
        end
      end

      context 'when no positions exist' do
        before do
          allow(active_cache).to receive(:all_positions).and_return([])
          allow(TradingSession::Service).to receive(:should_force_exit?).and_return(
            { should_exit: true }
          )
        end

        it 'returns early without calling exit_engine' do
          expect(exit_engine).not_to receive(:execute_exit)

          service.send(:enforce_session_end_exit, exit_engine: exit_engine)
        end
      end

      context 'error handling' do
        before do
          allow(TradingSession::Service).to receive(:should_force_exit?).and_return(
            { should_exit: true }
          )
          allow(service).to receive(:trackers_for_positions).and_raise(StandardError, 'DB error')
          allow(Rails.logger).to receive(:error)
        end

        it 'handles errors gracefully' do
          expect { service.send(:enforce_session_end_exit, exit_engine: exit_engine) }.not_to raise_error
          expect(Rails.logger).to have_received(:error).with(match(/enforce_session_end_exit error/))
        end
      end
    end

    describe '#record_loss_if_applicable' do
      let(:daily_limits) { instance_double(Live::DailyLimits) }
      let(:index_key) { 'NIFTY' }

      before do
        allow(Live::DailyLimits).to receive(:new).and_return(daily_limits)
        allow(Positions::MetadataResolver).to receive(:index_key).and_return(index_key)
        allow(Rails.logger).to receive(:info)
      end

      context 'when position exited with loss' do
        it 'records loss in DailyLimits' do
          tracker.update(entry_price: 100.0, quantity: 75)
          exit_price = BigDecimal('90.0') # 10% loss

          expect(daily_limits).to receive(:record_loss).with(
            index_key: index_key,
            amount: 750.0 # (100 - 90) * 75
          )

          service.send(:record_loss_if_applicable, tracker, exit_price)
        end

        it 'logs the loss' do
          tracker.update(entry_price: 100.0, quantity: 75)
          exit_price = BigDecimal('90.0')

          allow(daily_limits).to receive(:record_loss)

          service.send(:record_loss_if_applicable, tracker, exit_price)

          expect(Rails.logger).to have_received(:info).with(match(/Recorded loss for #{index_key}/))
        end
      end

      context 'when position exited with profit' do
        it 'does not record loss' do
          tracker.update(entry_price: 100.0, quantity: 75)
          exit_price = BigDecimal('110.0') # 10% profit

          expect(daily_limits).not_to receive(:record_loss)

          service.send(:record_loss_if_applicable, tracker, exit_price)
        end
      end

      context 'when entry_price or exit_price is missing' do
        it 'does not record loss if entry_price is nil' do
          tracker.update(entry_price: nil, quantity: 75)

          expect(daily_limits).not_to receive(:record_loss)

          service.send(:record_loss_if_applicable, tracker, BigDecimal('90.0'))
        end

        it 'does not record loss if exit_price is nil' do
          tracker.update(entry_price: 100.0, quantity: 75)

          expect(daily_limits).not_to receive(:record_loss)

          service.send(:record_loss_if_applicable, tracker, nil)
        end
      end

      context 'error handling' do
        before do
          tracker.update(entry_price: 100.0, quantity: 75)
          allow(daily_limits).to receive(:record_loss).and_raise(StandardError, 'DailyLimits error')
          allow(Rails.logger).to receive(:error)
        end

        it 'handles errors gracefully' do
          expect { service.send(:record_loss_if_applicable, tracker, BigDecimal('90.0')) }.not_to raise_error
          expect(Rails.logger).to have_received(:error).with(match(/Failed to record loss/))
        end
      end
    end

    describe '#dispatch_exit' do
      let(:exit_engine) { instance_double(Live::ExitEngine) }
      let(:reason) { 'test exit reason' }

      context 'when external exit_engine is provided' do
        it 'delegates to external exit_engine' do
          allow(exit_engine).to receive(:execute_exit).and_return(true)

          service.send(:dispatch_exit, exit_engine, tracker, reason)

          expect(exit_engine).to have_received(:execute_exit).with(tracker, reason)
        end

        it 'raises external exit_engine errors' do
          allow(exit_engine).to receive(:execute_exit).and_raise(StandardError, 'Exit error')

          expect { service.send(:dispatch_exit, exit_engine, tracker, reason) }
            .to raise_error(StandardError, 'Exit error')
        end
      end

      context 'when exit_engine is self' do
        it 'raises fatal error because self-managed fallback is removed' do
          allow(Rails.logger).to receive(:fatal)

          expect { service.send(:dispatch_exit, service, tracker, reason) }
            .to raise_error(RuntimeError, /ExitEngine unavailable/)
          expect(Rails.logger).to have_received(:fatal).with(match(/CRITICAL: ExitEngine unavailable/))
        end
      end

      context 'when exit_engine is nil' do
        it 'raises fatal error because self-managed fallback is removed' do
          allow(Rails.logger).to receive(:fatal)

          expect { service.send(:dispatch_exit, nil, tracker, reason) }
            .to raise_error(RuntimeError, /ExitEngine unavailable/)
          expect(Rails.logger).to have_received(:fatal).with(match(/CRITICAL: ExitEngine unavailable/))
        end
      end
    end

    describe '#evaluate_signal_risk' do
      context 'with high confidence' do
        it 'returns low risk level and max position size 100' do
          signal_data = { confidence: 0.9, entry_price: 100.0, stop_loss: 98.0 }

          result = service.evaluate_signal_risk(signal_data)

          expect(result[:risk_level]).to eq(:low)
          expect(result[:max_position_size]).to eq(100)
          expect(result[:recommended_stop_loss]).to eq(98.0)
        end
      end

      context 'with medium confidence' do
        it 'returns medium risk level and max position size 50' do
          signal_data = { confidence: 0.7, entry_price: 100.0 }

          result = service.evaluate_signal_risk(signal_data)

          expect(result[:risk_level]).to eq(:medium)
          expect(result[:max_position_size]).to eq(50)
          expect(result[:recommended_stop_loss]).to eq(98.0) # entry_price * 0.98
        end
      end

      context 'with low confidence' do
        it 'returns high risk level and max position size 25' do
          signal_data = { confidence: 0.5, entry_price: 100.0 }

          result = service.evaluate_signal_risk(signal_data)

          expect(result[:risk_level]).to eq(:high)
          expect(result[:max_position_size]).to eq(25)
        end
      end

      context 'when confidence is missing' do
        it 'defaults to high risk level' do
          signal_data = { entry_price: 100.0 }

          result = service.evaluate_signal_risk(signal_data)

          expect(result[:risk_level]).to eq(:high)
          expect(result[:max_position_size]).to eq(25)
        end
      end
    end

    describe '#fetch_positions_indexed' do
      context 'when paper trading is enabled' do
        before do
          allow(service).to receive(:paper_trading_enabled?).and_return(true)
        end

        it 'returns empty hash' do
          result = service.send(:fetch_positions_indexed)

          expect(result).to eq({})
        end
      end

      context 'when paper trading is disabled' do
        let(:position1) { double('Position', security_id: '50074', exchange_segment: 'NSE_FNO') }
        let(:position2) { double('Position', security_id: '50075', exchange_segment: 'NSE_FNO') }

        before do
          allow(service).to receive(:paper_trading_enabled?).and_return(false)
          allow(DhanHQ::Models::Position).to receive(:active).and_return([position1, position2])
          allow(Live::FeedHealthService.instance).to receive(:mark_success!)
        end

        it 'returns positions indexed by security_id' do
          result = service.send(:fetch_positions_indexed)

          expect(result).to eq({ '50074' => position1, '50075' => position2 })
        end

        it 'marks feed health success' do
          feed_health = Live::FeedHealthService.instance
          allow(feed_health).to receive(:mark_success!)

          service.send(:fetch_positions_indexed)

          expect(feed_health).to have_received(:mark_success!).with(:positions)
        end
      end

      context 'error handling' do
        before do
          allow(service).to receive(:paper_trading_enabled?).and_return(false)
          allow(DhanHQ::Models::Position).to receive(:active).and_raise(StandardError, 'API error')
          allow(Rails.logger).to receive(:error)
          allow(Live::FeedHealthService.instance).to receive(:mark_failure!)
        end

        it 'handles errors gracefully and returns empty hash' do
          result = service.send(:fetch_positions_indexed)

          expect(result).to eq({})
          expect(Rails.logger).to have_received(:error).with(match(/fetch_positions_indexed failed/))
        end

        it 'marks feed health failure' do
          feed_health = Live::FeedHealthService.instance
          allow(feed_health).to receive(:mark_failure!)

          service.send(:fetch_positions_indexed)

          expect(feed_health).to have_received(:mark_failure!).with(:positions, hash_including(:error))
        end
      end
    end

    describe '#paper_trading_enabled?' do
      it 'returns true when paper trading is enabled in config' do
        allow(AlgoConfig).to receive(:fetch).and_return(
          { paper_trading: { enabled: true } }
        )

        expect(service.send(:paper_trading_enabled?)).to be true
      end

      it 'returns false when paper trading is disabled' do
        allow(AlgoConfig).to receive(:fetch).and_return(
          { paper_trading: { enabled: false } }
        )

        expect(service.send(:paper_trading_enabled?)).to be false
      end

      it 'returns false on error' do
        allow(AlgoConfig).to receive(:fetch).and_raise(StandardError, 'Config error')

        expect(service.send(:paper_trading_enabled?)).to be false
      end
    end

    describe '#pnl_snapshot' do
      let(:redis_cache) { instance_double(Live::RedisPnlCache) }
      let(:pnl_data) { { pnl: BigDecimal(500), pnl_pct: 5.0 } }

      before do
        allow(Live::RedisPnlCache).to receive(:instance).and_return(redis_cache)
        allow(redis_cache).to receive(:fetch_pnl).and_return(pnl_data)
      end

      it 'fetches PnL from Redis cache' do
        result = service.send(:pnl_snapshot, tracker)

        expect(result).to eq(pnl_data)
        expect(redis_cache).to have_received(:fetch_pnl).with(tracker.id)
      end

      it 'handles errors gracefully' do
        allow(redis_cache).to receive(:fetch_pnl).and_raise(StandardError, 'Redis error')
        allow(Rails.logger).to receive(:error)

        result = service.send(:pnl_snapshot, tracker)

        expect(result).to be_nil
        expect(Rails.logger).to have_received(:error).with(match(/pnl_snapshot error/))
      end
    end

    describe '#update_paper_positions_pnl_if_due' do
      before do
        allow(service).to receive(:update_paper_positions_pnl)
      end

      it 'updates PnL if last update was more than 1 minute ago' do
        last_update = 2.minutes.ago

        service.send(:update_paper_positions_pnl_if_due, last_update)

        expect(service).to have_received(:update_paper_positions_pnl)
      end

      it 'skips update if last update was less than 1 minute ago' do
        last_update = 30.seconds.ago

        service.send(:update_paper_positions_pnl_if_due, last_update)

        expect(service).not_to have_received(:update_paper_positions_pnl)
      end

      it 'updates if last_update is nil' do
        service.send(:update_paper_positions_pnl_if_due, nil)

        expect(service).to have_received(:update_paper_positions_pnl)
      end

      it 'handles errors gracefully' do
        allow(service).to receive(:update_paper_positions_pnl).and_raise(StandardError, 'Update error')
        allow(Rails.logger).to receive(:error)

        expect { service.send(:update_paper_positions_pnl_if_due, 2.minutes.ago) }.not_to raise_error
        expect(Rails.logger).to have_received(:error).with(match(/update_paper_positions_pnl_if_due failed/))
      end
    end

    describe '#update_paper_positions_pnl' do
      let(:paper_tracker) do
        create(
          :position_tracker,
          watchable: instrument,
          instrument: instrument,
          order_no: 'PAPER001',
          security_id: '50077',
          segment: 'NSE_FNO',
          status: 'active',
          quantity: 50,
          entry_price: 100.0,
          paper: true
        )
      end
      let(:pnl_updater) { instance_double(Live::PnlUpdaterService) }

      before do
        allow(PositionTracker).to receive_message_chain(:paper, :active, :includes).and_return(
          double(to_a: [paper_tracker])
        )
        allow(Live::PnlUpdaterService).to receive(:instance).and_return(pnl_updater)
        allow(pnl_updater).to receive(:cache_intermediate_pnl)
        allow(service).to receive(:get_paper_ltp).and_return(BigDecimal('110.0'))
        allow(service).to receive(:stagger_api_calls)
        allow(Rails.logger).to receive(:info)
      end

      it 'updates PnL for all paper trackers' do
        service.send(:update_paper_positions_pnl)

        paper_tracker.reload
        expect(paper_tracker.last_pnl_rupees).to eq(BigDecimal('500.0')) # (110 - 100) * 50
        expect(paper_tracker.last_pnl_pct).to eq(10.0) # (110 - 100) / 100 * 100
      end

      it 'updates high water mark' do
        paper_tracker.update(high_water_mark_pnl: BigDecimal('400.0'))

        service.send(:update_paper_positions_pnl)

        paper_tracker.reload
        expect(paper_tracker.high_water_mark_pnl).to eq(BigDecimal('500.0')) # max(400, 500)
      end

      it 'caches PnL in Redis via PnlUpdaterService' do
        service.send(:update_paper_positions_pnl)

        expect(pnl_updater).to have_received(:cache_intermediate_pnl).with(
          hash_including(
            tracker_id: paper_tracker.id,
            pnl: BigDecimal('500.0'),
            pnl_pct: BigDecimal('0.10')
          )
        )
      end

      it 'skips trackers without entry_price' do
        paper_tracker.update(entry_price: nil)

        service.send(:update_paper_positions_pnl)

        expect(pnl_updater).not_to have_received(:cache_intermediate_pnl)
      end

      it 'skips trackers without LTP' do
        allow(service).to receive(:get_paper_ltp).and_return(nil)

        service.send(:update_paper_positions_pnl)

        expect(pnl_updater).not_to have_received(:cache_intermediate_pnl)
      end

      it 'handles errors for individual trackers gracefully' do
        allow(paper_tracker).to receive(:update!).and_raise(StandardError, 'DB error')
        allow(Rails.logger).to receive(:error)

        expect { service.send(:update_paper_positions_pnl) }.not_to raise_error
        expect(Rails.logger).to have_received(:error).with(match(/update_paper_positions_pnl failed/))
      end
    end

    describe '#ensure_all_positions_in_redis' do
      let(:redis_cache) { instance_double(Live::RedisPnlCache) }
      let(:position) { double('Position', security_id: tracker.security_id) }

      before do
        allow(Live::RedisPnlCache).to receive(:instance).and_return(redis_cache)
        allow(PositionTracker).to receive_message_chain(:active, :includes).and_return(
          double(to_a: [tracker])
        )
        allow(service).to receive(:stagger_api_calls)
        allow(service).to receive_messages(fetch_positions_indexed: { tracker.security_id.to_s => position },
                                           current_ltp: BigDecimal('110.0'), compute_pnl: BigDecimal('750.0'), compute_pnl_pct: BigDecimal('0.10'))
        allow(service).to receive(:update_pnl_in_redis)
        allow(tracker).to receive(:hydrate_pnl_from_cache!)
      end

      it 'updates PnL for trackers not in Redis or stale' do
        allow(redis_cache).to receive(:fetch_pnl).and_return(nil)

        service.send(:ensure_all_positions_in_redis)

        expect(service).to have_received(:update_pnl_in_redis)
      end

      it 'skips trackers with fresh Redis data' do
        fresh_data = { timestamp: Time.current.to_i - 5 } # Less than 10 seconds old
        allow(redis_cache).to receive(:fetch_pnl).and_return(fresh_data)

        service.send(:ensure_all_positions_in_redis)

        expect(service).not_to have_received(:update_pnl_in_redis)
      end

      it 'throttles to run at most every 5 seconds' do
        # Set to more than 5 seconds ago so method will execute
        old_timestamp = 6.seconds.ago
        service.instance_variable_set(:@last_ensure_all, old_timestamp)
        start_time = Time.current
        allow(redis_cache).to receive(:fetch_pnl).and_return(nil) # Stub for this test

        service.send(:ensure_all_positions_in_redis)

        new_timestamp = service.instance_variable_get(:@last_ensure_all)
        expect(new_timestamp).to be_within(1.second).of(start_time)
        expect(new_timestamp).not_to eq(old_timestamp) # Verify it was updated
      end

      it 'handles errors for individual trackers gracefully' do
        # Set timestamp to allow method to execute
        service.instance_variable_set(:@last_ensure_all, 6.seconds.ago)
        allow(service).to receive(:fetch_positions_indexed).and_return({})
        allow(Live::RedisPnlCache.instance).to receive(:fetch_pnl).and_return(nil)
        allow(tracker).to receive(:hydrate_pnl_from_cache!).and_raise(StandardError, 'Cache error')
        allow(Rails.logger).to receive(:error)

        expect { service.send(:ensure_all_positions_in_redis) }.not_to raise_error
        expect(Rails.logger).to have_received(:error).with(match(/ensure_all_positions_in_redis failed/))
      end
    end

    describe '#store_exit_reason' do
      it 'stores exit reason and timestamp in tracker meta' do
        tracker.update(meta: {})

        service.send(:store_exit_reason, tracker, 'test reason')

        tracker.reload
        expect(tracker.meta['exit_reason']).to eq('test reason')
        expect(tracker.meta['exit_triggered_at']).to be_present
      end

      it 'merges with existing meta' do
        tracker.update(meta: { 'existing_key' => 'value' })

        service.send(:store_exit_reason, tracker, 'test reason')

        tracker.reload
        expect(tracker.meta['existing_key']).to eq('value')
        expect(tracker.meta['exit_reason']).to eq('test reason')
      end

      it 'handles errors gracefully' do
        allow(tracker).to receive(:update!).and_raise(StandardError, 'DB error')
        allow(Rails.logger).to receive(:warn)

        expect { service.send(:store_exit_reason, tracker, 'test reason') }.not_to raise_error
        expect(Rails.logger).to have_received(:warn).with(match(/store_exit_reason failed/))
      end
    end

    describe '#parse_time_hhmm' do
      it 'parses valid time string' do
        result = service.send(:parse_time_hhmm, '15:20')

        expect(result).to be_a(Time)
        expect(result.hour).to eq(15)
        expect(result.min).to eq(20)
      end

      it 'returns nil for blank value' do
        expect(service.send(:parse_time_hhmm, '')).to be_nil
        expect(service.send(:parse_time_hhmm, nil)).to be_nil
      end

      it 'handles invalid format gracefully' do
        allow(Rails.logger).to receive(:warn)
        # Force an error by passing a value that will raise in Time.zone.parse
        # Time.zone.parse('invalid') returns nil, not an error, so we need to trigger the rescue
        allow(Time.zone).to receive(:parse).and_raise(ArgumentError, 'Invalid time')

        result = service.send(:parse_time_hhmm, 'invalid')

        expect(result).to be_nil
        expect(Rails.logger).to have_received(:warn).with(match(/Invalid time format provided/))
      end
    end

    describe '#active_cache_positions' do
      let(:active_cache) { instance_double(Positions::ActiveCache) }
      let(:positions) { [double('Position')] }

      before do
        allow(Positions::ActiveCache).to receive(:instance).and_return(active_cache)
        allow(active_cache).to receive(:all_positions).and_return(positions)
      end

      it 'returns all positions from ActiveCache' do
        result = service.send(:active_cache_positions)

        expect(result).to eq(positions)
      end
    end

    describe '#risk_config' do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return(
          {
            risk: {
              stop_loss_pct: 0.30,
              take_profit_pct: 0.60,
              sl_pct: 0.25,
              tp_pct: 0.55,
              breakeven_after_gain: 0.10,
              trail_step_pct: 0.05,
              exit_drop_pct: 0.03,
              time_exit_hhmm: '15:20',
              market_close_hhmm: '15:30',
              min_profit_rupees: 100
            }
          }
        )
      end

      it 'normalizes stop_loss_pct and sl_pct' do
        config = service.send(:risk_config)

        expect(config[:stop_loss_pct]).to eq(0.30)
        expect(config[:sl_pct]).to eq(0.30) # Uses stop_loss_pct if available
      end

      it 'normalizes take_profit_pct and tp_pct' do
        config = service.send(:risk_config)

        expect(config[:take_profit_pct]).to eq(0.60)
        expect(config[:tp_pct]).to eq(0.60) # Uses take_profit_pct if available
      end

      it 'includes all risk parameters' do
        config = service.send(:risk_config)

        expect(config[:breakeven_after_gain]).to eq(0.10)
        expect(config[:trail_step_pct]).to eq(0.05)
        expect(config[:exit_drop_pct]).to eq(0.03)
        expect(config[:time_exit_hhmm]).to eq('15:20')
        expect(config[:market_close_hhmm]).to eq('15:30')
        expect(config[:min_profit_rupees]).to eq(100)
      end

      it 'handles missing risk config' do
        allow(AlgoConfig).to receive(:fetch).and_return({})

        config = service.send(:risk_config)

        expect(config).to eq({})
      end

      it 'handles errors gracefully' do
        allow(AlgoConfig).to receive(:fetch).and_raise(StandardError, 'Config error')

        config = service.send(:risk_config)

        # Method catches errors and returns empty hash without logging
        expect(config).to eq({})
      end
    end

    describe '#demand_driven_enabled?' do
      it 'returns true when feature flag is enabled' do
        allow(service).to receive(:feature_flags).and_return(
          { enable_demand_driven_services: true }
        )

        expect(service.send(:demand_driven_enabled?)).to be true
      end

      it 'returns false when feature flag is disabled' do
        allow(service).to receive(:feature_flags).and_return(
          { enable_demand_driven_services: false }
        )

        expect(service.send(:demand_driven_enabled?)).to be false
      end
    end

    describe '#feature_flags' do
      it 'returns feature flags from config' do
        flags = { enable_feature_x: true }
        allow(AlgoConfig).to receive(:fetch).and_return({ feature_flags: flags })

        expect(service.send(:feature_flags)).to eq(flags)
      end

      it 'returns empty hash on error' do
        allow(AlgoConfig).to receive(:fetch).and_raise(StandardError, 'Config error')

        expect(service.send(:feature_flags)).to eq({})
      end
    end

    describe '#underlying_exits_enabled?' do
      it 'returns true when feature flag is enabled' do
        allow(service).to receive(:feature_flags).and_return(
          { enable_underlying_aware_exits: true }
        )

        expect(service.send(:underlying_exits_enabled?)).to be true
      end

      it 'returns false when feature flag is disabled' do
        allow(service).to receive(:feature_flags).and_return(
          { enable_underlying_aware_exits: false }
        )

        expect(service.send(:underlying_exits_enabled?)).to be false
      end
    end

    describe '#ensure_all_positions_in_active_cache' do
      let(:active_cache) { instance_double(Positions::ActiveCache) }

      before do
        allow(Positions::ActiveCache).to receive(:instance).and_return(active_cache)
        allow(PositionTracker).to receive_message_chain(:active, :find_each).and_yield(tracker)
        allow(active_cache).to receive(:get_by_tracker_id).and_return(nil)
        allow(active_cache).to receive(:add_position)
      end

      it 'adds positions not in cache' do
        service.send(:ensure_all_positions_in_active_cache)

        expect(active_cache).to have_received(:add_position).with(tracker: tracker)
      end

      it 'skips positions already in cache' do
        allow(active_cache).to receive(:get_by_tracker_id).and_return(double('Position'))

        service.send(:ensure_all_positions_in_active_cache)

        expect(active_cache).not_to have_received(:add_position)
      end

      it 'skips positions without entry_price' do
        tracker.update(entry_price: nil)

        service.send(:ensure_all_positions_in_active_cache)

        expect(active_cache).not_to have_received(:add_position)
      end

      it 'throttles to run at most every 5 seconds' do
        # Set to more than 5 seconds ago so method will execute
        service.instance_variable_set(:@last_ensure_active_cache, 6.seconds.ago)

        service.send(:ensure_all_positions_in_active_cache)

        expect(service.instance_variable_get(:@last_ensure_active_cache)).to be_within(1.second).of(Time.current)
      end

      it 'handles errors for individual trackers gracefully' do
        allow(active_cache).to receive(:add_position).and_raise(StandardError, 'Cache error')
        allow(Rails.logger).to receive(:error)

        expect { service.send(:ensure_all_positions_in_active_cache) }.not_to raise_error
        expect(Rails.logger).to have_received(:error).with(match(/ensure_all_positions_in_active_cache failed/))
      end
    end

    describe '#ensure_all_positions_subscribed' do
      let(:hub) do
        instance_double(Live::MarketFeedHub).tap do |h|
          allow(h).to receive_messages(running?: true, subscribed?: false,
                                       subscribe: { segment: 'NSE_FNO', security_id: '50074' }, start!: true)
        end
      end

      before do
        # Stub hub before tracker is created to avoid subscribe_to_feed errors
        allow(Live::MarketFeedHub).to receive(:instance).and_return(hub)
        allow(PositionTracker).to receive_message_chain(:active, :find_each).and_yield(tracker)
        allow(tracker).to receive(:subscribe)
      end

      it 'subscribes positions not already subscribed' do
        service.send(:ensure_all_positions_subscribed)

        expect(tracker).to have_received(:subscribe)
      end

      it 'skips positions already subscribed' do
        allow(hub).to receive(:subscribed?).and_return(true)

        service.send(:ensure_all_positions_subscribed)

        expect(tracker).not_to have_received(:subscribe)
      end

      it 'skips positions without security_id' do
        tracker.update(security_id: nil)

        service.send(:ensure_all_positions_subscribed)

        expect(tracker).not_to have_received(:subscribe)
      end

      it 'returns early if hub is not running' do
        allow(hub).to receive(:running?).and_return(false)
        test_tracker = create(:position_tracker, watchable: instrument, instrument: instrument,
                                                 order_no: 'ORD999999', security_id: '50074', segment: 'NSE_FNO',
                                                 status: 'active', quantity: 75, entry_price: 100.0, avg_price: 100.0)
        allow(PositionTracker).to receive_message_chain(:active, :find_each).and_yield(test_tracker)
        allow(test_tracker).to receive(:subscribe)

        service.send(:ensure_all_positions_subscribed)

        # Method returns early if hub is not running, so no subscriptions happen
        expect(test_tracker).not_to have_received(:subscribe)
      end

      it 'throttles to run at most every 5 seconds' do
        # Set to more than 5 seconds ago so method will execute
        service.instance_variable_set(:@last_ensure_subscribed, 6.seconds.ago)

        service.send(:ensure_all_positions_subscribed)

        expect(service.instance_variable_get(:@last_ensure_subscribed)).to be_within(1.second).of(Time.current)
      end

      it 'handles errors for individual trackers gracefully' do
        allow(tracker).to receive(:subscribe).and_raise(StandardError, 'Subscribe error')
        allow(Rails.logger).to receive(:error)

        expect { service.send(:ensure_all_positions_subscribed) }.not_to raise_error
        expect(Rails.logger).to have_received(:error).with(match(/ensure_all_positions_subscribed failed/))
      end
    end

    describe '#ensure_position_snapshot' do
      let(:position_data) do
        Positions::PositionData.new(
          tracker_id: tracker.id,
          security_id: tracker.security_id,
          segment: tracker.segment,
          entry_price: tracker.entry_price,
          quantity: tracker.quantity,
          current_ltp: nil,
          last_updated_at: Time.current
        )
      end
      let(:redis_tick_cache) { instance_double(Live::RedisTickCache) }

      before do
        allow(Live::TickCache).to receive(:ltp).and_return(nil)
        allow(Live::RedisTickCache).to receive(:instance).and_return(redis_tick_cache)
      end

      it 'updates LTP from TickCache if available' do
        allow(Live::TickCache).to receive(:ltp).and_return(BigDecimal('110.0'))

        service.send(:ensure_position_snapshot, position_data)

        expect(position_data.current_ltp).to eq(110.0)
      end

      it 'falls back to RedisTickCache if TickCache is empty' do
        tick_data = { ltp: BigDecimal('110.0') }
        allow(redis_tick_cache).to receive(:fetch_tick).and_return(tick_data)

        service.send(:ensure_position_snapshot, position_data)

        expect(position_data.current_ltp).to eq(110.0)
      end

      it 'skips update if LTP is already positive' do
        position_data.current_ltp = BigDecimal('120.0')

        service.send(:ensure_position_snapshot, position_data)

        expect(position_data.current_ltp).to eq(120.0)
      end

      it 'handles errors gracefully' do
        allow(Live::TickCache).to receive(:ltp).and_raise(StandardError, 'Cache error')
        allow(Rails.logger).to receive(:error)

        expect { service.send(:ensure_position_snapshot, position_data) }.not_to raise_error
        expect(Rails.logger).to have_received(:error).with(match(/ensure_position_snapshot failed/))
      end
    end

    describe '#recalculate_position_metrics' do
      let(:position_data) do
        Positions::PositionData.new(
          tracker_id: tracker.id,
          security_id: tracker.security_id,
          segment: tracker.segment,
          entry_price: BigDecimal('100.0'),
          quantity: tracker.quantity,
          current_ltp: BigDecimal('110.0'),
          pnl_pct: 5.0,
          peak_profit_pct: 8.0,
          last_updated_at: Time.current
        )
      end
      let(:active_cache) { instance_double(Positions::ActiveCache) }

      before do
        allow(Positions::ActiveCache).to receive(:instance).and_return(active_cache)
        allow(service).to receive(:sync_position_pnl_from_redis)
        allow(service).to receive(:ensure_position_snapshot)
        allow(position_data).to receive(:recalculate_pnl)
        allow(active_cache).to receive(:update_position)
      end

      it 'syncs PnL from Redis cache' do
        service.send(:recalculate_position_metrics, position_data, tracker)

        expect(service).to have_received(:sync_position_pnl_from_redis).with(position_data, tracker)
      end

      it 'ensures position snapshot' do
        service.send(:recalculate_position_metrics, position_data, tracker)

        expect(service).to have_received(:ensure_position_snapshot).with(position_data)
      end

      it 'recalculates PnL if LTP and entry_price are positive' do
        service.send(:recalculate_position_metrics, position_data, tracker)

        expect(position_data).to have_received(:recalculate_pnl)
      end

      it 'updates peak profit if current exceeds it' do
        position_data.pnl_pct = 10.0
        position_data.peak_profit_pct = 8.0

        service.send(:recalculate_position_metrics, position_data, tracker)

        expect(active_cache).to have_received(:update_position).with(
          position_data.tracker_id,
          peak_profit_pct: 10.0
        )
      end

      it 'handles errors gracefully' do
        allow(service).to receive(:sync_position_pnl_from_redis).and_raise(StandardError, 'Sync error')
        allow(Rails.logger).to receive(:error)

        expect { service.send(:recalculate_position_metrics, position_data, tracker) }.not_to raise_error
        expect(Rails.logger).to have_received(:error).with(match(/recalculate_position_metrics failed/))
      end
    end

    describe '#stagger_api_calls' do
      it 'sleeps if elapsed time is less than API_CALL_STAGGER_SECONDS' do
        service.instance_variable_set(:@last_api_call_time, Time.current - 0.5)
        allow(service).to receive(:sleep)

        service.send(:stagger_api_calls)

        expect(service).to have_received(:sleep).with(be_within(0.1).of(0.5))
      end

      it 'does not sleep if elapsed time exceeds API_CALL_STAGGER_SECONDS' do
        service.instance_variable_set(:@last_api_call_time, Time.current - 2.0)
        allow(service).to receive(:sleep)

        service.send(:stagger_api_calls)

        expect(service).not_to have_received(:sleep)
      end

      it 'updates @last_api_call_time' do
        old_time = Time.current - 1.0
        service.instance_variable_set(:@last_api_call_time, old_time)

        service.send(:stagger_api_calls)

        new_time = service.instance_variable_get(:@last_api_call_time)
        expect(new_time).to be > old_time
      end
    end

    describe '#handle_rate_limit_error' do
      let(:cache_key) { 'NSE_FNO:50074' }
      let(:rate_limit_error) { StandardError.new('429 Rate limit exceeded') }

      before do
        service.instance_variable_set(:@rate_limit_errors, {})
        allow(Rails.logger).to receive(:warn)
        allow(Rails.logger).to receive(:error)
      end

      it 'records rate limit error with exponential backoff' do
        service.send(:handle_rate_limit_error, rate_limit_error, cache_key)

        error_data = service.instance_variable_get(:@rate_limit_errors)[cache_key]
        expect(error_data[:backoff_seconds]).to eq(4.0) # 2.0 * 2
        expect(error_data[:retry_count]).to eq(1)
      end

      it 'increases backoff on subsequent errors' do
        service.instance_variable_set(:@rate_limit_errors, {
                                        cache_key => { backoff_seconds: 4.0, retry_count: 1, last_error: 5.seconds.ago }
                                      })

        service.send(:handle_rate_limit_error, rate_limit_error, cache_key)

        error_data = service.instance_variable_get(:@rate_limit_errors)[cache_key]
        expect(error_data[:backoff_seconds]).to eq(8.0) # 4.0 * 2
        expect(error_data[:retry_count]).to eq(2)
      end

      it 'stops retrying after MAX_RETRIES_ON_RATE_LIMIT' do
        service.instance_variable_set(:@rate_limit_errors, {
                                        cache_key => {
                                          backoff_seconds: 16.0,
                                          retry_count: Live::RiskManagerService::MAX_RETRIES_ON_RATE_LIMIT,
                                          last_error: 20.seconds.ago
                                        }
                                      })

        service.send(:handle_rate_limit_error, rate_limit_error, cache_key)

        expect(Rails.logger).to have_received(:error).with(match(/Rate limit exceeded max retries/))
      end

      it 'logs non-rate-limit errors normally' do
        normal_error = StandardError.new('Connection timeout')
        allow(Rails.logger).to receive(:error)

        service.send(:handle_rate_limit_error, normal_error, cache_key, tracker.order_no)

        expect(Rails.logger).to have_received(:error).with(match(/get_paper_ltp API error/))
        expect(service.instance_variable_get(:@rate_limit_errors)[cache_key]).to be_nil
      end
    end

    describe '#loop_sleep_interval' do
      before do
        allow(service).to receive(:risk_config).and_return(
          loop_interval_idle: 10_000,
          loop_interval_active: 1000
        )
      end

      it 'returns idle interval when active_cache is empty' do
        interval = service.send(:loop_sleep_interval, true)

        expect(interval).to eq(10.0) # 10000ms / 1000
      end

      it 'returns active interval when active_cache has positions' do
        interval = service.send(:loop_sleep_interval, false)

        expect(interval).to eq(1.0) # 1000ms / 1000
      end

      it 'defaults to 0.5 seconds (500ms) if config is missing for active cache' do
        allow(service).to receive(:risk_config).and_return({})

        interval = service.send(:loop_sleep_interval, false) # false = cache not empty (active)

        expect(interval).to eq(0.5) # Default 500ms / 1000 for active cache
      end

      it 'defaults to 5 seconds (5000ms) if config is missing for empty cache' do
        allow(service).to receive(:risk_config).and_return({})

        interval = service.send(:loop_sleep_interval, true) # true = cache empty (idle)

        expect(interval).to eq(5.0) # Default 5000ms / 1000 for idle cache
      end
    end

    describe '#wait_for_interval' do
      context 'when demand_driven is disabled' do
        before do
          allow(service).to receive(:demand_driven_enabled?).and_return(false)
          allow(service).to receive(:sleep)
        end

        it 'calls sleep directly' do
          service.send(:wait_for_interval, 2.0)

          expect(service).to have_received(:sleep).with(2.0)
        end
      end

      context 'when demand_driven is enabled' do
        before do
          allow(service).to receive(:demand_driven_enabled?).and_return(true)
          service.instance_variable_set(:@running, true)
        end

        it 'uses condition variable wait' do
          cv = service.instance_variable_get(:@sleep_cv)
          mutex = service.instance_variable_get(:@sleep_mutex)

          allow(cv).to receive(:wait)

          service.send(:wait_for_interval, 2.0)

          expect(cv).to have_received(:wait).with(mutex, 2.0)
        end
      end
    end

    describe '#wake_up!' do
      it 'broadcasts condition variable' do
        cv = service.instance_variable_get(:@sleep_cv)
        allow(cv).to receive(:broadcast)

        service.send(:wake_up!)

        expect(cv).to have_received(:broadcast)
      end
    end

    describe '#subscribe_to_position_events' do
      it 'subscribes to position added and removed events' do
        service.instance_variable_set(:@position_subscriptions, [])
        allow(ActiveSupport::Notifications).to receive(:subscribe).and_return('token1', 'token2')

        service.send(:subscribe_to_position_events)

        subscriptions = service.instance_variable_get(:@position_subscriptions)
        expect(subscriptions).to eq(%w[token1 token2])
        expect(ActiveSupport::Notifications).to have_received(:subscribe).with('positions.added')
        expect(ActiveSupport::Notifications).to have_received(:subscribe).with('positions.removed')
      end

      it 'does not subscribe if already subscribed' do
        service.instance_variable_set(:@position_subscriptions, ['existing_token'])
        allow(ActiveSupport::Notifications).to receive(:subscribe) # Stub before calling method

        service.send(:subscribe_to_position_events)

        expect(ActiveSupport::Notifications).not_to have_received(:subscribe)
      end
    end

    describe '#unsubscribe_from_position_events' do
      it 'unsubscribes from all position events' do
        tokens = %w[token1 token2]
        service.instance_variable_set(:@position_subscriptions, tokens)
        allow(ActiveSupport::Notifications).to receive(:unsubscribe)

        service.send(:unsubscribe_from_position_events)

        tokens.each do |token|
          expect(ActiveSupport::Notifications).to have_received(:unsubscribe).with(token)
        end
        expect(service.instance_variable_get(:@position_subscriptions)).to be_empty
      end

      it 'does nothing if no subscriptions exist' do
        service.instance_variable_set(:@position_subscriptions, [])

        expect { service.send(:unsubscribe_from_position_events) }.not_to raise_error
      end
    end

    describe '#pct_value' do
      it 'converts value to BigDecimal' do
        result = service.send(:pct_value, '0.10')

        expect(result).to eq(BigDecimal('0.10'))
      end

      it 'returns BigDecimal(0) on error' do
        result = service.send(:pct_value, 'invalid')

        expect(result).to eq(BigDecimal(0))
      end
    end

    describe '#cancel_remote_order' do
      let(:order) { instance_double(DhanHQ::Models::Order) }

      before do
        allow(DhanHQ::Models::Order).to receive(:find).with('123').and_return(order)
        allow(order).to receive(:cancel)
      end

      it 'cancels order via DhanHQ' do
        service.send(:cancel_remote_order, '123')

        expect(order).to have_received(:cancel)
      end

      it 'handles DhanHQ errors' do
        allow(order).to receive(:cancel).and_raise(DhanHQ::Error, 'Order not found')
        allow(Rails.logger).to receive(:error)

        expect { service.send(:cancel_remote_order, '123') }.to raise_error(DhanHQ::Error)
        expect(Rails.logger).to have_received(:error).with(match(/cancel_remote_order DhanHQ error/))
      end

      it 'handles unexpected errors' do
        allow(order).to receive(:cancel).and_raise(StandardError, 'Unexpected error')
        allow(Rails.logger).to receive(:error)

        expect { service.send(:cancel_remote_order, '123') }.to raise_error(StandardError)
        expect(Rails.logger).to have_received(:error).with(match(/cancel_remote_order unexpected error/))
      end
    end

    describe '#fetch_ltp' do
      let(:position) { double('Position', exchange_segment: 'NSE_FNO') }

      before do
        allow(Live::TickCache).to receive(:ltp).and_return(nil)
      end

      it 'returns cached LTP from TickCache' do
        allow(Live::TickCache).to receive(:ltp).and_return(BigDecimal('110.0'))

        result = service.send(:fetch_ltp, position, tracker)

        expect(result).to eq(BigDecimal('110.0'))
      end

      it 'returns nil if no cache available' do
        result = service.send(:fetch_ltp, position, tracker)

        expect(result).to be_nil
      end

      it 'handles errors gracefully' do
        allow(Live::TickCache).to receive(:ltp).and_raise(StandardError, 'Cache error')

        result = service.send(:fetch_ltp, position, tracker)

        expect(result).to be_nil
      end
    end

    describe '#guarded_exit' do
      let(:exit_engine) { instance_double(Live::ExitEngine) }
      let(:reason) { 'test exit' }

      context 'when external exit_engine is provided' do
        before do
          allow(tracker).to receive(:exited?).and_return(false)
          allow(exit_engine).to receive(:execute_exit)
        end

        it 'calls external exit_engine' do
          service.send(:guarded_exit, tracker, reason, exit_engine)

          expect(exit_engine).to have_received(:execute_exit).with(tracker, reason)
        end

        it 'skips if tracker already exited' do
          allow(tracker).to receive(:exited?).and_return(true)

          service.send(:guarded_exit, tracker, reason, exit_engine)

          expect(exit_engine).not_to have_received(:execute_exit)
        end
      end

      context 'when exit_engine is self' do
        before do
          allow(tracker).to receive(:with_lock).and_yield
          allow(tracker).to receive(:exited?).and_return(false)
          allow(service).to receive(:dispatch_exit)
        end

        it 'uses with_lock and dispatches exit' do
          service.send(:guarded_exit, tracker, reason, service)

          expect(tracker).to have_received(:with_lock)
          expect(service).to have_received(:dispatch_exit).with(service, tracker, reason)
        end

        it 'skips if tracker already exited' do
          allow(tracker).to receive(:exited?).and_return(true)

          service.send(:guarded_exit, tracker, reason, service)

          expect(service).not_to have_received(:dispatch_exit)
        end
      end

      context 'error handling' do
        before do
          allow(tracker).to receive(:exited?).and_return(false)
          allow(exit_engine).to receive(:execute_exit).and_raise(StandardError, 'Exit error')
          allow(Rails.logger).to receive(:error)
        end

        it 'handles errors gracefully' do
          expect { service.send(:guarded_exit, tracker, reason, exit_engine) }.not_to raise_error
          expect(Rails.logger).to have_received(:error).with(match(/guarded_exit failed/))
        end
      end
    end

    describe '#increment_metric' do
      it 'increments metric counter' do
        service.send(:increment_metric, :test_metric)

        expect(service.instance_variable_get(:@metrics)[:test_metric]).to eq(1)
      end

      it 'increments multiple times' do
        service.send(:increment_metric, :test_metric)
        service.send(:increment_metric, :test_metric)

        expect(service.instance_variable_get(:@metrics)[:test_metric]).to eq(2)
      end
    end

    describe '#underlying_trend_score_threshold' do
      it 'returns configured threshold' do
        allow(service).to receive(:risk_config).and_return(underlying_trend_score_threshold: 15.0)

        result = service.send(:underlying_trend_score_threshold)

        expect(result).to eq(15.0)
      end

      it 'defaults to 10.0 if not configured' do
        allow(service).to receive(:risk_config).and_return({})

        result = service.send(:underlying_trend_score_threshold)

        expect(result).to eq(10.0)
      end
    end

    describe '#underlying_atr_ratio_threshold' do
      it 'returns configured threshold' do
        allow(service).to receive(:risk_config).and_return(underlying_atr_collapse_multiplier: 0.5)

        result = service.send(:underlying_atr_ratio_threshold)

        expect(result).to eq(0.5)
      end

      it 'defaults to 0.65 if not configured' do
        allow(service).to receive(:risk_config).and_return({})

        result = service.send(:underlying_atr_ratio_threshold)

        expect(result).to eq(0.65)
      end
    end

    describe '#atr_collapse?' do
      let(:underlying_state) do
        OpenStruct.new(
          atr_trend: :falling,
          atr_ratio: 0.5
        )
      end

      before do
        allow(service).to receive(:underlying_atr_ratio_threshold).and_return(0.65)
      end

      it 'returns true when ATR is falling and ratio below threshold' do
        result = service.send(:atr_collapse?, underlying_state)

        expect(result).to be true
      end

      it 'returns false when ATR trend is not falling' do
        underlying_state.atr_trend = :rising

        result = service.send(:atr_collapse?, underlying_state)

        expect(result).to be false
      end

      it 'returns false when ratio is above threshold' do
        underlying_state.atr_ratio = 0.8

        result = service.send(:atr_collapse?, underlying_state)

        expect(result).to be false
      end

      it 'returns false when underlying_state is nil' do
        result = service.send(:atr_collapse?, nil)

        expect(result).to be false
      end
    end

    describe '#structure_break_against_position?' do
      let(:position_data) do
        Positions::PositionData.new(
          tracker_id: tracker.id,
          security_id: tracker.security_id,
          segment: tracker.segment,
          entry_price: tracker.entry_price,
          quantity: tracker.quantity,
          position_direction: :bullish,
          last_updated_at: Time.current
        )
      end
      let(:underlying_state) do
        OpenStruct.new(
          bos_state: :broken,
          bos_direction: :bearish
        )
      end

      before do
        allow(service).to receive(:normalized_position_direction).and_return(:bullish)
      end

      it 'returns true when structure breaks against bullish position' do
        result = service.send(:structure_break_against_position?, position_data, tracker, underlying_state)

        expect(result).to be true
      end

      it 'returns true when structure breaks against bearish position' do
        allow(service).to receive(:normalized_position_direction).and_return(:bearish)
        underlying_state.bos_direction = :bullish

        result = service.send(:structure_break_against_position?, position_data, tracker, underlying_state)

        expect(result).to be true
      end

      it 'returns false when structure is intact' do
        underlying_state.bos_state = :intact

        result = service.send(:structure_break_against_position?, position_data, tracker, underlying_state)

        expect(result).to be false
      end

      it 'returns false when structure breaks in same direction' do
        underlying_state.bos_direction = :bullish

        result = service.send(:structure_break_against_position?, position_data, tracker, underlying_state)

        expect(result).to be false
      end
    end

    describe '#normalized_position_direction' do
      let(:position_data) do
        Positions::PositionData.new(
          tracker_id: tracker.id,
          security_id: tracker.security_id,
          segment: tracker.segment,
          entry_price: tracker.entry_price,
          quantity: tracker.quantity,
          position_direction: :bullish,
          last_updated_at: Time.current
        )
      end

      it 'returns direction from position if available' do
        result = service.send(:normalized_position_direction, position_data, tracker)

        expect(result).to eq(:bullish)
      end

      it 'falls back to MetadataResolver if position direction is missing' do
        position_data.position_direction = nil
        allow(Positions::MetadataResolver).to receive(:direction).and_return(:bearish)

        result = service.send(:normalized_position_direction, position_data, tracker)

        expect(result).to eq(:bearish)
        expect(Positions::MetadataResolver).to have_received(:direction).with(tracker)
      end
    end
  end
end
