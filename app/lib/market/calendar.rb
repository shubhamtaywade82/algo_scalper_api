# frozen_string_literal: true

module Market
  class Calendar
    # Indian market holidays for 2024-2025 (simplified list)
    # In production, this should be loaded from a more comprehensive source
    MARKET_HOLIDAYS = [].freeze

    class << self
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

      # Returns the date that was n trading days ago
      def trading_days_ago(n)
        current = Date.current
        trading_days_counted = 0

        # Start from yesterday to avoid counting today if it's not a trading day
        (1..30).each do |days_back|
          candidate = current - days_back.days
          if trading_day?(candidate)
            trading_days_counted += 1
            return candidate if trading_days_counted == n
          end
        end

        # Fallback
        current - n.days
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

      # Checks if a given date is a trading day
      def trading_day?(date)
        return false if date.saturday? || date.sunday?
        return false if MARKET_HOLIDAYS.include?(date.strftime('%Y-%m-%d'))

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
    end
  end
end
