# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'

module Instruments
  # Syncs one exchange segment from Dhan's segmentwise instrument-list API:
  #
  #   GET https://api.dhan.co/v2/instrument/{exchangeSegment}
  #
  # The segmentwise endpoint is the surgical alternative to the full scrip
  # master CSV: refreshing just the FNO segment (where contracts churn daily)
  # without re-ingesting thousands of equity rows. Rows land in the same
  # canonical `instruments` master with the same upsert semantics as
  # InstrumentsImporter.
  #
  # exchangeSegment values follow the app-wide DhanHQ segment codes
  # (IDX_I, NSE_EQ, BSE_EQ, NSE_FNO, BSE_FNO, NSE_CURRENCY, BSE_CURRENCY,
  # MCX_COMM).
  class SegmentImporter
    BASE_URL = 'https://api.dhan.co/v2/instrument'.freeze
    BATCH_SIZE = 1_000
    TIMEOUT_SECONDS = 120

    # Dhan exchange-segment code -> our DB (exchange, segment) pair.
    SEGMENT_MAP = {
      'IDX_I'        => %w[NSE I],
      'BSE_IDX'      => %w[BSE I],
      'NSE_EQ'       => %w[NSE E],
      'BSE_EQ'       => %w[BSE E],
      'NSE_FNO'      => %w[NSE D],
      'BSE_FNO'      => %w[BSE D],
      'NSE_CURRENCY' => %w[NSE C],
      'BSE_CURRENCY' => %w[BSE C],
      'MCX_COMM'     => %w[MCX M]
    }.freeze

    # The API is documented with camelCase keys; the same master is also
    # published as a CSV with SNAKE_CAPS headers. Accept both so a Dhan
    # rename cannot silently null out contract attributes.
    FIELD_ALIASES = {
      security_id:        %w[securityId security_id SECURITY_ID],
      isin:               %w[isin ISIN],
      instrument_code:    %w[instrumentCode instrument_code INSTRUMENT],
      underlying_security_id: %w[underlyingSecurityId underlying_security_id UNDERLYING_SECURITY_ID],
      underlying_symbol:  %w[underlyingSymbol underlying_symbol UNDERLYING_SYMBOL],
      symbol_name:        %w[symbolName symbol_name SYMBOL_NAME],
      display_name:       %w[displayName display_name DISPLAY_NAME],
      instrument_type:    %w[instrumentType instrument_type INSTRUMENT_TYPE],
      series:             %w[series SERIES],
      lot_size:           %w[lotSize lot_size LOT_SIZE],
      expiry_date:        %w[sm_EXPIRY_DATE expiryDate expiry_date SM_EXPIRY_DATE],
      strike_price:       %w[strikePrice strike_price STRIKE_PRICE],
      option_type:        %w[optionType option_type OPTION_TYPE],
      tick_size:          %w[tickSize tick_size TICK_SIZE],
      expiry_flag:        %w[expiryFlag expiry_flag EXPIRY_FLAG]
    }.freeze

    class << self
      # @param exchange_segment [String] e.g. "NSE_FNO"
      # @return [Hash] summary { rows:, upserts:, segment:, linked:, expired_flagged: }
      def import_segment(exchange_segment)
        segment_code = exchange_segment.to_s.upcase
        mapping = SEGMENT_MAP[segment_code]
        raise ArgumentError, "Unknown exchange segment #{exchange_segment.inspect}" if mapping.nil?

        payload = fetch_payload(segment_code)
        rows = payload.filter_map { |raw| build_row(raw, mapping) }

        upserts = if rows.empty?
                    0
                  else
                    Instrument.import(
                      rows,
                      batch_size: BATCH_SIZE,
                      on_duplicate_key_update: {
                        conflict_target: %i[exchange segment security_id],
                        columns: refreshed_columns
                      }
                    ).ids.size
                  end

        linked = InstrumentsImporter.link_underlying_instruments!
        expired = InstrumentsImporter.mark_expired_contracts_untradable!

        {
          segment: segment_code,
          rows: rows.size,
          upserts: upserts,
          linked: linked,
          expired_flagged: expired
        }
      rescue StandardError => e
        Rails.logger.error("[Instruments::SegmentImporter] #{segment_code} failed: #{e.class} - #{e.message}")
        raise
      end

      private

      def fetch_payload(segment_code)
        uri = URI.parse("#{BASE_URL}/#{segment_code}")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = 15
        http.read_timeout = TIMEOUT_SECONDS

        request = Net::HTTP::Get.new(uri.request_uri)
        token = access_token
        client_id = ENV['DHAN_CLIENT_ID'].presence || ENV['CLIENT_ID'].presence
        request['access-token'] = token if token.present?
        request['client-id'] = client_id if client_id.present?
        request['Accept'] = 'application/json'

        response = http.request(request)
        unless response.is_a?(Net::HTTPSuccess)
          raise "HTTP #{response.code} fetching segmentwise instruments for #{segment_code}: #{response.body.to_s[0, 200]}"
        end

        parsed = JSON.parse(response.body)
        raise "Unexpected segmentwise payload (#{parsed.class}) for #{segment_code}" unless parsed.is_a?(Array)

        parsed
      end

      # Resolves a Dhan access token: TokenManager first, gem config second,
      # static ENV last.
      def access_token
        Dhan::TokenManager.current_token
      rescue StandardError
        begin
          DhanHQ.configuration&.access_token
        rescue StandardError
          ENV['DHAN_ACCESS_TOKEN'].presence || ENV['ACCESS_TOKEN'].presence
        end
      end

      def build_row(raw, mapping)
        exchange, segment = mapping
        attrs = FIELD_ALIASES.each_with_object({}) do |(attribute, aliases), out|
          out[attribute] = aliases.filter_map { |key| raw[key] }.first
        end

        return nil if attrs[:security_id].blank?

        now = Time.zone.now
        {
          exchange: exchange,
          segment: segment,
          security_id: attrs[:security_id].to_s,
          isin: attrs[:isin],
          instrument_code: attrs[:instrument_code],
          underlying_security_id: attrs[:underlying_security_id].to_s.presence,
          underlying_symbol: attrs[:underlying_symbol],
          symbol_name: attrs[:symbol_name],
          display_name: attrs[:display_name],
          instrument_type: attrs[:instrument_type],
          series: attrs[:series],
          lot_size: attrs[:lot_size].to_i.presence,
          expiry_date: parse_date(attrs[:expiry_date]),
          strike_price: attrs[:strike_price].present? ? attrs[:strike_price].to_f : nil,
          option_type: attrs[:option_type].presence&.upcase,
          tick_size: attrs[:tick_size].present? ? attrs[:tick_size].to_f : nil,
          expiry_flag: attrs[:expiry_flag],
          created_at: now,
          updated_at: now
        }
      end

      def parse_date(raw)
        return nil if raw.blank?

        Date.parse(raw.to_s)
      rescue ArgumentError, TypeError
        nil
      end

      def refreshed_columns
        InstrumentsImporter::REFRESHED_COLUMNS
      end
    end
  end
end
