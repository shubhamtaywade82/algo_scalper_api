# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::RiskManagerService, '#enforce_trailing_stops' do
  let(:service) { described_class.new }
  let(:exit_engine) { instance_double(Live::ExitEngine) }
  let(:instrument) { create(:instrument, symbol_name: 'NIFTY') }
  let(:tracker) do
    create(:position_tracker,
           instrument: instrument,
           entry_price: 100.0,
           quantity: 50,
           symbol: 'NIFTY24MAR22000CE',
           segment: 'NSE_FNO',
           trade_state: 'expansion')
  end

  before do
    allow(exit_engine).to receive(:execute_exit) do |t, _r|
      t.update!(meta: (t.meta || {}).merge('exit_path' => 'trailing_stop_institutional'))
    end
    allow(Live::TickQuery).to receive(:ltp_for).with(tracker).and_return(ltp)
  end

  describe 'Institutional 3-Phase Trailing' do
    context 'in Phase 1 (Survival)' do
      let(:ltp) { 105.0 } # +5% profit -> SL at 88.0

      it 'does not trigger exit because LTP (105) > SL (88)' do
        expect(exit_engine).not_to receive(:execute_exit)
        service.enforce_trailing_stops(exit_engine: exit_engine)
      end
    end

    context 'in Phase 2 (Breakeven)' do
      let(:ltp) { 110.0 } # +10% profit -> SL at 100.0

      it 'does not trigger exit because LTP (110) > SL (100)' do
        expect(exit_engine).not_to receive(:execute_exit)
        service.enforce_trailing_stops(exit_engine: exit_engine)
      end
    end

    context 'in Phase 3 (HWM Trailing) - No Exit' do
      let(:ltp) { 120.0 } # +20% profit -> SL at 120 * 0.78 = 93.6

      it 'does not trigger exit because LTP (120) > SL (93.6)' do
        expect(exit_engine).not_to receive(:execute_exit)
        service.enforce_trailing_stops(exit_engine: exit_engine)
      end
    end

    context 'in Phase 3 (HWM Trailing) - Triggering Exit' do
      before do
        # First set the high watermark at 200 using a direct call or manual meta update
        tracker.update!(meta: tracker.meta.merge('highest_price' => 200.0))
      end

      # Highest: 200.0
      # Trailing distance: 22%
      # SL: 200 * (1 - 0.22) = 156.0
      let(:ltp) { 150.0 } # Dropped below 156.0

      it 'triggers institutional trailing stop exit' do
        expect(exit_engine).to receive(:execute_exit).with(tracker, /INSTITUTIONAL_TRAILING_STOP|peak_drawdown/i) do |t, _r|
          t.update!(meta: (t.meta || {}).merge('exit_path' => 'trailing_stop_institutional'))
        end
        service.enforce_trailing_stops(exit_engine: exit_engine)

        tracker.reload
        expect(tracker.meta['exit_path']).to eq('trailing_stop_institutional')
      end
    end
  end
end
