# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Risk::Rules::VixForceExitRule do
  subject(:rule) { described_class.new(config: {}) }

  let(:tracker) { instance_double(PositionTracker, order_no: 'ORD001') }
  let(:context) { instance_double(Risk::Rules::RuleContext, active?: true, tracker: tracker) }

  before do
    allow(AlgoConfig).to receive(:fetch).and_return(market: { vix_gate: { enabled: true } })
    allow(Market::VixGate).to receive(:force_exit_active?).and_return(true)
    allow(Market::VixGate).to receive(:current_ltp).and_return(23.4)
  end

  it 'exits when VIX force-exit gate is active' do
    result = rule.evaluate(context)

    expect(result.exit?).to be(true)
    expect(result.reason).to include('VIX_FORCE_EXIT')
  end
end
