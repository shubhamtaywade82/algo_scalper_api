# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Demand driven services' do
  let(:feature_config) do
    {
      feature_flags: { enable_demand_driven_services: true },
      risk: { loop_interval_idle: 5000, loop_interval_active: 500 }
    }
  end

  let(:empty_cache) { instance_double(Positions::ActiveCache, empty?: true) }

  before do
    allow(AlgoConfig).to receive(:fetch).and_return(feature_config)
    allow(Positions::ActiveCache).to receive(:instance).and_return(empty_cache)
  end

  it 'uses idle vs active intervals for RiskManagerService' do
    service = Live::RiskManagerService.new
    expect(service.send(:loop_sleep_interval, true)).to eq(5.0)
    expect(service.send(:loop_sleep_interval, false)).to eq(0.5)
  ensure
    service.instance_variable_get(:@watchdog_thread)&.kill
  end

  it 'computes intervals for PnlUpdaterService based on queue state' do
    service = Live::PnlUpdaterService.instance
    service.stop!
    expect(service.send(:next_interval, queue_empty: true)).to eq(5.0)
    expect(service.send(:next_interval, queue_empty: false)).to eq(0.5)
  end

  it 'derives idle/active intervals for PaperPnlRefresher' do
    refresher = Live::PaperPnlRefresher.new
    expect(refresher.send(:idle_interval_seconds)).to eq(5.0)
    expect(refresher.send(:active_interval_seconds)).to eq(0.5)
  end
end
