# frozen_string_literal: true

require 'spec_helper'
require_relative '../src/live_runner'

RSpec.describe AlgoTradingSystem::LiveRunner do
  let(:mock_api_client) { instance_double('Api::DhanApiClient') }
  let(:mock_ws_feed) { instance_double('Api::WebsocketFeed', connect: true, subscribe: true, disconnect: true) }
  let(:mock_strategy) { instance_double('TradingStrategies::RSIMACDReversal') }

  let(:runner) do
    described_class.new(
      strategy_name: 'rsi_macd',
      symbol: 'NIFTY',
      env: 'paper',
      dependencies: {
        api_client: mock_api_client,
        ws_feed: mock_ws_feed,
        strategy: mock_strategy
      }
    )
  end

  before do
    allow(Utils::TimeHelpers).to receive(:exit_window?).and_return(true)
    allow(runner).to receive(:sleep)
  end

  describe '#start' do
    it 'connects, subscribes, and stops when exit window is reached' do
      expect(mock_api_client).to receive(:fetch_intraday_history).and_return({ timestamp: [] })
      expect(mock_ws_feed).to receive(:connect)
      expect(mock_ws_feed).to receive(:subscribe).with([{ ExchangeSegment: 'NSE_FNO', SecurityId: '13' }])
      expect(mock_ws_feed).to receive(:disconnect)

      runner.start
    end

    it 'uses correct SecurityId for SENSEX' do
      sensex_runner = described_class.new(
        strategy_name: 'rsi_macd',
        symbol: 'SENSEX',
        env: 'paper',
        dependencies: {
          api_client: mock_api_client,
          ws_feed: mock_ws_feed,
          strategy: mock_strategy
        }
      )
      allow(sensex_runner).to receive(:sleep)

      expect(mock_api_client).to receive(:fetch_intraday_history).with(hash_including(security_id: '51', exchange_segment: 'BSE_FNO')).and_return({ timestamp: [] })
      expect(mock_ws_feed).to receive(:subscribe).with([{ ExchangeSegment: 'BSE_FNO', SecurityId: '51' }])

      sensex_runner.start
    end
  end
end
