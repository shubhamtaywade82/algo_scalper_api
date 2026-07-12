# frozen_string_literal: true

require 'dhan_hq'
require 'date'
require 'time'
require_relative '../utils/logger'

module Api
  # Fetches market data from DhanHQ V2 API using the DhanHQ gem
  # Supports Historical Daily, Intraday Minutes, and Expired Options
  class DhanApiClient
    def initialize(access_token: ENV.fetch('DHAN_ACCESS_TOKEN', nil))
      raise 'Missing DHAN_ACCESS_TOKEN' unless access_token

      # Configure the gem
      DhanHQ.configure do |config|
        config.access_token = access_token
      end
    end

    # Fetch 1, 5, 15, 25, 60 min candles (Last 5 years, max 90 days per request)
    def fetch_intraday_history(security_id:, exchange_segment:, instrument:, interval:, from_date:, to_date:)
      all_data = { timestamp: [], open: [], high: [], low: [], close: [], volume: [], open_interest: [] }

      split_date_range(from_date, to_date, chunk_size: 89).each do |chunk_from, chunk_to|
        payload = {
          security_id: security_id.to_s,
          exchange_segment: exchange_segment,
          instrument: instrument,
          interval: interval.to_s,
          oi: true,
          from_date: chunk_from.to_s, # YYYY-MM-DD
          to_date: chunk_to.to_s      # YYYY-MM-DD
        }

        response = DhanHQ::Models::HistoricalData.intraday(payload)
        raw_data = response.is_a?(Hash) ? response : response.instance_variable_get(:@attributes)
        merge_flat_arrays(all_data, raw_data)
      end

      all_data
    end

    # Fetch daily candles
    def fetch_daily_history(security_id:, exchange_segment:, instrument:, from_date:, to_date:)
      payload = {
        security_id: security_id.to_s,
        exchange_segment: exchange_segment,
        instrument: instrument,
        expiry_code: 0,
        oi: true,
        from_date: from_date.to_s,
        to_date: to_date.to_s
      }

      response = DhanHQ::Models::HistoricalData.historical(payload)
      response.is_a?(Hash) ? response : response.instance_variable_get(:@attributes)
    end

    # Specific for expired options backtesting
    def fetch_expired_options(underlying: :nifty, from_date:, to_date:, interval: '1', option_type: 'CALL', strikes: ['ATM'], expiry_flag: 'WEEK', expiry_code: 1)
      security_id = map_underlying_id(underlying)
      all_data = {}

      split_date_range(from_date, to_date, chunk_size: 29).each do |chunk_from, chunk_to|
        strikes.each do |strike|
          payload = {
            security_id: security_id.to_s,
            exchange_segment: (security_id.to_i == 51 ? 'BSE_FNO' : 'NSE_FNO'),
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

          api_type_key = option_type.to_s.downcase == 'call' ? 'ce' : 'pe'
          strike_data = raw_data.dig('data', api_type_key)

          next unless strike_data && strike_data['timestamp'] && strike_data['timestamp'].any?

          strike_key = "#{strike}_#{option_type}"
          all_data[strike_key] ||= { timestamp: [], open: [], high: [], low: [], close: [], iv: [], oi: [], volume: [], spot: [], strike: [] }

          merge_strike_data(all_data[strike_key], strike_data)
        end
      end

      all_data
    end

    private

    def map_underlying_id(underlying)
      { nifty: 13, banknifty: 25, finnifty: 27, sensex: 51 }.fetch(underlying.to_sym)
    end

    def merge_flat_arrays(target, source)
      return unless source.is_a?(Hash)
      %i[timestamp open high low close volume open_interest].each do |key|
        str_key = key.to_s
        target[key].concat(source[str_key] || []) if source[str_key]
      end
    end

    def merge_strike_data(target, source)
      %i[timestamp open high low close iv oi volume spot strike].each do |key|
        str_key = key.to_s
        target[key].concat(source[str_key] || []) if source[str_key]
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
        
        # Ensure from_date < to_date by extending chunk_to if they are same
        # This only works for historical dates (not today)
        if current == chunk_to
          chunk_to += 1
          # Skip weekend if we just moved to Saturday
          chunk_to += 1 while chunk_to.saturday? || chunk_to.sunday?
        end

        # Final check to ensure we don't return a range where from == to
        # or from > to (which can happen if target < current)
        ranges << [current, chunk_to] if current < chunk_to
        
        current = chunk_to + 1
      end
      ranges
    end

    def format_date_time(date, start_of_day:)
      time_str = start_of_day ? "09:15:00" : "15:30:00"
      "#{date} #{time_str}"
    end
  end
end
