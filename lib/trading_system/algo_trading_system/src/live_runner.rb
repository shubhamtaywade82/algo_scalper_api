# frozen_string_literal: true

require_relative 'utils/config'
require_relative 'utils/logger'
require_relative 'utils/time_helpers'
require_relative 'utils/event_bus'
require_relative 'api/dhan_api_client'
require_relative 'api/websocket_feed'
require_relative 'market_data/tick_normalizer'
require_relative 'market_data/candle_aggregator'
require_relative 'strategies/trading_strategies'
require_relative 'execution/live_engine'

module AlgoTradingSystem
  # Orchestrates live trading session with real-time data and strategy execution
  class LiveRunner
    SYMBOL_MAP = {
      'NIFTY' => { id: '13', segment: 'NSE_FNO' },
      'BANKNIFTY' => { id: '25', segment: 'NSE_FNO' },
      'FINNIFTY' => { id: '27', segment: 'NSE_FNO' },
      'SENSEX' => { id: '51', segment: 'BSE_FNO' }
    }.freeze

    def initialize(strategy_name:, symbol:, env: 'paper', interval: 1, dependencies: {})
      Utils::Config.load!
      @symbol = symbol.upcase
      @env = env
      @strategy_name = strategy_name
      @interval = interval
      @dependencies = dependencies
      @event_bus = Utils::EventBus.instance

      @symbol_info = SYMBOL_MAP[@symbol] || SYMBOL_MAP['NIFTY']

      setup_api
      setup_strategy
      setup_execution
      setup_aggregator
    end

    def start
      Utils::Logger.info('system.starting', env: @env, strategy: @strategy_name, symbol: @symbol, interval: @interval)

      pre_load_historical_data

      @ws.connect
      # Subscribe to the specified symbol for Spot data and Option for trading
      @ws.subscribe([{ ExchangeSegment: @symbol_info[:segment], SecurityId: @symbol_info[:id] }])

      subscribe_to_events

      loop do
        sleep 1
        break if Utils::TimeHelpers.exit_window?
      end

      stop
    end

    def stop
      Utils::Logger.info('system.stopping')
      @ws.disconnect
    end

    private

    def pre_load_historical_data
      Utils::Logger.info('system.pre_loading_data', symbol: @symbol)

      # Fetch last 5 days of data ending YESTERDAY to warm up indicators
      # This avoids DH-905 errors if the market hasn't opened yet today.
      to_date = Date.today - 1
      from_date = to_date - 5

      data = @api_client.fetch_intraday_history(
        security_id: @symbol_info[:id],
        exchange_segment: @symbol_info[:segment],
        instrument: 'INDEX',
        interval: @interval.to_s,
        from_date: from_date,
        to_date: to_date
      )

      return unless data[:timestamp]

      # Convert to candles and feed to strategy
      data[:timestamp].each_with_index do |ts, i|
        candle = OpenStruct.new(
          timestamp: Time.at(ts),
          open: data[:open][i],
          high: data[:high][i],
          low: data[:low][i],
          close: data[:close][i],
          volume: data[:volume][i]
        )
        @strategy.add_bar(candle)
      end

      Utils::Logger.info('system.pre_load_complete', bar_count: data[:timestamp].size)
    end

    def setup_api
      client_id = ENV.fetch('DHAN_CLIENT_ID', 'test')
      token = ENV.fetch('DHAN_ACCESS_TOKEN', 'test')

      @api_client = @dependencies[:api_client] || Api::DhanApiClient.new(access_token: token)
      @ws = @dependencies[:ws_feed] || Api::WebsocketFeed.new(client_id: client_id, access_token: token)
    end

    def setup_strategy
      @strategy = @dependencies[:strategy] || TradingStrategies::StrategyFactory.create(@strategy_name)
    end

    def setup_execution
      @engine = @dependencies[:execution_engine] || Execution::LiveEngine.new(@api_client, @strategy, @symbol)
    end

    def setup_aggregator
      @aggregator = MarketData::CandleAggregator.new(interval_minutes: @interval)
      @aggregator.on_candle_close do |candle|
        @engine.process_candle(candle)
      end
    end

    def subscribe_to_events
      @event_bus.subscribe('market_data.tick') do |payload|
        tick = MarketData::TickNormalizer.normalize(payload[:tick])
        @aggregator.process_tick(tick)
        @engine.process_tick(tick)
      end
    end
  end
end
