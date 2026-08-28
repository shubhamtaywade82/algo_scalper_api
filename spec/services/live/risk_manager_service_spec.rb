# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::RiskManagerService do
  let(:exit_engine) { instance_double(Live::ExitEngine) }
  let(:service) { described_class.new(exit_engine: exit_engine) }
  let(:event_bus) { Core::EventBus.instance }
  let(:active_cache) { instance_double(Positions::ActiveCache) }
  let(:mock_thread) { instance_double(Thread, alive?: true, name: 'risk-manager', kill: true, join: true) }

  before do
    allow(Positions::ActiveCache).to receive(:instance).and_return(active_cache)
    allow(AlgoConfig).to receive(:fetch).and_return({ paper_trading: { enabled: true } })
    allow(Notifications::TelegramNotifier.instance).to receive(:notify_error)
  end

  describe '#initialize' do
    it 'sets initial state' do
      expect(service.instance_variable_get(:@running)).to be false
      expect(service.instance_variable_get(:@exit_engine)).to eq(exit_engine)
      expect(service.instance_variable_get(:@paper_mode)).to be true
    end
  end

  describe '#start' do
    before do
      allow(Thread).to receive(:new).and_return(mock_thread)
    end

    it 'sets running to true and starts a thread' do
      service.start
      expect(Thread).to have_received(:new).at_least(:once)
      expect(service.instance_variable_get(:@running)).to be true
    end

    it 'subscribes to pnl_update events' do
      allow(event_bus).to receive(:subscribe).and_call_original
      service.start
      expect(event_bus).to have_received(:subscribe).with(Core::EventBus::EVENTS[:pnl_update])
    end
  end

  describe '#stop' do
    before do
      allow(Thread).to receive(:new).and_return(mock_thread)
      service.start
    end

    it 'sets running to false' do
      service.stop
      expect(service.instance_variable_get(:@running)).to be false
    end

    it 'unsubscribes from event bus' do
      allow(event_bus).to receive(:unsubscribe)
      service.stop
      expect(event_bus).to have_received(:unsubscribe)
    end
  end

  describe '#handle_pnl_event' do
    let(:tracker) { create(:position_tracker, :active) }
    let(:event) { { tracker_id: tracker.id, pnl: 50.0, ltp: 100.0 } }

    before do
      service.instance_variable_set(:@running, true)
      allow(service).to receive(:should_run_realtime_enforcement?).and_return(false)
    end

    it 'evaluates exit conditions via UnifiedExitChecker' do
      allow(Live::UnifiedExitChecker).to receive(:check_exit_conditions).with(tracker).and_return({ exit: false })
      service.send(:handle_pnl_event, event)
      expect(Live::UnifiedExitChecker).to have_received(:check_exit_conditions).with(tracker)
    end

    it 'ignores events for unknown trackers' do
      allow(Live::UnifiedExitChecker).to receive(:check_exit_conditions)
      service.send(:handle_pnl_event, { tracker_id: 999_999, ltp: 100.0 })
      expect(Live::UnifiedExitChecker).not_to have_received(:check_exit_conditions)
    end

    context 'when exit is triggered' do
      before do
        allow(Live::UnifiedExitChecker).to receive(:check_exit_conditions)
          .and_return({ exit: true, reason: 'Target Reached' })
      end

      it 'calls dispatch_exit on the exit engine' do
        allow(service).to receive(:dispatch_exit)
        service.send(:handle_pnl_event, event)
        expect(service).to have_received(:dispatch_exit).with(exit_engine, tracker, /Target Reached/)
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

    it 'returns high risk for low confidence' do
      result = service.send(:evaluate_signal_risk, { confidence: 0.4, entry_price: 100 })
      expect(result[:risk_level]).to eq(:high)
      expect(result[:max_position_size]).to eq(25)
    end

    it 'defaults to high risk when confidence is missing' do
      result = service.send(:evaluate_signal_risk, { entry_price: 100 })
      expect(result[:risk_level]).to eq(:high)
    end

    it 'falls back to 2% stop loss when not provided' do
      result = service.send(:evaluate_signal_risk, { confidence: 0.9, entry_price: 100 })
      expect(result[:recommended_stop_loss]).to eq(98.0)
    end
  end

  describe '#should_run_realtime_enforcement?' do
    it 'returns true when gap is not configured' do
      allow(service).to receive(:realtime_min_enforcement_gap_seconds).and_return(0)
      expect(service.send(:should_run_realtime_enforcement?, 1)).to be true
    end

    it 'throttles evaluations for the same tracker within the gap' do
      allow(service).to receive(:realtime_min_enforcement_gap_seconds).and_return(60)
      expect(service.send(:should_run_realtime_enforcement?, 1)).to be true
      expect(service.send(:should_run_realtime_enforcement?, 1)).to be false
    end
  end

  describe '#dispatch_exit' do
    let(:tracker) { create(:position_tracker, :active) }
    let(:reason) { 'TEST_EXIT' }

    it 'delegates to external exit_engine' do
      allow(exit_engine).to receive(:execute_exit)
      service.send(:dispatch_exit, exit_engine, tracker, reason)
      expect(exit_engine).to have_received(:execute_exit).with(tracker, reason)
    end

    it 'raises external exit_engine errors' do
      allow(exit_engine).to receive(:execute_exit).and_raise(StandardError, 'gateway down')
      expect { service.send(:dispatch_exit, exit_engine, tracker, reason) }.to raise_error(StandardError, 'gateway down')
    end

    it 'raises fatal error when exit_engine is self' do
      expect { service.send(:dispatch_exit, service, tracker, reason) }
        .to raise_error(/ExitEngine unavailable/)
    end

    it 'raises fatal error when exit_engine is nil' do
      expect { service.send(:dispatch_exit, nil, tracker, reason) }
        .to raise_error(/ExitEngine unavailable/)
    end
  end

  describe '#store_exit_reason' do
    let(:tracker) { create(:position_tracker, :active) }

    it 'persists exit reason and timestamp' do
      service.send(:store_exit_reason, tracker, 'SL HIT')
      tracker.reload
      expect(tracker.exit_reason).to eq('SL HIT')
      expect(tracker.exit_triggered_at).to be_present
    end

    it 'swallows persistence errors' do
      allow(tracker).to receive(:update!).and_raise(ActiveRecord::RecordInvalid)
      expect { service.send(:store_exit_reason, tracker, 'SL HIT') }.not_to raise_error
    end
  end

  describe '#parse_time_hhmm' do
    it 'parses a valid time string' do
      expect(service.send(:parse_time_hhmm, '15:30')).to be_present
    end

    it 'returns nil for blank input' do
      expect(service.send(:parse_time_hhmm, '')).to be_nil
      expect(service.send(:parse_time_hhmm, nil)).to be_nil
    end

    it 'returns nil for invalid input' do
      expect(service.send(:parse_time_hhmm, 'not-a-time')).to be_nil
    end
  end

  describe '#cancel_remote_order' do
    it 'delegates to the orders gateway' do
      gateway = service.instance_variable_get(:@orders_gateway)
      allow(gateway).to receive(:cancel_order)
      service.send(:cancel_remote_order, 'ORD123')
      expect(gateway).to have_received(:cancel_order).with('ORD123')
    end

    it 're-raises gateway errors' do
      allow(service.instance_variable_get(:@orders_gateway)).to receive(:cancel_order).and_raise(StandardError, 'boom')
      expect { service.send(:cancel_remote_order, 'ORD123') }.to raise_error(StandardError, 'boom')
    end
  end

  describe '#fetch_ltp' do
    # BaseModel attribute accessors are not visible to verifying doubles
    let(:position) { double('position', exchange_segment: 'NSE_FNO') } # rubocop:disable RSpec/VerifiedDoubles
    let(:tracker) { build_stubbed(:position_tracker, :active) }

    it 'returns nil when no cache data is available' do
      expect(service.send(:fetch_ltp, position, tracker)).to be_nil
    end
  end

  describe '#update_paper_positions_pnl' do
    it 'returns early when no paper trackers exist' do
      expect(service.send(:update_paper_positions_pnl)).to be_nil
    end

    context 'with a paper tracker' do
      let(:tracker) { create(:position_tracker, :paper, :active, entry_price: 100.0, quantity: 10, high_water_mark_pnl: BigDecimal('0')) }

      before do
        allow(service).to receive(:get_paper_ltp).with(tracker).and_return(110.0)
        allow(service).to receive(:update_pnl_in_redis)
      end

      it 'updates PnL and high water mark' do
        service.send(:update_paper_positions_pnl)
        tracker.reload
        expect(tracker.last_pnl_rupees).to eq(BigDecimal('80'))
        expect(tracker.last_pnl_pct).to eq(BigDecimal('0.1'))
        expect(tracker.high_water_mark_pnl).to eq(BigDecimal('80'))
      end

      it 'skips trackers without LTP' do
        allow(service).to receive(:get_paper_ltp).and_return(nil)
        expect { service.send(:update_paper_positions_pnl) }.not_to(change { tracker.reload.last_pnl_rupees })
      end

      it 'skips trackers without entry_price' do
        tracker.update!(entry_price: nil)
        allow(service).to receive(:get_paper_ltp).and_return(110.0)
        expect { service.send(:update_paper_positions_pnl) }.not_to(change { tracker.reload.last_pnl_rupees })
      end
    end
  end

  describe '#update_paper_positions_pnl_if_due' do
    it 'updates when last update is stale' do
      allow(service).to receive(:update_paper_positions_pnl)
      service.send(:update_paper_positions_pnl_if_due, 2.minutes.ago)
      expect(service).to have_received(:update_paper_positions_pnl)
    end

    it 'skips when updated recently' do
      allow(service).to receive(:update_paper_positions_pnl)
      service.send(:update_paper_positions_pnl_if_due, 10.seconds.ago)
      expect(service).not_to have_received(:update_paper_positions_pnl)
    end

    it 'updates when last update is nil' do
      allow(service).to receive(:update_paper_positions_pnl)
      service.send(:update_paper_positions_pnl_if_due, nil)
      expect(service).to have_received(:update_paper_positions_pnl)
    end
  end

  describe '#ensure_all_positions_in_redis' do
    before do
      allow(TradingSession::Service).to receive(:market_closed?).and_return(false)
      allow(Live::RedisPnlCache.instance).to receive(:fetch_pnl).and_return(nil)
      allow(service).to receive(:fetch_positions_indexed).and_return({})
      allow(service).to receive(:update_pnl_in_redis)
    end

    it 'returns early when no active trackers exist' do
      allow(service).to receive(:current_ltp).and_return(105.0)
      expect(service.send(:ensure_all_positions_in_redis)).to be_nil
    end

    context 'with an active tracker' do
      let!(:tracker) { create(:position_tracker, :active) }

      it 'caches PnL for trackers missing from Redis' do
        allow(service).to receive(:current_ltp).and_return(105.0)
        allow(service).to receive(:update_pnl_in_redis).with(tracker, anything, anything, anything)
        service.send(:ensure_all_positions_in_redis)
        expect(service).to have_received(:update_pnl_in_redis).with(tracker, anything, anything, anything)
      end
    end

    it 'throttles to at most once per 5 seconds' do
      create(:position_tracker, :active)
      allow(service).to receive(:current_ltp).and_return(105.0)
      service.send(:ensure_all_positions_in_redis)
      service.send(:ensure_all_positions_in_redis)
      expect(service).to have_received(:update_pnl_in_redis).once
    end
  end

  describe '#fetch_positions_indexed' do
    it 'returns empty hash in paper mode' do
      expect(service.send(:fetch_positions_indexed)).to eq({})
    end

    context 'when live trading is enabled' do
      before do
        service.instance_variable_set(:@paper_mode, false)
        allow(AlgoConfig).to receive(:fetch).and_return({ paper_trading: { enabled: false } })
      end

      it 'indexes live positions by security_id' do
        # BaseModel attribute accessors are not visible to verifying doubles
        position = double('position', security_id: '50074') # rubocop:disable RSpec/VerifiedDoubles
        allow(DhanHQ::Models::Position).to receive(:active).and_return([position])
        result = service.send(:fetch_positions_indexed)
        expect(result['50074']).to eq(position)
      end

      it 'returns empty hash on failure' do
        allow(DhanHQ::Models::Position).to receive(:active).and_raise(StandardError, 'API error')
        expect(service.send(:fetch_positions_indexed)).to eq({})
      end
    end
  end

  describe '#risk_config' do
    it 'returns empty hash on error' do
      allow(service).to receive(:resolved_risk_config).and_raise(StandardError, 'Config error')
      expect(service.send(:risk_config)).to eq({})
    end
  end

  describe '#pct_value' do
    it 'converts to BigDecimal' do
      expect(service.send(:pct_value, 0.12)).to eq(BigDecimal('0.12'))
    end

    it 'returns zero for unparseable values' do
      expect(service.send(:pct_value, Object.new)).to eq(BigDecimal('0'))
    end
  end

  describe '#paper_trading_enabled?' do
    it 'returns true when paper trading is enabled' do
      expect(service.send(:paper_trading_enabled?)).to be true
    end

    context 'when paper trading is disabled' do
      before do
        service.instance_variable_set(:@paper_mode, false)
      end

      it 'returns false' do
        expect(service.send(:paper_trading_enabled?)).to be false
      end
    end
  end
end