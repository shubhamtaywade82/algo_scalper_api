# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::ExitEngine do
  let(:router) { instance_double(TradingSystem::OrderRouter) }
  let(:watchable) { create(:derivative, :nifty_call_option, security_id: '55111') }
  let(:tracker) do
    create(:position_tracker, :option_position,
           watchable: watchable,
           instrument: watchable.instrument,
           status: 'active',
           segment: 'NSE_FNO',
           security_id: watchable.security_id)
  end
  let(:engine) { described_class.new(order_router: router) }

  before do
    allow(Live::TickCache).to receive(:ltp).and_return(101.5)
    allow(router).to receive(:exit_market).and_return({ success: true })
  end

  describe '#initialize' do
    it 'initializes with order router' do
      expect(engine.instance_variable_get(:@router)).to eq(router)
      expect(engine.instance_variable_get(:@running)).to be false
    end
  end

  describe '#start' do
    it 'sets running to true' do
      engine.start
      expect(engine.running?).to be true
    end

    it 'does not start if already running' do
      engine.start
      expect(engine.running?).to be true
      engine.start # Should not change state
      expect(engine.running?).to be true
    end
  end

  describe '#stop' do
    it 'sets running to false' do
      engine.start
      engine.stop
      expect(engine.running?).to be false
    end

    it 'does nothing if not running' do
      expect { engine.stop }.not_to raise_error
      expect(engine.running?).to be false
    end
  end

  describe '#running?' do
    it 'returns false initially' do
      expect(engine.running?).to be false
    end

    it 'returns true after start' do
      engine.start
      expect(engine.running?).to be true
    end
  end

  describe '#execute_exit' do
    context 'with valid inputs' do
      it 'returns success hash on successful exit' do
        result = engine.execute_exit(tracker, 'stop_loss')

        expect(result).to be_a(Hash)
        expect(result[:success]).to be true
        expect(result[:exit_price]).to eq(101.5)
        expect(result[:reason]).to eq('stop_loss')
      end

      it 'marks tracker as exited' do
        engine.execute_exit(tracker, 'take_profit')

        tracker.reload
        expect(tracker.status).to eq('exited')
        expect(tracker.meta['exit_reason']).to eq('take_profit')
      end

      it 'calls router exit_market' do
        engine.execute_exit(tracker, 'test reason')

        expect(router).to have_received(:exit_market).with(tracker)
      end

      it 'prevents double exit - marks tracker exited once even when called multiple times' do
        engine.execute_exit(tracker, 'paper exit')
        result = engine.execute_exit(tracker, 'duplicate exit')

        tracker.reload
        expect(tracker.status).to eq('exited')
        expect(tracker.meta['exit_reason']).to eq('paper exit')
        expect(router).to have_received(:exit_market).once
        expect(result[:success]).to be true
        expect(result[:reason]).to eq('already_exited')
      end

      it 'returns already_exited if tracker is already exited' do
        tracker.update!(status: 'exited', meta: { 'exit_reason' => 'previous_exit' })
        result = engine.execute_exit(tracker, 'new_exit')

        expect(result[:success]).to be true
        expect(result[:reason]).to eq('already_exited')
        expect(router).not_to have_received(:exit_market)
      end
    end

    context 'with invalid inputs' do
      it 'returns failure if tracker is nil' do
        result = engine.execute_exit(nil, 'reason')

        expect(result[:success]).to be false
        expect(result[:reason]).to eq('invalid_tracker')
        expect(router).not_to have_received(:exit_market)
      end

      it 'returns failure if router is nil' do
        engine_without_router = described_class.new(order_router: nil)
        result = engine_without_router.execute_exit(tracker, 'reason')

        expect(result[:success]).to be false
        expect(result[:reason]).to eq('invalid_router')
      end

      it 'returns failure if reason is blank' do
        result = engine.execute_exit(tracker, '')

        expect(result[:success]).to be false
        expect(result[:reason]).to eq('invalid_reason')
        expect(router).not_to have_received(:exit_market)
      end

      it 'returns failure if reason is nil' do
        result = engine.execute_exit(tracker, nil)

        expect(result[:success]).to be false
        expect(result[:reason]).to eq('invalid_reason')
        expect(router).not_to have_received(:exit_market)
      end

      it 'returns failure if tracker is not active' do
        tracker.update!(status: 'cancelled')
        result = engine.execute_exit(tracker, 'reason')

        expect(result[:success]).to be false
        expect(result[:reason]).to eq('not_active')
        expect(router).not_to have_received(:exit_market)
      end
    end

    context 'with router failures' do
      it 'returns failure hash when router returns false' do
        allow(router).to receive(:exit_market).and_return(false)

        result = engine.execute_exit(tracker, 'test reason')

        expect(result[:success]).to be false
        expect(result[:reason]).to eq('router_failed')
        expect(result[:error]).to eq(false)
      end

      it 'returns failure hash when router returns hash with success: false' do
        allow(router).to receive(:exit_market).and_return({ success: false, error: 'Order rejected' })

        result = engine.execute_exit(tracker, 'test reason')

        expect(result[:success]).to be false
        expect(result[:reason]).to eq('router_failed')
        expect(result[:error]).to eq({ success: false, error: 'Order rejected' })
      end

      it 'does not mark tracker as exited when router fails' do
        allow(router).to receive(:exit_market).and_return({ success: false })

        engine.execute_exit(tracker, 'test reason')

        tracker.reload
        expect(tracker.status).to eq('active')
      end
    end

    context 'with success detection improvements' do
      it 'accepts boolean true' do
        allow(router).to receive(:exit_market).and_return(true)

        result = engine.execute_exit(tracker, 'test reason')

        expect(result[:success]).to be true
      end

      it 'accepts hash with success: true' do
        allow(router).to receive(:exit_market).and_return({ success: true })

        result = engine.execute_exit(tracker, 'test reason')

        expect(result[:success]).to be true
      end

      it 'accepts hash with success: 1' do
        allow(router).to receive(:exit_market).and_return({ success: 1 })

        result = engine.execute_exit(tracker, 'test reason')

        expect(result[:success]).to be true
      end

      it 'accepts hash with success: "true"' do
        allow(router).to receive(:exit_market).and_return({ success: 'true' })

        result = engine.execute_exit(tracker, 'test reason')

        expect(result[:success]).to be true
      end

      it 'accepts hash with success: "yes"' do
        allow(router).to receive(:exit_market).and_return({ success: 'yes' })

        result = engine.execute_exit(tracker, 'test reason')

        expect(result[:success]).to be true
      end

      it 'rejects hash with success: false' do
        allow(router).to receive(:exit_market).and_return({ success: false })

        result = engine.execute_exit(tracker, 'test reason')

        expect(result[:success]).to be false
      end

      it 'rejects hash with success: 0' do
        allow(router).to receive(:exit_market).and_return({ success: 0 })

        result = engine.execute_exit(tracker, 'test reason')

        expect(result[:success]).to be false
      end
    end

    context 'with partial success handling' do
      it 'handles mark_exited! failure gracefully when tracker is already exited' do
        allow(router).to receive(:exit_market).and_return({ success: true })
        allow(tracker).to receive(:mark_exited!).and_raise(StandardError.new('DB error'))
        tracker.update!(status: 'exited', exit_price: 102.0, meta: { 'exit_reason' => 'previous' })

        # Reload to simulate OrderUpdateHandler updating tracker
        tracker.reload

        result = engine.execute_exit(tracker, 'new_reason')

        expect(result[:success]).to be true
        expect(result[:reason]).to eq('already_exited')
      end

      it 'raises error if mark_exited! fails and tracker is not exited' do
        allow(router).to receive(:exit_market).and_return({ success: true })
        allow(tracker).to receive(:mark_exited!).and_raise(StandardError.new('DB error'))

        expect do
          engine.execute_exit(tracker, 'test reason')
        end.to raise_error(StandardError, 'DB error')
      end
    end

    context 'with LTP fallback' do
      it 'handles nil LTP gracefully' do
        allow(Live::TickCache).to receive(:ltp).and_return(nil)

        result = engine.execute_exit(tracker, 'test reason')

        expect(result[:success]).to be true
        tracker.reload
        expect(tracker.exit_price).to be_nil
      end

      it 'handles LTP fetch errors gracefully' do
        allow(Live::TickCache).to receive(:ltp).and_raise(StandardError.new('Cache error'))

        result = engine.execute_exit(tracker, 'test reason')

        expect(result[:success]).to be true
        tracker.reload
        expect(tracker.exit_price).to be_nil
      end
    end

    context 'with gateway-provided exit_price (paper mode)' do
      it 'uses exit_price from gateway when available' do
        allow(router).to receive(:exit_market).and_return({ success: true, exit_price: 105.75 })

        result = engine.execute_exit(tracker, 'test reason')

        expect(result[:success]).to be true
        expect(result[:exit_price]).to eq(105.75)
        tracker.reload
        expect(tracker.exit_price).to eq(105.75)
      end

      it 'falls back to LTP when gateway does not provide exit_price' do
        allow(Live::TickCache).to receive(:ltp).and_return(102.5)
        allow(router).to receive(:exit_market).and_return({ success: true })

        result = engine.execute_exit(tracker, 'test reason')

        expect(result[:success]).to be true
        expect(result[:exit_price]).to eq(102.5)
        tracker.reload
        expect(tracker.exit_price).to eq(102.5)
      end

      it 'uses gateway exit_price even when LTP is nil' do
        allow(Live::TickCache).to receive(:ltp).and_return(nil)
        allow(router).to receive(:exit_market).and_return({ success: true, exit_price: 100.0 })

        result = engine.execute_exit(tracker, 'test reason')

        expect(result[:success]).to be true
        expect(result[:exit_price]).to eq(100.0)
        tracker.reload
        expect(tracker.exit_price).to eq(100.0)
      end
    end

    context 'with exceptions' do
      it 'raises exception when router raises error' do
        allow(router).to receive(:exit_market).and_raise(StandardError.new('Router error'))

        expect do
          engine.execute_exit(tracker, 'test reason')
        end.to raise_error(StandardError, 'Router error')
      end

      it 'raises exception when tracker.with_lock raises error' do
        allow(tracker).to receive(:with_lock).and_raise(StandardError.new('Lock error'))

        expect do
          engine.execute_exit(tracker, 'test reason')
        end.to raise_error(StandardError, 'Lock error')
      end
    end
  end
end

