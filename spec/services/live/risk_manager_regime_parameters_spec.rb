# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::RiskManagerService, '#enforce_hard_limits with regime-based parameters' do
  let(:service) { described_class.new }
  let(:nifty_instrument) { create(:instrument, symbol_name: 'NIFTY 50', security_id: '9999') }
  let(:tracker) do
    create(
      :position_tracker,
      instrument: nifty_instrument,
      watchable: nifty_instrument,
      order_no: 'ORD123456',
      security_id: '50074',
      segment: 'NSE_FNO',
      status: 'active',
      quantity: 75,
      entry_price: 100.0,
      avg_price: 100.0,
      meta: { index_key: 'NIFTY' }
    )
  end
  let(:position_data) do
    Positions::ActiveCache::PositionData.new(
      tracker_id: tracker.id,
      security_id: tracker.security_id,
      segment: tracker.segment,
      entry_price: tracker.entry_price,
      quantity: tracker.quantity,
      pnl: BigDecimal('-1000'),
      pnl_pct: -10.0,
      high_water_mark: BigDecimal('0'),
      last_updated_at: Time.current
    )
  end
  let(:active_cache) { instance_double(Positions::ActiveCache, all_positions: [position_data]) }
  let(:exit_engine) { instance_double(Live::ExitEngine) }

  before do
    allow(Positions::ActiveCache).to receive(:instance).and_return(active_cache)
    allow(service).to receive(:trackers_for_positions).and_return({ tracker.id => tracker })
    allow(service).to receive(:sync_position_pnl_from_redis)
    allow(service).to receive(:dispatch_exit)
  end

  describe '#resolve_parameters_for_tracker' do
    context 'when regime-based parameters are enabled' do
      before do
        allow(service).to receive(:risk_config).and_return({
          volatility_regimes: {
            enabled: true
          },
          sl_pct: 0.30,
          tp_pct: 0.60
        })
        allow(Risk::RegimeParameterResolver).to receive(:call).with(index_key: 'NIFTY').and_return({
          index_key: 'NIFTY',
          regime: :high,
          condition: :bullish,
          parameters: {
            sl_pct_range: [8, 12],
            tp_pct_range: [18, 30],
            trail_pct_range: [7, 12],
            timeout_minutes: [10, 18]
          }
        })
      end

      it 'resolves regime-based SL/TP parameters' do
        sl_pct, tp_pct = service.send(:resolve_parameters_for_tracker, tracker, BigDecimal('0.30'), BigDecimal('0.60'))
        expect(sl_pct).to eq(BigDecimal('0.10')) # Midpoint of [8, 12] = 10% = 0.10
        expect(tp_pct).to eq(BigDecimal('0.24')) # Midpoint of [18, 30] = 24% = 0.24
      end

      it 'uses index_key from tracker meta' do
        expect(Risk::RegimeParameterResolver).to receive(:call).with(index_key: 'NIFTY')
        service.send(:resolve_parameters_for_tracker, tracker, BigDecimal('0.30'), BigDecimal('0.60'))
      end
    end

    context 'when regime-based parameters are disabled' do
      before do
        allow(service).to receive(:risk_config).and_return({
          volatility_regimes: {
            enabled: false
          },
          sl_pct: 0.30,
          tp_pct: 0.60
        })
      end

      it 'falls back to default parameters' do
        sl_pct, tp_pct = service.send(:resolve_parameters_for_tracker, tracker, BigDecimal('0.30'), BigDecimal('0.60'))
        expect(sl_pct).to eq(BigDecimal('0.30'))
        expect(tp_pct).to eq(BigDecimal('0.60'))
      end
    end

    context 'when index_key not in tracker meta' do
      let(:tracker_no_index) do
        create(
          :position_tracker,
          instrument: nifty_instrument,
          watchable: nifty_instrument,
          order_no: 'ORD123457',
          security_id: '50075',
          segment: 'NSE_FNO',
          status: 'active',
          quantity: 75,
          entry_price: 100.0,
          avg_price: 100.0,
          meta: {}
        )
      end

      before do
        allow(service).to receive(:risk_config).and_return({
          volatility_regimes: {
            enabled: true
          },
          sl_pct: 0.30,
          tp_pct: 0.60
        })
      end

      it 'extracts index from instrument symbol name' do
        allow(Risk::RegimeParameterResolver).to receive(:call).with(index_key: 'NIFTY').and_return({
          parameters: {
            sl_pct_range: [8, 12],
            tp_pct_range: [18, 30]
          }
        })
        sl_pct, tp_pct = service.send(:resolve_parameters_for_tracker, tracker_no_index, BigDecimal('0.30'), BigDecimal('0.60'))
        expect(sl_pct).to eq(BigDecimal('0.10'))
      end

      it 'falls back to defaults if index cannot be extracted' do
        allow(tracker_no_index.instrument).to receive(:symbol_name).and_return('UNKNOWN')
        sl_pct, tp_pct = service.send(:resolve_parameters_for_tracker, tracker_no_index, BigDecimal('0.30'), BigDecimal('0.60'))
        expect(sl_pct).to eq(BigDecimal('0.30'))
        expect(tp_pct).to eq(BigDecimal('0.60'))
      end
    end

    context 'when RegimeParameterResolver fails' do
      before do
        allow(service).to receive(:risk_config).and_return({
          volatility_regimes: {
            enabled: true
          },
          sl_pct: 0.30,
          tp_pct: 0.60
        })
        allow(Risk::RegimeParameterResolver).to receive(:call).and_raise(StandardError, 'Resolver error')
      end

      it 'falls back to default parameters' do
        sl_pct, tp_pct = service.send(:resolve_parameters_for_tracker, tracker, BigDecimal('0.30'), BigDecimal('0.60'))
        expect(sl_pct).to eq(BigDecimal('0.30'))
        expect(tp_pct).to eq(BigDecimal('0.60'))
      end
    end
  end

  describe '#extract_index_from_instrument' do
    it 'extracts NIFTY from symbol name' do
      index = service.send(:extract_index_from_instrument, tracker)
      expect(index).to eq('NIFTY')
    end

    it 'extracts BANKNIFTY from symbol name' do
      banknifty_instrument = create(:instrument, symbol_name: 'BANKNIFTY')
      banknifty_tracker = create(:position_tracker, instrument: banknifty_instrument)
      index = service.send(:extract_index_from_instrument, banknifty_tracker)
      expect(index).to eq('BANKNIFTY')
    end

    it 'extracts SENSEX from symbol name' do
      sensex_instrument = create(:instrument, symbol_name: 'SENSEX')
      sensex_tracker = create(:position_tracker, instrument: sensex_instrument)
      index = service.send(:extract_index_from_instrument, sensex_tracker)
      expect(index).to eq('SENSEX')
    end

    it 'returns nil for unknown symbols' do
      unknown_instrument = create(:instrument, symbol_name: 'UNKNOWN')
      unknown_tracker = create(:position_tracker, instrument: unknown_instrument)
      index = service.send(:extract_index_from_instrument, unknown_tracker)
      expect(index).to be_nil
    end

    it 'handles missing instrument gracefully' do
      tracker_without_instrument = instance_double(PositionTracker, instrument: nil)
      index = service.send(:extract_index_from_instrument, tracker_without_instrument)
      expect(index).to be_nil
    end
  end

  describe '#enforce_hard_limits with regime parameters' do
    before do
      allow(service).to receive(:risk_config).and_return({
        volatility_regimes: {
          enabled: true
        },
        sl_pct: 0.30,
        tp_pct: 0.60
      })
      allow(Risk::RegimeParameterResolver).to receive(:call).with(index_key: 'NIFTY').and_return({
        index_key: 'NIFTY',
        regime: :high,
        condition: :bullish,
        parameters: {
          sl_pct_range: [8, 12],
          tp_pct_range: [18, 30],
          trail_pct_range: [7, 12],
          timeout_minutes: [10, 18]
        }
      })
    end

    context 'when regime-based SL is hit' do
      it 'exits with regime-based reason' do
        position_data.pnl_pct = -10.0 # -10% hits the 10% SL threshold (midpoint of [8, 12])

        expect(service).to receive(:dispatch_exit).with(
          exit_engine,
          tracker,
          a_string_matching(/SL HIT.*regime-based/)
        )

        service.send(:enforce_hard_limits, exit_engine: exit_engine)
      end
    end

    context 'when regime-based TP is hit' do
      it 'exits with regime-based reason' do
        position_data.pnl_pct = 24.0 # 24% hits the 24% TP threshold (midpoint of [18, 30])

        expect(service).to receive(:dispatch_exit).with(
          exit_engine,
          tracker,
          a_string_matching(/TP HIT.*regime-based/)
        )

        service.send(:enforce_hard_limits, exit_engine: exit_engine)
      end
    end

    context 'when regime parameters not available' do
      before do
        allow(Risk::RegimeParameterResolver).to receive(:call).and_return({
          parameters: nil
        })
      end

      it 'falls back to default SL/TP' do
        position_data.pnl_pct = -30.0 # Hits default 30% SL

        expect(service).to receive(:dispatch_exit).with(
          exit_engine,
          tracker,
          a_string_matching(/SL HIT.*regime-based/)
        )

        service.send(:enforce_hard_limits, exit_engine: exit_engine)
      end
    end

    context 'with different volatility regimes' do
      it 'uses low volatility parameters when regime is low' do
        allow(Risk::RegimeParameterResolver).to receive(:call).with(index_key: 'NIFTY').and_return({
          index_key: 'NIFTY',
          regime: :low,
          condition: :bullish,
          parameters: {
            sl_pct_range: [3, 5],
            tp_pct_range: [4, 7],
            trail_pct_range: [2, 3],
            timeout_minutes: [3, 8]
          }
        })

        position_data.pnl_pct = -4.0 # Hits low volatility SL (midpoint of [3, 5] = 4%)

        expect(service).to receive(:dispatch_exit).with(
          exit_engine,
          tracker,
          a_string_matching(/SL HIT.*regime-based/)
        )

        service.send(:enforce_hard_limits, exit_engine: exit_engine)
      end

      it 'uses medium volatility parameters when regime is medium' do
        allow(Risk::RegimeParameterResolver).to receive(:call).with(index_key: 'NIFTY').and_return({
          index_key: 'NIFTY',
          regime: :medium,
          condition: :bullish,
          parameters: {
            sl_pct_range: [6, 8],
            tp_pct_range: [10, 18],
            trail_pct_range: [5, 7],
            timeout_minutes: [8, 12]
          }
        })

        position_data.pnl_pct = -7.0 # Hits medium volatility SL (midpoint of [6, 8] = 7%)

        expect(service).to receive(:dispatch_exit).with(
          exit_engine,
          tracker,
          a_string_matching(/SL HIT.*regime-based/)
        )

        service.send(:enforce_hard_limits, exit_engine: exit_engine)
      end
    end

    context 'with different market conditions' do
      it 'uses bearish parameters when condition is bearish' do
        allow(Risk::RegimeParameterResolver).to receive(:call).with(index_key: 'NIFTY').and_return({
          index_key: 'NIFTY',
          regime: :high,
          condition: :bearish,
          parameters: {
            sl_pct_range: [8, 12],
            tp_pct_range: [15, 28], # Lower TP for bearish
            trail_pct_range: [7, 12],
            timeout_minutes: [10, 18]
          }
        })

        position_data.pnl_pct = 21.5 # Hits bearish TP (midpoint of [15, 28] = 21.5%)

        expect(service).to receive(:dispatch_exit).with(
          exit_engine,
          tracker,
          a_string_matching(/TP HIT.*regime-based/)
        )

        service.send(:enforce_hard_limits, exit_engine: exit_engine)
      end
    end
  end
end
