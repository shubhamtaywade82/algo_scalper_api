# frozen_string_literal: true

module Providers
  class DhanhqProvider
    SUPPORTED_API_TYPES = %i[order_api data_api quote_api option_chain non_trading_api].freeze
    DEFAULT_API_TYPE = :option_chain

    def initialize(client: default_client)
      @client = client
      @tick_cache = Live::RedisTickCache.instance
    end

    def underlying_spot(index)
      inst = index_config(index)
      raise "missing_index_config:#{index}" unless inst

      tick = @tick_cache.fetch_tick(inst[:segment], inst[:sid])
      tick&.dig(:ltp)&.to_f
    end

    def option_chain(index)
      inst = index_config(index)
      raise "missing_index_config:#{index}" unless inst
      raise 'dhanhq_client_missing' unless @client

      chain = @client.option_chain(inst[:key])
      Array(chain).map do |opt|
        {
          strike: opt.respond_to?(:strike) ? opt.strike : opt[:strike],
          type: opt.respond_to?(:option_type) ? opt.option_type : opt[:option_type],
          ltp: opt.respond_to?(:ltp) ? opt.ltp : opt[:ltp],
          bid: opt.respond_to?(:bid_price) ? opt.bid_price : opt[:bid_price],
          ask: opt.respond_to?(:ask_price) ? opt.ask_price : opt[:ask_price],
          oi: opt.respond_to?(:open_interest) ? opt.open_interest : opt[:open_interest],
          iv: opt.respond_to?(:iv) ? opt.iv : opt[:iv],
          volume: opt.respond_to?(:volume) ? opt.volume : opt[:volume]
        }
      end
    end

    private

    def index_config(index)
      key = index.to_s.upcase
      Array(AlgoConfig.fetch[:indices]).find { |cfg| cfg[:key].to_s.upcase == key }
    end

    def default_client
      api_type = fetch_api_type
      DhanHQ::Client.new(api_type: api_type)
    rescue StandardError => e
      Rails.logger.warn("[Providers::DhanhqProvider] Failed to build client: #{e.message}")
      nil
    end

    def fetch_api_type
      raw = ENV['DHAN_API_TYPE'] || ENV.fetch('DHANHQ_API_TYPE', nil)
      return DEFAULT_API_TYPE unless raw

      candidate = raw.to_s.strip.downcase.to_sym
      SUPPORTED_API_TYPES.include?(candidate) ? candidate : DEFAULT_API_TYPE
    end
  end
end
