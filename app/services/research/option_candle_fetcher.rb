# frozen_string_literal: true

module Research
  # Fetches expired/rolling option candles for a single contract (symbol +
  # expiry_flag + option_type + strike) via DhanHQ::Models::ExpiredOptionsData,
  # archives the raw response (Layer 1), normalizes it (Layer 2), and upserts
  # it into research_option_bars keyed by contract identity + timestamp so
  # repeat fetches for the same window are idempotent.
  class OptionCandleFetcher < ApplicationService
    REQUIRED_DATA = %w[open high low close volume oi spot strike].freeze
    UNIQUE_BY = %i[underlying_symbol expiry_flag option_type strike_label interval ts].freeze

    def initialize(symbol:, option_type:, expiry_flag:, strike_label:, dhan_strike_param:, from_date:, to_date:,
                    interval: "5", expiry_code: 1)
      @symbol = symbol.to_s.upcase
      @option_type = option_type.to_s.upcase
      @expiry_flag = expiry_flag
      @strike_label = strike_label
      @dhan_strike_param = dhan_strike_param
      @from_date = from_date
      @to_date = to_date
      @interval = interval.to_s
      @expiry_code = expiry_code
    end

    def call
      response = DhanHQ::Models::ExpiredOptionsData.fetch(
        exchange_segment: segment,
        interval: @interval,
        security_id: security_id,
        instrument: "OPTIDX",
        expiry_flag: @expiry_flag,
        expiry_code: @expiry_code,
        strike: @dhan_strike_param,
        drv_option_type: drv_option_type,
        required_data: REQUIRED_DATA,
        from_date: @from_date,
        to_date: @to_date
      )

      raw_fetch = store_raw_fetch(response)
      side_data = response&.data&.[](@option_type == "CE" ? "ce" : "pe")

      rows = Research::OptionBarNormalizer.normalize(
        side_data,
        symbol: @symbol,
        exchange_segment: segment,
        expiry_flag: @expiry_flag,
        option_type: @option_type,
        strike_label: @strike_label,
        interval: @interval
      )
      return [] if rows.blank?

      rows.each { |row| row[:research_raw_fetch_id] = raw_fetch&.id }
      upsert(rows)
    rescue StandardError => e
      log_error("fetch failed for #{@symbol} #{@option_type} #{@strike_label}: #{e.message}")
      []
    end

    private

    def segment
      @symbol == "SENSEX" ? "BSE_FNO" : "NSE_FNO"
    end

    def drv_option_type
      @option_type == "CE" ? "CALL" : "PUT"
    end

    def security_id
      Instrument.segment_index.find_by(symbol_name: @symbol)&.security_id
    end

    def store_raw_fetch(response)
      Research::RawFetch.create!(
        endpoint: "expired_options_data",
        request: request_payload,
        response: response.respond_to?(:data) ? { "data" => response.data } : {},
        fetched_at: Time.current
      )
    rescue StandardError => e
      log_error("failed to persist raw fetch: #{e.message}")
      nil
    end

    def request_payload
      {
        "symbol" => @symbol,
        "option_type" => @option_type,
        "expiry_flag" => @expiry_flag,
        "strike" => @dhan_strike_param,
        "interval" => @interval,
        "from_date" => @from_date,
        "to_date" => @to_date
      }
    end

    def upsert(rows)
      now = Time.current
      records = rows.map { |row| row.merge(created_at: now, updated_at: now) }
      Research::OptionBar.upsert_all(records, unique_by: UNIQUE_BY)

      Research::OptionBar
        .where(underlying_symbol: @symbol, expiry_flag: @expiry_flag, option_type: @option_type,
               strike_label: @strike_label, interval: @interval, ts: rows.map { |row| row[:ts] })
        .order(:ts)
    end
  end
end
