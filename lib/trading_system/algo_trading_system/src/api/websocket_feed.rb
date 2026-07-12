# frozen_string_literal: true

require 'websocket-client-simple'
require 'json'

module Api
  # WebSocket client for live market data feed
  class WebsocketFeed
    WS_URL = 'wss://api-feed.dhan.co'

    def initialize(client_id: ENV.fetch('DHAN_CLIENT_ID', 'test'), access_token: ENV.fetch('DHAN_ACCESS_TOKEN', 'test'))
      @client_id = client_id
      @access_token = access_token
      @ws = nil
    end

    def connect
      headers = {
        'access-token' => @access_token,
        'client-id' => @client_id
      }

      @ws = WebSocket::Client::Simple.connect(WS_URL, headers: headers)
      setup_handlers
    end

    def subscribe(instruments)
      payload = {
        RequestCode: 15,
        InstrumentCount: instruments.size,
        InstrumentList: instruments
      }
      @ws.send(payload.to_json)
    end

    def disconnect
      @ws&.close
    end

    private

    def setup_handlers
      @ws.on :message do |msg|
        begin
          data = JSON.parse(msg.data, symbolize_names: true)
          if data && data[:type] == 'ticker' && defined?(::Utils::EventBus)
            ::Utils::EventBus.publish('market_data.tick', tick: data)
          end
        rescue StandardError
          # Ignore parse errors
        end
      end

      @ws.on :open do
        ::Utils::Logger.info('websocket.connected', url: WS_URL) if defined?(::Utils::Logger)
      end

      @ws.on :close do |e|
        ::Utils::Logger.info('websocket.disconnected', reason: e) if defined?(::Utils::Logger)
      end

      @ws.on :error do |e|
        ::Utils::Logger.error('websocket.error', error: e.message) if defined?(::Utils::Logger)
      end
    end
  end
end
