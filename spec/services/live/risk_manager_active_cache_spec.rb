# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::RiskManagerService, '#enforce_hard_limits via ActiveCache' do
  let(:service) { described_class.new }
  let(:watchable) { create(:derivative, :nifty_call_option, security_id: '44223') }
  let(:tracker) do
    create(
      :position_tracker,
      :option_position,
      watchable: watchable,
      instrument: watchable.instrument,
      entry_price: BigDecimal('100.0'),
      quantity: 25,
      segment: 'NSE_FNO',
      security_id: watchable.security_id
    )
  end
  let(:position_data) do
    Positions::ActiveCache::PositionData.new(
      tracker_id: tracker.id,
      security_id: tracker.security_id,
      segment: tracker.segment,
      entry_price: tracker.entry_price,
      quantity: tracker.quantity,
      pnl: BigDecimal('2500'),
      pnl_pct: 25.0,
      high_water_mark: BigDecimal('3000'),
      last_updated_at: Time.current
    )
  end
  let(:active_cache) { instance_double(Positions::ActiveCache, all_positions: [position_data]) }

  before do
    allow(Positions::ActiveCache).to receive(:instance).and_return(active_cache)
    allow(service).to receive(:risk_config).and_return(sl_pct: 0.1, tp_pct: 0.2, exit_drop_pct: 0.03, min_profit_rupees: 0)
  end

  it 'dispatches exits using tracker data from ActiveCache' do
    expect(service).to receive(:dispatch_exit).with(service, tracker, a_string_matching(/TP HIT/))

    service.send(:enforce_hard_limits, exit_engine: service)
  end

  it 'skips exit when pnl percentage below thresholds' do
    position_data.pnl_pct = 5.0

    expect(service).not_to receive(:dispatch_exit)

    service.send(:enforce_hard_limits, exit_engine: service)
  end
end

