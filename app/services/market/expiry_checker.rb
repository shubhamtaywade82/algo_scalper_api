# frozen_string_literal: true

module Market
  # Single source of truth for "is today an expiry day for this index?"
  #
  # Always consults the instrument's expiry_list first — this is the authoritative
  # source because DhanHQ's data already reflects holiday-adjusted expiry dates.
  # Falls back to weekday heuristics only when expiry_list is unavailable.
  #
  # Usage:
  #   Market::ExpiryChecker.expiry_today?('NIFTY')          # index key
  #   Market::ExpiryChecker.expiry_today?('BANKNIFTY24MAR52400PE')  # option symbol
  class ExpiryChecker
    # Weekday defaults — used ONLY as last-resort fallback when expiry_list is absent.
    # These are the NSE-scheduled days and may be wrong around public holidays.
    WEEKDAY_BY_INDEX = {
      'SENSEX' => 5, # Friday
      'BANKEX' => 5, # Friday
      'MIDCPNIFTY' => 1, # Monday
      'FINNIFTY' => 2, # Tuesday
      'BANKNIFTY' => 3, # Wednesday
      'NIFTY' => 4 # Thursday (checked last — must come after more specific NIFTY variants)
    }.freeze

    # Returns true if today is an expiry day for the given index.
    # @param symbol_or_key [String] index key ("NIFTY") or option contract symbol
    def self.expiry_today?(symbol_or_key)
      return false if symbol_or_key.blank?

      key   = resolve_index_key(symbol_or_key.to_s.upcase)
      today = Time.zone.today

      instrument  = fetch_instrument(key)
      expiry_list = instrument&.expiry_list&.compact

      if expiry_list.present?
        parsed = parse_dates(expiry_list)
        result = parsed.include?(today)
        Rails.logger.debug { "[ExpiryChecker] expiry_today? #{key} date=#{today} expiry_list_hit=#{result}" }
        return result
      end

      Rails.logger.warn("[ExpiryChecker] expiry_list unavailable for #{key}, using weekday heuristic")
      weekday_fallback(key, today)
    rescue StandardError => e
      Rails.logger.error("[ExpiryChecker] expiry_today? error for #{symbol_or_key}: #{e.message}")
      weekday_fallback(resolve_index_key(symbol_or_key.to_s.upcase), Time.zone.today)
    end

    # Resolves an index key from either a clean key ("NIFTY") or an option contract
    # symbol ("BANKNIFTY24MAR52400PE", "NIFTY-Mar2026-23000-CE", etc.).
    # Checks longer/more-specific keys first to avoid "NIFTY" matching "BANKNIFTY".
    def self.resolve_index_key(symbol)
      WEEKDAY_BY_INDEX.each_key do |key|
        return key if symbol == key || symbol.start_with?(key)
      end
      symbol # return as-is if no known index matched
    end

    # ---- private class methods ------------------------------------------------
    class << self
      private

      def fetch_instrument(index_key)
        indices   = AlgoConfig.fetch[:indices] || []
        index_cfg = indices.find { |i| i[:key].to_s.upcase == index_key }
        return nil unless index_cfg

        IndexInstrumentCache.instance.get_or_fetch(index_cfg)
      rescue StandardError
        nil
      end

      def parse_dates(expiry_list)
        expiry_list.filter_map do |raw|
          case raw
          when Date then raw
          when String then begin
                             Date.parse(raw)
          rescue StandardError
                             nil
          end
          when Time, DateTime, ActiveSupport::TimeWithZone then raw.to_date
          end
        end.to_set
      end

      def weekday_fallback(key, today)
        wday = today.wday
        WEEKDAY_BY_INDEX.each do |index, expected_wday|
          return wday == expected_wday if key == index || key.start_with?(index)
        end
        false
      end
    end
  end
end
