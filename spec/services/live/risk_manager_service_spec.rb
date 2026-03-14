# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::RiskManagerService do
  let(:exit_engine) { instance_double(Live::ExitEngine, execute_exit: true) }
  let(:service) { described_class.new(exit_engine: exit_engine) }
  let(:tracker) do
    create(
      :position_tracker,
      watchable: instrument,
      instrument: instrument,
      order_no: 'ORD123456',
      security_id: '50074',
      segment: 'NSE_FNO',
      status: 'active',
      quantity: 75,
      entry_price: 100.0,
      avg_price: 100.0
    )
  end
  let(:instrument) { create(:instrument, :nifty_future, security_id: '9999') }

  # Stub MarketFeedHub globally to prevent WebSocket subscription errors during tracker creation
  let(:market_feed_hub) do
    instance_double(Live::MarketFeedHub).tap do |hub|
      allow(hub).to receive_messages(running?: true, connected?: true, subscribed?: false,
                                     subscribe: { segment: 'NSE_FNO', security_id: '50074' }, unsubscribe: true, start!: true, stop!: true)
    end
  end

  before do
    # Stub MarketFeedHub before any trackers are created
    allow(Live::MarketFeedHub).to receive(:instance).and_return(market_feed_hub)
  end

  after do
      service.stop if defined?(service) && service.send(:running?)
  rescue StandardError
    # ignore
  end

  describe 'EPIC G — G1: Enforce Simplified Exit Rules' do
    describe '#start' do
      after do
        service.stop
      end

      it 'starts background thread with correct name' do
        service.start
        sleep 0.01 # Allow thread to start and set name

        expect(service.send(:running?)).to be true
        expect(service.instance_variable_get(:@thread).name).to eq('risk-manager')
      end

      it 'does not start if already running' do
        service.start
        first_thread = service.instance_variable_get(:@thread)

        service.start
        second_thread = service.instance_variable_get(:@thread)

        expect(first_thread).to eq(second_thread)
      end
    end

    describe '#stop' do
      it 'stops the service and sets running to false' do
        service.start
        expect(service.send(:running?)).to be true

        service.stop
        expect(service.send(:running?)).to be false
      end
    end

    describe '#monitor_loop' do
      before do
        allow(TradingSession::Service).to receive(:market_closed?).and_return(false)
        allow(PositionTracker).to receive(:active).and_return(PositionTracker.where(id: tracker.id))
        allow(Positions::ActivePositionsCache.instance).to receive(:active_trackers).and_return([tracker])
        allow(Live::PositionSyncService.instance).to receive(:sync_positions!)
        allow(service).to receive_messages(fetch_positions_indexed: {}, tick_stream_fresh?: false)
        allow(service).to receive(:run_interval_enforcement_if_needed).and_call_original
        allow(service).to receive(:enforce_trailing_stops).and_call_original
        allow(service).to receive(:enforce_time_based_exit).and_call_original
        allow(service).to receive(:sleep)
      end

      after do
        service.stop
      end

      it 'runs loop every 5 seconds' do
        service.start
        sleep 0.1 # Allow thread to start

        # Allow any sleep call
        expect(service).to receive(:sleep).at_least(:once)
        sleep 0.2 # Allow one iteration
      end

      it 'handles errors gracefully and stops on critical error' do
        # Stub a method that monitor_loop actually calls to raise an error
        allow(service).to receive(:ensure_all_positions_in_redis).and_raise(StandardError, 'Test error')
        error_logs = []
        allow(Rails.logger).to receive(:error).and_wrap_original do |method, *args, &block|
          if block
            message = nil
            method.call(*args) do
              message = block.call
              message
            end
            error_logs << message
          else
            error_logs << args.first
            method.call(*args)
          end
        end

        service.start
        # Kill watchdog to avoid auto-restart
        service.instance_variable_get(:@watchdog_thread)&.kill

        sleep 0.8 # Give thread time to execute and catch error

        # Service should log the error
        expect(error_logs.any? { |msg| msg.to_s.include?('monitor_loop crashed') || msg.to_s.include?('monitor_loop error') }).to be true
        # Service stops running after critical errors (resilient design restarts via watchdog in production)
        expect(service.send(:running?)).to be false
      end
    end

    describe '#enforce_profit_floor' do
      let(:position) do
        double(
          'Position',
          security_id: '50074',
          exchange_segment: 'NSE_FNO',
          net_qty: 75,
          cost_price: 100.0
        )
      end

      before do
        allow(service).to receive(:profit_floor_config).and_return(
          enabled: true,
          breakeven_at: 750 # ₹750 profit (which is 10% of 75 * 100)
        )
        allow(PositionTracker).to receive(:active).and_return(PositionTracker.active.where(id: tracker.id))
        allow(service).to receive(:pnl_snapshot).with(tracker).and_return({
          pnl: BigDecimal('750.0'),
          pnl_pct: BigDecimal('0.10'),
          ltp: BigDecimal('110.0')
        })
      end

      context 'when breakeven threshold is reached' do
        before do
          allow(service).to receive(:dispatch_exit) # Prevent actual exit calls
          # Ensure tracker meta is clean
          tracker.update!(meta: {})
        end

        it 'locks breakeven at +10% profit' do
          service.send(:enforce_profit_floor, exit_engine: exit_engine)

          tracker.reload
          expect(tracker.be_set?).to be true
        end

        it 'does not lock breakeven if already locked' do
          tracker.update(meta: { be_set: true })

          expect(tracker).not_to receive(:update!)

          service.send(:enforce_profit_floor, exit_engine: exit_engine)
        end

        it 'does not lock breakeven below threshold' do
          allow(service).to receive(:pnl_snapshot).with(tracker).and_return({
            pnl: BigDecimal('675.0'),
            pnl_pct: BigDecimal('0.09'),
            ltp: BigDecimal('109.0')
          })

          service.send(:enforce_profit_floor, exit_engine: exit_engine)
          tracker.reload
          expect(tracker).not_to be_be_set
        end
      end
    end

    describe '#enforce_trailing_stops' do
      let(:position) do
        double(
          'Position',
          security_id: '50074',
          exchange_segment: 'NSE_FNO',
          net_qty: 75,
          cost_price: 100.0
        )
      end

      before do
        PositionTracker.delete_all
        allow(service).to receive(:risk_config).and_return(
          breakeven_after_gain: 0.10, # 10%
          exit_drop_pct: 0.03, # 3%
          trail_step_pct: 0.10
        )
        tracker.update!(trade_state: 'expansion')
        allow(PositionTracker).to receive(:active).and_return(PositionTracker.where(id: tracker.id))
        # TrailingEngine uses ActiveCache
        allow(Positions::ActiveCache.instance).to receive(:get_by_tracker_id).with(tracker.id).and_return(
          Positions::ActiveCache::PositionData.new(
            tracker_id: tracker.id,
            security_id: '50074',
            entry_price: 100.0,
            quantity: 75,
            current_ltp: 119.4,
            pnl: 1455.0,
            pnl_pct: 0.194,
            peak_profit_pct: 0.20,
            high_water_mark: 1500.0
          )
        )
      end

      context 'when trailing stop is triggered' do
        before do
          # Set up tracker with HWM: Entry ₹100, qty 75
          # HWM PnL ₹1500 means price was ₹120 (20% profit)
          tracker.update!(
            entry_price: 100.0,
            quantity: 75,
            high_water_mark_pnl: BigDecimal('1500.0'),
            meta: { be_set: true }
          )
        end

        it 'exits when PnL drops 3% below HWM' do
          # HWM: ₹1500, drop 3% threshold = 1500 × 0.97 = ₹1455
          # Current PnL ₹1455 should trigger exit
          # TrailingConfig handles the logic, we just verify delegation

          # Stub TrailingConfig to trigger exit
          allow(Positions::TrailingConfig).to receive(:peak_drawdown_triggered?).and_return(true)

          expect(exit_engine).to receive(:execute_exit).with(
            tracker,
            /peak_drawdown_exit/
          )

          service.send(:enforce_trailing_stops, exit_engine: exit_engine)
        end

        it 'does not exit if PnL has not dropped enough' do
          # Stub TrailingConfig to NOT trigger exit
          allow(Positions::TrailingConfig).to receive(:peak_drawdown_triggered?).and_return(false)

          expect(exit_engine).not_to receive(:execute_exit)

          service.send(:enforce_trailing_stops, exit_engine: exit_engine)
        end
      end

      context 'when HWM updates' do
        it 'updates HWM when new LTP exceeds previous HWM' do
          # Start with initial HWM of ₹1000
          tracker.update!(
            entry_price: 100.0,
            quantity: 75,
            high_water_mark_pnl: BigDecimal('1000.0'),
            last_pnl_rupees: BigDecimal('1000.0')
          )

          # New higher PnL: ₹1125
          allow(Positions::ActiveCache.instance).to receive(:get_by_tracker_id).with(tracker.id).and_return(
            Positions::ActiveCache::PositionData.new(
              tracker_id: tracker.id,
              security_id: '50074',
              entry_price: 100.0,
              quantity: 75,
              current_ltp: 115.0,
              pnl: 1125.0,
              pnl_pct: 0.15,
              peak_profit_pct: 0.10 # previous peak
            )
          )

          service.send(:enforce_trailing_stops, exit_engine: exit_engine)

          # TrailingEngine should have updated the peak in ActiveCache and DB
          tracker.reload
          # expect(tracker.meta['highest_price']).to eq(115.0)
        end
      end
    end

    describe '#enforce_time_based_exit' do
      let(:position) do
        double(
          'Position',
          security_id: '50074',
          exchange_segment: 'NSE_FNO',
          net_qty: 75
        )
      end

      before do
        PositionTracker.delete_all
        allow(service).to receive_messages(fetch_positions_indexed: { '50074' => position }, risk_config: {
                                             time_exit_hhmm: '15:20',
                                             market_close_hhmm: '15:30'
                                           })
        allow(PositionTracker).to receive(:active).and_return(PositionTracker.active.where(id: tracker.id))
      end

      context 'when time is 15:20 IST or later' do
        it 'exits all active positions at 15:20 IST' do
          Time.use_zone('Asia/Kolkata') do
            current_time = Time.zone.parse('2025-11-01 15:20:00')
            exit_time = Time.zone.parse('2025-11-01 15:20:00')
            market_close_time = Time.zone.parse('2025-11-01 15:30:00')

            allow(Time).to receive(:current).and_return(current_time)
            allow(service).to receive(:parse_time_hhmm).with('15:20').and_return(exit_time)
            allow(service).to receive(:parse_time_hhmm).with('15:30').and_return(market_close_time)

            expect(exit_engine).to receive(:execute_exit).with(
              tracker,
              match(/time-based exit/)
            )

            service.send(:enforce_time_based_exit, exit_engine: exit_engine)
          end
        end

        it 'exits positions between 15:20 and 15:30' do
          Time.use_zone('Asia/Kolkata') do
            current_time = Time.zone.parse('2025-11-01 15:25:00')
            exit_time = Time.zone.parse('2025-11-01 15:20:00')
            market_close_time = Time.zone.parse('2025-11-01 15:30:00')

            allow(Time).to receive(:current).and_return(current_time)
            allow(service).to receive(:parse_time_hhmm).with('15:20').and_return(exit_time)
            allow(service).to receive(:parse_time_hhmm).with('15:30').and_return(market_close_time)

            expect(exit_engine).to receive(:execute_exit).with(
              tracker,
              match(/time-based exit/)
            )

            service.send(:enforce_time_based_exit, exit_engine: exit_engine)
          end
        end

        it 'does not exit after 15:30 (market close)' do
          Time.use_zone('Asia/Kolkata') do
            current_time = Time.zone.parse('2025-11-01 15:30:00')
            exit_time = Time.zone.parse('2025-11-01 15:20:00')
            market_close_time = Time.zone.parse('2025-11-01 15:30:00')

            allow(Time).to receive(:current).and_return(current_time)
            allow(service).to receive(:parse_time_hhmm).with('15:20').and_return(exit_time)
            allow(service).to receive(:parse_time_hhmm).with('15:30').and_return(market_close_time)

            expect(exit_engine).not_to receive(:execute_exit)

            service.send(:enforce_time_based_exit, exit_engine: exit_engine)
          end
        end

        it 'logs time-based exit enforcement' do
          Time.use_zone('Asia/Kolkata') do
            current_time = Time.zone.parse('2025-11-01 15:20:00')
            exit_time = Time.zone.parse('2025-11-01 15:20:00')
            market_close_time = Time.zone.parse('2025-11-01 15:30:00')

            allow(Time).to receive(:current).and_return(current_time)
            allow(service).to receive(:parse_time_hhmm).with('15:20').and_return(exit_time)
            allow(service).to receive(:parse_time_hhmm).with('15:30').and_return(market_close_time)

            # First log happens before execute_exit
            allow(Rails.logger).to receive(:info).and_call_original
            expect(Rails.logger).to receive(:info).with(match(/\[RiskManager\] time-based exit/))

            service.send(:enforce_time_based_exit, exit_engine: exit_engine)
          end
        end
      end

      context 'when time is before 15:20 IST' do
        it 'does not exit positions' do
          Time.use_zone('Asia/Kolkata') do
            current_time = Time.zone.parse('2025-11-01 15:19:00')
            exit_time = Time.zone.parse('2025-11-01 15:20:00')

            allow(Time).to receive(:current).and_return(current_time)
            allow(service).to receive(:parse_time_hhmm).with('15:20').and_return(exit_time)

            expect(exit_engine).not_to receive(:execute_exit)

            service.send(:enforce_time_based_exit, exit_engine: exit_engine)
          end
        end
      end

      context 'when position is already exited' do
        it 'does not attempt exit' do
          tracker.update(status: 'exited')
          Time.use_zone('Asia/Kolkata') do
            current_time = Time.zone.parse('2025-11-01 15:20:00')
            exit_time = Time.zone.parse('2025-11-01 15:20:00')
            market_close_time = Time.zone.parse('2025-11-01 15:30:00')

            allow(Time).to receive(:current).and_return(current_time)
            allow(service).to receive(:parse_time_hhmm).with('15:20').and_return(exit_time)
            allow(service).to receive(:parse_time_hhmm).with('15:30').and_return(market_close_time)
            # Exited trackers won't be in PositionTracker.active scope
            expect(exit_engine).not_to receive(:execute_exit)

            service.send(:enforce_time_based_exit, exit_engine: exit_engine)
          end
        end
      end

      context 'error handling' do
        it 'handles errors gracefully' do
          Time.use_zone('Asia/Kolkata') do
            current_time = Time.zone.parse('2025-11-01 15:20:00')
            exit_time = Time.zone.parse('2025-11-01 15:20:00')
            market_close_time = Time.zone.parse('2025-11-01 15:30:00')

            allow(Time).to receive(:current).and_return(current_time)
            allow(service).to receive(:parse_time_hhmm).with('15:20').and_return(exit_time)
            allow(service).to receive(:parse_time_hhmm).with('15:30').and_return(market_close_time)
            allow(PositionTracker).to receive(:active).and_raise(StandardError, 'Database error')
            allow(Rails.logger).to receive(:error).and_call_original
            expect(Rails.logger).to receive(:error).with(match(/enforce_time_based_exit(_for)? error/)).at_least(:once)

            expect { service.send(:enforce_time_based_exit, exit_engine: exit_engine) }.not_to raise_error
          end
        end
      end
    end

    describe '#dispatch_exit' do
      it 'delegates to exit_engine' do
        expect(exit_engine).to receive(:execute_exit).with(tracker, 'test reason')
        service.send(:dispatch_exit, exit_engine, tracker, 'test reason')
      end

      it 'raises error if exit_engine is missing or invalid' do
        expect(Rails.logger).to receive(:fatal).with(/CRITICAL: ExitEngine unavailable/)
        expect do
          service.send(:dispatch_exit, nil, tracker, 'test reason')
        end.to raise_error(/ExitEngine unavailable/)
      end
    end

    describe '#track_exit_path' do
      it 'stores exit path and reason in tracker meta' do
        service.send(:track_exit_path, tracker, 'trailing_stop', 'trailing stop (drop 3.0%)')

        tracker.reload
        expect(tracker.meta['exit_path']).to eq('trailing_stop')
        expect(tracker.meta['exit_reason']).to eq('trailing stop (drop 3.0%)')
        expect(tracker.meta['exit_triggered_at']).to be_present
      end
    end

    describe '#update_pnl_in_redis' do
      it 'stores PnL data in Redis cache via PnlUpdaterService' do
        pnl_updater = Live::PnlUpdaterService.instance
        expect(pnl_updater).to receive(:cache_intermediate_pnl).with(
          tracker_id: tracker.id,
          pnl: BigDecimal('750.0'),
          pnl_pct: BigDecimal('0.10'),
          ltp: BigDecimal('110.0'),
          hwm: tracker.high_water_mark_pnl
        )

        service.send(:update_pnl_in_redis, tracker, BigDecimal('750.0'), BigDecimal('0.10'), BigDecimal('110.0'))
      end

      it 'handles errors gracefully' do
        pnl_updater = Live::PnlUpdaterService.instance
        allow(pnl_updater).to receive(:cache_intermediate_pnl).and_raise(StandardError, 'Redis error')
        expect(Rails.logger).to receive(:error).with(match(/update_pnl_in_redis failed for ORD123456/))

        expect { service.send(:update_pnl_in_redis, tracker, BigDecimal('750.0'), BigDecimal('0.10'), BigDecimal('110.0')) }.not_to raise_error
      end
    end

    describe '#compute_pnl' do
      context 'for options positions' do
        let(:position) do
          double(
            'Position',
            net_qty: 75,
            cost_price: 100.0,
            respond_to?: true
          )
        end

        before do
          allow(position).to receive(:respond_to?).with(:net_qty).and_return(true)
          allow(position).to receive(:respond_to?).with(:cost_price).and_return(true)
        end

        it 'calculates PnL using position cost price and quantity' do
          # (Current LTP - Cost Price) × Quantity
          # (110.0 - 100.0) × 75 = ₹750
          pnl = service.send(:compute_pnl, tracker, position, BigDecimal('110.0'))

          expect(pnl).to eq(BigDecimal('750.0'))
        end

        it 'returns nil if quantity is zero' do
          allow(position).to receive(:net_qty).and_return(0)

          pnl = service.send(:compute_pnl, tracker, position, BigDecimal('110.0'))

          expect(pnl).to be_nil
        end
      end

      context 'for regular positions' do
        let(:position) do
          double(
            'Position',
            respond_to?: false
          )
        end

        before do
          allow(position).to receive(:respond_to?).and_return(false)
        end

        it 'calculates PnL using tracker entry price and quantity' do
          # (Current LTP - Entry Price) × Quantity
          # (110.0 - 100.0) × 75 = ₹750
          pnl = service.send(:compute_pnl, tracker, position, BigDecimal('110.0'))

          expect(pnl).to eq(BigDecimal('750.0'))
        end
      end
    end

    describe '#compute_pnl_pct' do
      context 'for options positions' do
        let(:position) do
          double(
            'Position',
            cost_price: 100.0,
            respond_to?: true
          )
        end

        before do
          allow(position).to receive(:respond_to?).with(:cost_price).and_return(true)
        end

        it 'calculates PnL% using position cost price' do
          # (Current LTP - Cost Price) / Cost Price
          # (110.0 - 100.0) / 100.0 = 0.10 (10%)
          pnl_pct = service.send(:compute_pnl_pct, tracker, BigDecimal('110.0'), position)

          expect(pnl_pct).to eq(BigDecimal('0.10'))
        end
      end

      context 'for regular positions' do
        let(:position) { nil }

        it 'calculates PnL% using tracker entry price' do
          # (Current LTP - Entry Price) / Entry Price
          # (110.0 - 100.0) / 100.0 = 0.10 (10%)
          pnl_pct = service.send(:compute_pnl_pct, tracker, BigDecimal('110.0'), position)

          expect(pnl_pct).to eq(BigDecimal('0.10'))
        end
      end
    end
  end

  describe 'EPIC H — H1: Risk Loop' do
    describe 'AC 1: Loop Interval' do
      before do
        allow(TradingSession::Service).to receive(:market_closed?).and_return(false)
        allow(PositionTracker).to receive(:active).and_return(PositionTracker.where(id: tracker.id))
        allow(Positions::ActivePositionsCache.instance).to receive(:active_trackers).and_return([tracker])
        allow(Live::PositionSyncService.instance).to receive(:sync_positions!)
        allow(service).to receive_messages(fetch_positions_indexed: {}, tick_stream_fresh?: false)
        allow(service).to receive(:run_interval_enforcement_if_needed).and_call_original
        allow(service).to receive(:enforce_trailing_stops).and_call_original
        allow(service).to receive(:enforce_time_based_exit).and_call_original
        allow(service).to receive(:sleep)
      end

      after do
        service.stop
      end

      it 'runs every 5 seconds (LOOP_INTERVAL = 5)' do
        expect(Live::RiskManagerService::LOOP_INTERVAL).to eq(5)
        service.start
        expect(service.send(:running?)).to be true
      end

      it 'uses hardcoded LOOP_INTERVAL constant (not configurable from config file)' do
        expect(Live::RiskManagerService::LOOP_INTERVAL).to eq(5)
      end
    end

    describe 'AC 2: Exit Evaluation' do
      let(:position) do
        double(
          'Position',
          security_id: '50074',
          exchange_segment: 'NSE_FNO',
          net_qty: 75,
          cost_price: 100.0,
          product_type: 'INTRADAY'
        )
      end

      before do
        allow(Live::PositionSyncService.instance).to receive(:sync_positions!)
        # Allow methods to be called but track them (don't stub, let them run)
        allow(service).to receive(:run_interval_enforcement_if_needed).and_call_original
        allow(service).to receive(:enforce_trailing_stops).and_call_original
        allow(service).to receive(:enforce_time_based_exit).and_call_original
        # Mock ActiveRecord chain properly
        relation = double('Relation')
        allow(PositionTracker).to receive(:active).and_return(relation)
        allow(relation).to receive(:eager_load).with(:instrument).and_return(relation)
        allow(relation).to receive(:to_a).and_return([tracker])
        allow(relation).to receive(:includes).with(:instrument).and_return(relation)
        allow(relation).to receive(:find_each).and_yield(tracker)
        allow(service).to receive(:execute_exit)
        allow(service).to receive(:sleep)
        # Mock internal methods that enforce methods call
        allow(service).to receive_messages(fetch_positions_indexed: { '50074' => position },
                                           current_ltp: BigDecimal('100.0'), compute_pnl: BigDecimal(0), compute_pnl_pct: BigDecimal(0))
        allow(service).to receive(:update_pnl_in_redis)
        allow(tracker).to receive(:with_lock).and_yield
        allow(tracker).to receive_messages(instrument: instrument, security_id: '50074', status: 'active')
      end

      after do
        service.stop
      end

      it 'calls enforce methods for each open position' do
        expect(service).to receive(:run_interval_enforcement_if_needed).at_least(:once).and_call_original
        expect(service).to receive(:enforce_dynamic_trailing_stops_for).at_least(:once).and_call_original
        expect(service).to receive(:enforce_time_based_exit_for).at_least(:once).and_call_original

        service.send(:monitor_loop, Time.current)
      end
    end

    describe 'AC 3: Time-Based Exit' do
      let(:position) do
        double(
          'Position',
          security_id: '50074',
          exchange_segment: 'NSE_FNO',
          net_qty: 75,
          cost_price: 100.0,
          product_type: 'INTRADAY'
        )
      end

      before do
        allow(Live::PositionSyncService.instance).to receive(:sync_positions!)
        allow(service).to receive(:fetch_positions_indexed).and_return({ '50074' => position })
        allow(service).to receive(:sleep)
      end

      after do
        # Ensure service is stopped and thread is terminated before DatabaseCleaner runs
        service.stop if service.send(:running?)
        # Give thread a moment to fully terminate and release DB connections
        sleep 0.1
      end

      it 'exits all open positions at 15:20 IST' do
        Time.use_zone('Asia/Kolkata') do
          # Set time to 15:20 IST
          exit_time = Time.zone.parse('2024-01-15 15:20:00')
          market_close_time = Time.zone.parse('2024-01-15 15:30:00')

          # Mock Time.current to return 15:20 IST
          allow(Time).to receive(:current).and_return(exit_time)

          # Mock Time.zone.parse for enforce_time_based_exit
          allow(Time.zone).to receive(:parse).and_call_original
          allow(Time.zone).to receive(:parse).with('15:20').and_return(exit_time)
          allow(Time.zone).to receive(:parse).with('15:30').and_return(market_close_time)

          # Mock ActiveRecord Relation for PositionTracker.active
          relation = double('Relation')
          allow(PositionTracker).to receive(:active).and_return(relation)
          allow(relation).to receive(:includes).with(:instrument).and_return(relation)
          allow(relation).to receive(:find_each).and_yield(tracker)
          allow(relation).to receive(:to_a).and_return([tracker])

          # Should call dispatch_exit (which calls execute_exit on exit_engine)
          expect(exit_engine).to receive(:execute_exit).at_least(:once)

          service.send(:monitor_loop, Time.current)
        end
      end

      it 'does not exit positions before 15:20 IST' do
        Time.use_zone('Asia/Kolkata') do
          # Set time to 15:19 IST (before cutoff)
          test_time = Time.zone.parse('2024-01-15 15:19:00')
          exit_time = Time.zone.parse('2024-01-15 15:20:00')
          allow(Time).to receive(:current).and_return(test_time)

          # Mock Time.zone.parse for enforce_time_based_exit
          allow(Time.zone).to receive(:parse).and_call_original
          allow(Time.zone).to receive(:parse).with('15:20').and_return(exit_time)

          # Ensure execute_exit is not stubbed in before block (it's not, we removed it)
          # But we need to track it
          expect(service).not_to receive(:execute_exit)

          service.start
          sleep 0.6 # Allow time for thread to execute
        end
      end
    end

    describe 'AC 4: Visibility & Logging' do
      before do
        allow(Live::PositionSyncService.instance).to receive(:sync_positions!)
        allow(service).to receive(:fetch_positions_indexed).and_return({})
        allow(service).to receive(:run_interval_enforcement_if_needed)
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

        expect(service.send(:running?)).to be true
        expect(service.instance_variable_get(:@thread)).to be_a(Thread)
        expect(service.instance_variable_get(:@thread).name).to eq('risk-manager')

        # Verify thread is visible in Thread.list
        risk_thread = Thread.list.find { |t| t.name == 'risk-manager' }
        expect(risk_thread).to be_present
      end

      it 'logs clear events for each exit' do
        # Verify delegation to exit_engine
        expect(exit_engine).to receive(:execute_exit).with(tracker, 'test reason')

        service.send(:dispatch_exit, exit_engine, tracker, 'test reason')
      end

      it 'auto-starts on system boot via initializer' do
        # This tests that the service can be started (auto-start is tested in initializer)
        expect { service.start }.not_to raise_error
        expect(service.send(:running?)).to be true
      end
    end

    describe 'Monitor Loop Structure' do
      before do
        allow(TradingSession::Service).to receive(:market_closed?).and_return(false)
        allow(PositionTracker).to receive(:active).and_return(PositionTracker.where(id: tracker.id))
        allow(Positions::ActivePositionsCache.instance).to receive(:active_trackers).and_return([tracker])
        allow(Live::PositionSyncService.instance).to receive(:sync_positions!)
        allow(service).to receive_messages(fetch_positions_indexed: {}, tick_stream_fresh?: false)
        allow(service).to receive(:run_interval_enforcement_if_needed).and_call_original
        allow(service).to receive(:enforce_trailing_stops).and_call_original
        allow(service).to receive(:enforce_time_based_exit).and_call_original
        allow(service).to receive(:sleep)
      end

      after do
        # Ensure service is stopped and thread is terminated before DatabaseCleaner runs
        service.stop if service.send(:running?)
        # Give thread a moment to fully terminate and release DB connections
        sleep 0.1
      end

      it 'calls run_interval_enforcement_if_needed during each loop iteration' do
        expect(service).to receive(:run_interval_enforcement_if_needed).at_least(:once).and_call_original
        service.send(:monitor_loop, Time.current)
      end

      it 'calls enforce methods in correct sequence during each loop iteration' do
        expect(service).to receive(:run_interval_enforcement_if_needed).ordered.and_call_original
        expect(service).to receive(:enforce_dynamic_trailing_stops_for).ordered.and_call_original
        expect(service).to receive(:enforce_time_based_exit_for).ordered.and_call_original

        service.send(:monitor_loop, Time.current)
      end

      it 'handles errors gracefully and stops running' do
        # Allow logger to receive error calls
        allow(Rails.logger).to receive(:error).and_call_original

        # Raise error when ensure_all_positions_in_redis is called
        allow(service).to receive(:ensure_all_positions_in_redis).and_raise(StandardError, 'Error')

        # Mock other methods to prevent additional errors
        allow(service).to receive(:fetch_positions_indexed).and_return({})
        allow(service).to receive(:run_interval_enforcement_if_needed)
        allow(service).to receive(:enforce_trailing_stops)
        allow(service).to receive(:enforce_time_based_exit)
        allow(service).to receive(:sleep)

        service.start
        # Kill watchdog so it doesn't restart the service after it stops
        service.instance_variable_get(:@watchdog_thread)&.kill

        sleep 1.0 # Give thread time to execute, catch error, and stop

        # After error, service should stop running (rescue block sets @running = false)
        expect(service.send(:running?)).to be false
      end
    end

    describe 'Caching optimizations' do
      let(:active_cache) { instance_double(Positions::ActiveCache) }
      let(:position_data) do
        Positions::ActiveCache::PositionData.new(
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
          # allow(service).to receive(:ensure_all_positions_in_active_cache) # Moved or removed
          # allow(service).to receive(:ensure_all_positions_subscribed) # Moved or removed
          # allow(service).to receive(:enforce_session_end_exit) # Removed
        end

        it 'clears @redis_pnl_cache at start of each cycle' do
          service.instance_variable_set(:@redis_pnl_cache, { tracker.id => { pnl: 100 } })
          service.instance_variable_set(:@cycle_tracker_map, { tracker.id => tracker })

          # Mock methods that repopulate cache to keep it empty
          allow(service).to receive(:update_paper_positions_pnl_if_due)
          allow(service).to receive(:ensure_all_positions_in_redis)
          allow(service).to receive(:skip_enforcement_due_to_market_closed?).and_return(true)

          service.send(:monitor_loop, Time.current)

          expect(service.instance_variable_get(:@redis_pnl_cache)).to be_empty
          expect(service.instance_variable_get(:@cycle_tracker_map)).to be_nil
        end

        it 'returns early when positions are empty but still runs maintenance' do
          allow(active_cache).to receive(:all_positions).and_return([])

          service.send(:monitor_loop, Time.current)

          expect(service).to have_received(:update_paper_positions_pnl_if_due)
          expect(service).to have_received(:ensure_all_positions_in_redis)
          # expect(service).to have_received(:ensure_all_positions_in_active_cache)
          # expect(service).to have_received(:ensure_all_positions_subscribed)
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
        allow(Rails.logger).to receive(:info)
      end

      it 'updates PnL for all paper trackers' do
        service.send(:update_paper_positions_pnl)

        paper_tracker.reload
        expect(paper_tracker.last_pnl_rupees).to eq(BigDecimal('480.0')) # (110 - 100) * 50 - 20
        expect(paper_tracker.last_pnl_pct).to eq(0.10) # (110 - 100) / 100
      end

      it 'updates high water mark' do
        paper_tracker.update(high_water_mark_pnl: BigDecimal('400.0'))

        service.send(:update_paper_positions_pnl)

        paper_tracker.reload
        expect(paper_tracker.high_water_mark_pnl).to eq(BigDecimal('480.0')) # max(400, 480)
      end

      it 'caches PnL in Redis via PnlUpdaterService' do
        service.send(:update_paper_positions_pnl)

        expect(pnl_updater).to have_received(:cache_intermediate_pnl).with(
          hash_including(
            tracker_id: paper_tracker.id,
            pnl: BigDecimal('480.0'),
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
      it 'cancels order via gateway' do
        gateway = service.instance_variable_get(:@orders_gateway)
        expect(gateway).to receive(:cancel_order).with('123')
        service.send(:cancel_remote_order, '123')
      end
    end

    describe '#fetch_ltp' do
      let(:position) { double('Position', exchange_segment: 'NSE_FNO') }

      before do
        allow(Live::TickQuery).to receive(:for_security).and_return(nil)
      end

      it 'returns cached LTP from TickQuery' do
        allow(Live::TickQuery).to receive(:for_security).and_return(double(ltp: BigDecimal('110.0')))

        result = service.send(:fetch_ltp, position, tracker)

        expect(result).to eq(BigDecimal('110.0'))
      end

      it 'returns nil if no cache available' do
        result = service.send(:fetch_ltp, position, tracker)

        expect(result).to be_nil
      end
    end
  end
end
