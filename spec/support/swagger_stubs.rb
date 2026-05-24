# frozen_string_literal: true

# Shared doubles for RSwag / OpenAPI request examples (keeps response shapes realistic).
module SwaggerStubs
  def stub_health_dependencies!
    allow(Live::MarketFeedHub.instance).to receive(:health_status).and_return(
      running: true,
      connected: true,
      connection_state: 'open',
      started_at: Time.current.iso8601,
      last_tick_at: Time.current.iso8601
    )
    hub = Live::OrderUpdateHub.instance
    allow(hub).to receive(:respond_to?).and_call_original
    allow(hub).to receive(:respond_to?).with(:health_status).and_return(false)
    allow(Dhan::IpService).to receive(:fetch_ip_info).and_return(
      public_ipv4: '198.51.100.1', public_ipv6: nil, registered_ips: []
    )
    allow(Live::TickCache).to receive(:all).and_return({})
    allow(Live::TickCache).to receive(:ltp).and_return(24_000.0)
    allow(Risk::CircuitBreaker.instance).to receive(:status).and_return({ tripped: false })
    allow(AlgoConfig).to receive(:mode).and_return('paper')
  end

  def stub_dashboard_dependencies!
    stub_health_dependencies!
    allow(Live::PnlUpdaterService.instance).to receive(:running?).and_return(true)
    allow(Live::OrderUpdateHub.instance).to receive(:running?).and_return(false)
    allow(Live::SystemStatusCache.instance).to receive(:all_statuses).and_return(
      ws_market_feed: false, scheduler: 'running'
    )
    allow(Orders).to receive_message_chain(:config, :gateway, :wallet_snapshot).and_return(
      { cash: 100_000, equity: 0, mtm: 0, exposure: 0 }
    )
    allow(TradingSignal).to receive_message_chain(:order, :limit, :as_json).and_return([])
    allow(AlgoConfig).to receive(:fetch).and_return({
      risk: { sl_pct: 0.02, tp_pct: 0.04, hard_rupee_sl: 500, profit_floor: 0.01, trailing: {} },
      signals: { enable_adx_filter: true, adx: {}, enable_direction_gate: false },
      trading_time_restrictions: {}
    })
    allow(Live::TimeRegimeService.instance).to receive(:current_regime).and_return('regular')
    allow(Live::TimeRegimeService.instance).to receive(:regime_config).and_return({})
    allow(IndexConfigLoader).to receive(:load_indices).and_return([])
    allow(PositionTracker).to receive(:paper_trading_stats_with_pct).and_return({})
  end

  def stub_dhan_access_token!
    allow(Dhan::TokenManager).to receive(:current_token).and_return('mock-dhan-access-token')
    allow(DhanAccessToken).to receive(:active).and_return(
      double('DhanAccessToken', token: 'mock-dhan-access-token', expiry_time: 1.day.from_now)
    )
  end

  def stub_analysis_show_dependencies!(instrument)
    allow(IndexConfigLoader).to receive(:load_indices).and_return(
      [
        { key: 'NIFTY', segment: instrument.exchange_segment, sid: instrument.security_id.to_s }
      ]
    )
    allow(Instrument).to receive(:find_by_sid_and_segment).and_return(instrument)
    allow(AnalysisStore).to receive(:read_all).and_return({})
    allow(AnalysisStore).to receive(:stale_components).and_return([])
    allow(Live::TickCache).to receive(:ltp).and_return(22_450.0)
    allow(Live::TimeRegimeService.instance).to receive(:current_regime).and_return('regular')
    allow(AlgoConfig).to receive(:fetch).and_return({ risk: {}, indices: [] })
  end
end

RSpec.configure do |config|
  config.include SwaggerStubs, file_path: %r{/spec/requests/api_docs/}
end
