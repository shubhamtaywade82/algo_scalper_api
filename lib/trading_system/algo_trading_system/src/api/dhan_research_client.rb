# frozen_string_literal: true

require 'dhan_hq'
require 'date'
require_relative '../utils/logger'

module Api
  # Specialized client for fetching historical research data using the DhanHQ gem.
  class DhanResearchClient
    def initialize(access_token: ENV.fetch('DHAN_ACCESS_TOKEN', nil))
      raise 'Missing DHAN_ACCESS_TOKEN' unless access_token

      # Configure the gem
      DhanHQ.configure do |config|
        config.access_token = access_token
      end
    end

    # Fetch intraday index candles (Spot)
    def fetch_spot_intraday(security_id:, from_date:, to_date:, interval: '1')
      all_data = { timestamp: [], open: [], high: [], low: [], close: [], volume: [] }

      split_date_range(from_date, to_date, chunk_size: 89).each do |chunk_from, chunk_to|
        ::Utils::Logger.info("research.fetching_spot", security_id: security_id, from: chunk_from, to: chunk_to)
        
        payload = {
          security_id: (security_id.to_i == 51 ? '1' : security_id.to_s),
          exchange_segment: 'IDX_I',
          instrument: 'INDEX',
          interval: interval.to_s,
          oi: false,
          from_date: chunk_from.to_s,
          to_date: chunk_to.to_s
        }

        response = DhanHQ::Models::HistoricalData.intraday(payload)
        # DhanHQ.intraday often returns HashWithIndifferentAccess directly
        raw_data = response.is_a?(Hash) ? response : response.instance_variable_get(:@attributes)
        
        if raw_data && raw_data['timestamp']
          ::Utils::Logger.info("research.raw_spot", count: raw_data['timestamp'].size)
          merge_flat_arrays(all_data, raw_data)
        else
          ::Utils::Logger.error("research.empty_spot", response: raw_data)
        end
      end

      all_data
    end

    # Fetch expired options data (Rolling Options)
    def fetch_rolling_options(security_id:, option_type:, from_date:, to_date:, interval: '1', strike: 'ATM', expiry_flag: 'WEEK', expiry_code: 1)
      all_data = { timestamp: [], open: [], high: [], low: [], close: [], volume: [], iv: [], oi: [], strike: [], spot: [] }

      split_date_range(from_date, to_date, chunk_size: 29).each do |chunk_from, chunk_to|
        ::Utils::Logger.info("research.fetching_options", security_id: security_id, strike: strike, type: option_type, from: chunk_from, to: chunk_to)

        payload = {
          security_id: security_id.to_s,
          exchange_segment: ([1, 51].include?(security_id.to_i) ? 'BSE_FNO' : 'NSE_FNO'),
          instrument: 'OPTIDX',
          interval: interval.to_s,
          expiry_flag: expiry_flag,
          expiry_code: expiry_code.to_i,
          strike: strike,
          drv_option_type: option_type.to_s.upcase,
          required_data: %w[open high low close iv volume strike oi spot],
          from_date: chunk_from.to_s,
          to_date: chunk_to.to_s
        }

        response = DhanHQ::Models::ExpiredOptionsData.fetch(payload)
        raw_data = response.is_a?(Hash) ? response : response.instance_variable_get(:@attributes)

        # The gem returns a Hash with 'data' -> 'ce' or 'pe'
        api_type_key = option_type.to_s.downcase == 'call' ? 'ce' : 'pe'
        strike_data = raw_data.dig('data', api_type_key)
        
        if strike_data && strike_data['timestamp']
          ::Utils::Logger.info("research.raw_options", count: strike_data['timestamp'].size)
          merge_strike_data(all_data, strike_data)
        else
          ::Utils::Logger.error("research.empty_options", response: raw_data)
        end
      end

      all_data
    end

    private

    def merge_flat_arrays(target, source)
      return unless source.is_a?(Hash)
      %w[timestamp open high low close volume].each do |key|
        target[key.to_sym].concat(source[key] || []) if source[key]
      end
    end

    def merge_strike_data(target, source)
      %w[timestamp open high low close iv volume strike oi spot].each do |key|
        target[key.to_sym].concat(source[key] || []) if source[key]
      end
    end

    def split_date_range(from, to, chunk_size:)
      ranges = []
      current = Date.parse(from.to_s)
      target = Date.parse(to.to_s)
      while current <= target
        # Skip weekends for the start of the chunk
        current += 1 while current.saturday? || current.sunday?
        break if current > target

        chunk_to = [current + chunk_size, target].min
        ranges << [current, chunk_to]
        current = chunk_to + 1
      end
      ranges
    end

    def format_date_time(date, start_of_day:)
      # Removed unused method
    end
  end
end
