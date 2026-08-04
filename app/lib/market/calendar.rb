# frozen_string_literal: true

module Market
  # Trading-day calendar: weekends + holidays from `market_holidays` (NSE/BSE) merged with
  # optional extras in config/market_holidays.yml.
  #
  # Official lists (verify yearly):
  #   https://www.nseindia.com/resources/exchange-communication-holidays
  #   https://www.bseindia.com/static/markets/marketinfo/listholi.aspx
  class Calendar
    CONFIG_BASENAME = 'market_holidays.yml'

    class << self
      # Clears memoized holiday list (tests, console after editing YAML or DB rows).
      def clear_holiday_cache!
        @holiday_date_strings = nil
      end

      # Returns today if it's a trading day, otherwise the last trading day
      def today_or_last_trading_day
        today = Date.current
        return today if trading_day?(today)

        # Go back day by day until we find a trading day
        (1..7).each do |days_back|
          candidate = today - days_back.days
          return candidate if trading_day?(candidate)
        end

        # Fallback (shouldn't happen in normal circumstances)
        today - 1.day
      end

      # Returns the nearest trading day on or before the given date.
      def on_or_before_trading_day(date)
        candidate = date.is_a?(Date) ? date : Date.parse(date.to_s)
        return candidate if trading_day?(candidate)

        (1..7).each do |days_back|
          earlier = candidate - days_back.days
          return earlier if trading_day?(earlier)
        end

        candidate - 1.day
      end

      # Returns the date that was count trading days before an anchor date.
      def trading_days_before(anchor_date, count)
        anchor = on_or_before_trading_day(anchor_date)
        trading_days_counted = 0

        (1..(count * 2)).each do |days_back|
          candidate = anchor - days_back.days
          next unless trading_day?(candidate)

          trading_days_counted += 1
          return candidate if trading_days_counted == count
        end

        anchor - count.days
      end

      # Returns the date that was count trading days ago
      def trading_days_ago(count)
        current = Date.current
        trading_days_counted = 0
        days_back = 0

        # Use while loop instead of fixed range - handles weekends + holiday clusters
        # Max 10 trading days worth of calendar days (14 days) as safety
        max_days_back = count * 7
        while days_back < max_days_back
          days_back += 1
          candidate = current - days_back.days
          if trading_day?(candidate)
            trading_days_counted += 1
            return candidate if trading_days_counted == count
          end
        end

        # Fallback
        current - count.days
      end

      # Returns the next trading day
      def next_trading_day
        today = Date.current
        (1..7).each do |days_forward|
          candidate = today + days_forward.days
          return candidate if trading_day?(candidate)
        end

        # Fallback
        today + 1.day
      end

      # Checks if a given date is a trading day (Mon–Fri, not a merged DB/YAML holiday date).
      def trading_day?(date)
        return false if date.saturday? || date.sunday?
        return false if holiday_date_strings.include?(date.strftime('%Y-%m-%d'))

        true
      end

      # Returns true if today is a trading day
      def trading_day_today?
        trading_day?(Date.current)
      end

      # Returns the number of trading days between two dates
      def trading_days_between(start_date, end_date)
        return 0 if start_date >= end_date

        count = 0
        current = start_date + 1.day

        while current <= end_date
          count += 1 if trading_day?(current)
          current += 1.day
        end

        count
      end

      private

      def holiday_date_strings
        @holiday_date_strings ||= load_holiday_date_strings
      end

      def load_holiday_date_strings
        (load_holiday_dates_from_database + load_yaml_holiday_strings).uniq.freeze
      end

      def load_holiday_dates_from_database
        return [] unless ApplicationRecord.connection.data_source_exists?('market_holidays')

        MarketHoliday.closure_date_strings
      rescue StandardError => e
        Rails.logger.warn("[Market::Calendar] market_holidays read failed: #{e.class} - #{e.message}")
        []
      end

      def load_yaml_holiday_strings
        path = Rails.root.join('config', CONFIG_BASENAME)
        return [] unless File.file?(path)

        raw = YAML.safe_load_file(
          path,
          permitted_classes: [],
          permitted_symbols: [],
          aliases: true
        )
        list = Array(raw&.dig('nse', 'holidays') || raw&.dig('holidays'))
        list.map { |x| x.to_s.strip }.compact_blank.uniq
      rescue StandardError => e
        Rails.logger.warn("[Market::Calendar] #{CONFIG_BASENAME} load failed: #{e.class} - #{e.message}")
        []
      end
    end
  end
end
