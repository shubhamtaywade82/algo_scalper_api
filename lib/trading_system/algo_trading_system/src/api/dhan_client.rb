# frozen_string_literal: true

require 'faraday'
require 'faraday/retry'
require 'json'

module Api
  # REST API client for DhanHQ
  class DhanClient
    BASE_URL = 'https://api.dhan.co'

    def initialize(client_id: ENV.fetch('DHAN_CLIENT_ID', 'test'), access_token: ENV.fetch('DHAN_ACCESS_TOKEN', 'test'))
      @client_id = client_id
      @access_token = access_token
    end

    def place_order(payload)
      post('/orders', payload)
    end

    def modify_order(order_id, payload)
      put("/orders/#{order_id}", payload)
    end

    def cancel_order(order_id)
      delete("/orders/#{order_id}")
    end

    def get_orders
      get('/orders')
    end

    def get_positions
      get('/positions')
    end

    def get_holdings
      get('/holdings')
    end

    def get_fund_limit
      get('/fundlimit')
    end

    def historical_candles(payload)
      post('/charts/historical', payload)
    end

    def intraday_candles(payload)
      post('/charts/intraday', payload)
    end

    def market_quote(payload)
      post('/marketfeed/ltp', payload)
    end

    def option_chain(underlying_scrip, underlying_seg, expiry)
      get('/optionchain', {
        'UnderlyingScrip' => underlying_scrip,
        'UnderlyingSeg' => underlying_seg,
        'Expiry' => expiry
      })
    end

    private

    def connection
      @connection ||= Faraday.new(url: BASE_URL) do |f|
        f.request :json
        f.response :json, parser_options: { symbolize_names: true }

        # Rate limiting / retry logic
        f.request :retry, max: 3, interval: 0.1, backoff_factor: 2,
                          retry_statuses: [429, 500, 502, 503, 504],
                          methods: [:get, :post, :put, :delete]

        f.headers['access-token'] = @access_token
        f.headers['client-id'] = @client_id
        f.headers['Content-Type'] = 'application/json'
        f.headers['Accept'] = 'application/json'

        f.adapter Faraday.default_adapter
      end
    end

    def get(path, params = {})
      handle_response { connection.get(path, params) }
    end

    def post(path, body = {})
      handle_response { connection.post(path, body) }
    end

    def put(path, body = {})
      handle_response { connection.put(path, body) }
    end

    def delete(path)
      handle_response { connection.delete(path) }
    end

    def handle_response
      response = yield
      unless response.success?
        # We assume Utils::Logger is available
        if defined?(::Utils::Logger)
          ::Utils::Logger.error("api.request_failed", status: response.status, body: response.body)
        end
        raise "API Error: #{response.status} - #{response.body}"
      end
      response.body
    rescue Faraday::Error => e
      if defined?(::Utils::Logger)
        ::Utils::Logger.error("api.connection_error", error: e.message)
      end
      raise e
    end
  end
end
