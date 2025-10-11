# frozen_string_literal: true

module Market
  class Calendar
    # Indian market holidays for 2024-2025 (simplified list)
    # In production, this should be loaded from a more comprehensive source
    MARKET_HOLIDAYS = [
      # 2024
      "2024-01-26", # Republic Day
      "2024-03-08", # Holi
      "2024-03-29", # Good Friday
      "2024-04-11", # Eid ul Fitr
      "2024-04-17", # Ram Navami
      "2024-05-01", # Maharashtra Day
      "2024-06-17", # Eid ul Adha
      "2024-08-15", # Independence Day
      "2024-08-26", # Janmashtami
      "2024-10-02", # Gandhi Jayanti
      "2024-10-12", # Dussehra
      "2024-10-31", # Diwali
      "2024-11-01", # Diwali
      "2024-11-15", # Guru Nanak Jayanti
      "2024-12-25", # Christmas

      # 2025
      "2025-01-26", # Republic Day
      "2025-03-14", # Holi
      "2025-04-18", # Good Friday
      "2025-04-21", # Eid ul Fitr
      "2025-05-01", # Maharashtra Day
      "2025-06-06", # Eid ul Adha
      "2025-08-15", # Independence Day
      "2025-08-15", # Independence Day
      "2025-10-02", # Gandhi Jayanti
      "2025-10-20", # Dussehra
      "2025-11-01", # Diwali
      "2025-11-02", # Diwali
      "2025-12-25" # Christmas
    ].freeze

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
        return false if MARKET_HOLIDAYS.include?(date.strftime("%Y-%m-%d"))

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
