# frozen_string_literal: true

# app/services/options/expired_fetcher.rb
module Options
  class ExpiredFetcher < ApplicationService
    def initialize(symbol:, expiry_flag: 'WEEK', date: Time.zone.today)
      @symbol = symbol
      @expiry_flag = normalize_expiry_flag(symbol, expiry_flag)
      @date = date
    end

    # Fetches CE and PE OHLC arrays
    # def call
    #   date_str = normalize_date_string(@date)
    #   pp date_str
    #   { ce: 'CALL', pe: 'PUT' }.to_h do |side_key, opt_type|
    #     data = DhanHQ::Models::ExpiredOptionsData.fetch(
    #       exchange_segment: segment_for(@symbol),
    #       interval: '5',
    #       security_id: security_id_for(@symbol),
    #       instrument: 'OPTIDX',
    #       expiry_flag: @expiry_flag,
    #       expiry_code: 1,
    #       strike: 'ATM',
    #       drv_option_type: opt_type,
    #       required_data: %w[open high low close volume oi spot strike],
    #       from_date: date_str,
    #       to_date: date_str
    #     )
    #     [side_key, parse_data(data, side_key)]
    #   end
    # rescue StandardError => e
    #   Rails.logger.error("[ExpiredFetcher] Failed: #{e.message}")
    #   { ce: [], pe: [] }
    # end

    def call
      cache_key = "expired_option_data:#{@symbol}:#{@date}:#{@expiry_flag}"

      cached_data = Rails.cache.read(cache_key)
      return cached_data if cached_data.present?

      date_str = normalize_date_string(@date)
      Rails.logger.debug date_str
      result = { ce: 'CALL', pe: 'PUT' }.to_h do |side_key, opt_type|
        data = DhanHQ::Models::ExpiredOptionsData.fetch(
          exchange_segment: segment_for(@symbol),
          interval: '5',
          security_id: security_id_for(@symbol),
          instrument: 'OPTIDX',
          expiry_flag: @expiry_flag,
          expiry_code: 1,
          strike: 'ATM',
          drv_option_type: opt_type,
          required_data: %w[open high low close volume oi spot strike],
          from_date: date_str,
          to_date: date_str
        )
        [side_key, parse_data(data, side_key)]
      end

      Rails.cache.write(cache_key, result, expires_in: 24.hours)
      result
    rescue StandardError => e
      Rails.logger.error("[ExpiredFetcher] Failed: #{e.message}")
      { ce: [], pe: [] }
    end

    private

    def normalize_date_string(value)
      return value.strftime('%Y-%m-%d') if value.is_a?(Date)
      return value.to_date.strftime('%Y-%m-%d') if value.respond_to?(:to_date)

      Date.parse(value.to_s).strftime('%Y-%m-%d')
    rescue StandardError
      Time.zone.today.strftime('%Y-%m-%d')
    end

    def normalize_expiry_flag(symbol, requested_flag)
      return requested_flag if requested_flag.to_s.upcase == 'MONTH'

      sym = symbol.to_s.upcase
      # Only NIFTY and SENSEX support weekly expiries; BANKNIFTY is monthly-only
      if %w[NIFTY SENSEX].include?(sym)
        'WEEK'
      else
        'MONTH'
      end
    end

    def security_id_for(symbol)
      Instrument.segment_index.find_by(symbol_name: symbol)&.security_id
    end

    def segment_for(symbol)
      sym = symbol.to_s.upcase
      case sym
      when 'SENSEX'
        'BSE_FNO'
      else
        'NSE_FNO'
      end
    end

    def parse_data(data, side_key)
      # Map :ce/:pe to API keys 'ce'/'pe'
      side = side_key == :ce ? 'ce' : 'pe'
      d = data&.data&.[](side)
      return [] unless d && d['timestamp']

      d['timestamp'].map.with_index do |ts, i|
        {
          timestamp: Time.at(ts).in_time_zone('Asia/Kolkata'),
          open: d['open'][i].to_f,
          high: d['high'][i].to_f,
          low: d['low'][i].to_f,
          close: d['close'][i].to_f,
          volume: d['volume'][i].to_i,
          oi: d['oi'][i].to_i,
          spot: d['spot'][i].to_f,
          strike: d['strike'][i].to_f
        }
      end
    end
  end
end
