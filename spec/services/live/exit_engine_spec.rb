# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::ExitEngine do
  let(:router) { instance_double(TradingSystem::OrderRouter) }
  let(:risk_manager) { instance_double(Live::RiskManagerService) }

  before do
    allow(Live::RiskManagerService).to receive(:new).and_return(risk_manager)
    allow(risk_manager).to receive(:start)
    allow(risk_manager).to receive(:stop)
    allow(Live::TickCache).to receive(:ltp).and_return(101.5)
    allow(router).to receive(:exit_market).and_return({ success: true })
  end

  it 'marks tracker exited once even when execute_exit is called multiple times' do
    watchable = create(:derivative, :nifty_call_option, security_id: '55111')
    tracker = create(:position_tracker, :option_position, watchable: watchable, instrument: watchable.instrument, status: 'active', segment: 'NSE_FNO', security_id: watchable.security_id)
    engine = described_class.new(order_router: router)

    engine.execute_exit(tracker, 'paper exit')
    engine.execute_exit(tracker, 'duplicate exit')

    tracker.reload
    expect(tracker.status).to eq('exited')
    expect(tracker.meta['exit_reason']).to eq('paper exit')
    expect(router).to have_received(:exit_market).once
  end
end

