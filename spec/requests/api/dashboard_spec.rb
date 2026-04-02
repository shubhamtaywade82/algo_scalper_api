# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'GET /api/dashboard', type: :request do
  before do
    allow(Live::PnlUpdaterService.instance).to receive(:running?).and_return(true)
    allow(Live::OrderUpdateHub.instance).to receive(:running?).and_return(false)
    allow(Live::SystemStatusCache.instance).to receive(:all_statuses).and_return(
      ws_market_feed: false, scheduler: 'running'
    )
    allow(Orders).to receive_message_chain(:config, :gateway, :wallet_snapshot).and_return(
      { cash: 100_000, equity: 0, mtm: 0, exposure: 0 }
    )
    allow(Dhan::IpService).to receive(:fetch_ip_info).and_return(
      { public_ipv4: '1.2.3.4', public_ipv6: nil, registered_ips: [] }
    )
    allow(TradingSignal).to receive_message_chain(:order, :limit, :as_json).and_return([])
    allow(AlgoConfig).to receive(:fetch).and_return({
      risk: { sl_pct: 0.02, tp_pct: 0.04, hard_rupee_sl: 500, profit_floor: 0.01, trailing: {} },
      signals: { enable_adx_filter: true, adx: {}, enable_direction_gate: false },
      trading_time_restrictions: {}
    })
    allow(AlgoConfig).to receive(:mode).and_return('paper')
    allow(Live::TimeRegimeService.instance).to receive(:current_regime).and_return('regular')
    allow(Live::TimeRegimeService.instance).to receive(:regime_config).and_return({})
    allow(IndexConfigLoader).to receive(:load_indices).and_return([])
    allow(PositionTracker).to receive(:paper_trading_stats_with_pct).and_return({})
    allow(Risk::CircuitBreaker.instance).to receive(:status).and_return({ tripped: false })
  end

  it 'includes pnl_updater_running in the system hash' do
    get '/api/dashboard'
    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body['system']['pnl_updater_running']).to eq(true)
  end

  it 'reflects pnl_updater_running as false when service is stopped' do
    allow(Live::PnlUpdaterService.instance).to receive(:running?).and_return(false)
    get '/api/dashboard'
    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body['system']['pnl_updater_running']).to eq(false)
  end

  it 'includes subscribed_indices as an array' do
    get '/api/dashboard'
    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body['subscribed_indices']).to eq([])
  end
end
