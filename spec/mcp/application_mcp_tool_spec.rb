# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ApplicationMCPTool do
  let(:snapshot) do
    {
      'generated_at' => '2026-11-17T10:00:00+05:30', 'mode' => 'paper', 'session' => { 'status' => 'open' },
      'indices' => [{ 'index_key' => 'NIFTY' }, { 'index_key' => 'SENSEX' }],
      'market_context' => {}, 'setup' => { 'decision' => 'NO_TRADE' },
      'risk' => { 'circuit_breaker' => { 'tripped' => false } },
      'health' => { 'status' => 'ok' }, 'freshness' => {}, 'warnings' => []
    }
  end

  before do
    Rails.application.eager_load!
    allow(Reports::MarketBrief::SnapshotBuilder).to receive(:call).and_return(snapshot)
  end

  it 'exposes only the reviewed read-only tools' do
    expect(ActionMCP::ToolsRegistry.tools.keys).to contain_exactly(
      'get_market_overview', 'get_risk_status', 'get_system_health',
      'get_market_regime', 'get_feed_health', 'get_trading_signals',
      'get_open_positions', 'get_position_details', 'get_closed_positions', 'get_live_pnl',
      'get_circuit_breaker_status', 'get_daily_trade_limits',
      'get_trading_mode', 'get_enabled_indices', 'get_algo_config',
      'get_reconciliation', 'get_experiment_history'
    )
  end

  it 'never references order placement from MCP code' do
    code_lines = Rails.root.glob('app/mcp/**/*.rb').flat_map { |f| f.readlines.grep_v(/^\s*#/) }
    sources = code_lines.join
    expect(sources).not_to match(/Orders::|Gateway(Live|Paper|Factory)|Placer|place_market|DhanHQ::Models::Order/)
  end

  it 'filters the market overview to the requested index' do
    response = GetMarketOverviewTool.new(index: 'NIFTY').call
    payload = JSON.parse(response.contents.first.text)

    expect(payload['indices'].pluck('index_key')).to eq(['NIFTY'])
  end

  describe ApplicationGateway do
    def gateway_for(authorization, remote_addr: '10.0.0.5', **headers)
      env = Rack::MockRequest.env_for('/', 'HTTP_AUTHORIZATION' => authorization, 'REMOTE_ADDR' => remote_addr, **headers)
      described_class.new(ActionDispatch::Request.new(env))
    end

    around do |example|
      original = ENV.fetch('MCP_API_TOKEN', nil)
      ENV['MCP_API_TOKEN'] = 'secret-token'
      example.run
    ensure
      ENV['MCP_API_TOKEN'] = original
    end

    it 'lets clients on this machine in without a token' do
      expect { gateway_for(nil, remote_addr: '127.0.0.1').call }.not_to raise_error
      expect { gateway_for(nil, remote_addr: '::1').call }.not_to raise_error
    end

    it 'does not treat proxied loopback traffic as local' do
      proxied = gateway_for(nil, remote_addr: '127.0.0.1', 'HTTP_X_FORWARDED_FOR' => '203.0.113.9')
      expect { proxied.call }.to raise_error(ActionMCP::UnauthorizedError)
    end

    it 'accepts the configured bearer token' do
      expect { gateway_for('Bearer secret-token').call }.not_to raise_error
    end

    it 'rejects a wrong token' do
      expect { gateway_for('Bearer nope').call }.to raise_error(ActionMCP::UnauthorizedError)
    end

    it 'allows tokenless access outside production when no token is configured' do
      ENV['MCP_API_TOKEN'] = nil
      expect { gateway_for(nil).call }.not_to raise_error
    end

    it 'fails closed in production when no token is configured' do
      ENV['MCP_API_TOKEN'] = nil
      allow(Rails.env).to receive(:production?).and_return(true)
      expect { gateway_for('Bearer anything').call }.to raise_error(ActionMCP::UnauthorizedError)
    end
  end
end
