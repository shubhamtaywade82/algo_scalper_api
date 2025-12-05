# frozen_string_literal: true

module TradingSession
  # TradingSession provides session timing checks for entry and exit
  # Entry allowed: 9:20 AM to 3:15 PM IST
  # Exits must happen before 3:15 PM IST
  class Service
    ENTRY_START_HOUR = 9
    ENTRY_START_MINUTE = 20
    EXIT_DEADLINE_HOUR = 15
    EXIT_DEADLINE_MINUTE = 15
    MARKET_CLOSE_HOUR = 15
    MARKET_CLOSE_MINUTE = 30

    IST_TIMEZONE = 'Asia/Kolkata'

    class << self
      # Check if entry is allowed at current time
      # @return [Hash] { allowed: Boolean, reason: String }
      def entry_allowed?
        current_ist = current_ist_time
        hour = current_ist.hour
        minute = current_ist.min

        # Entry allowed: 9:20 AM to 3:15 PM IST
        if hour < ENTRY_START_HOUR || (hour == ENTRY_START_HOUR && minute < ENTRY_START_MINUTE)
          {
            allowed: false,
            reason: "Entry not allowed before #{ENTRY_START_HOUR}:#{format_minute(ENTRY_START_MINUTE)} IST"
          }
        elsif hour > EXIT_DEADLINE_HOUR || (hour == EXIT_DEADLINE_HOUR && minute >= EXIT_DEADLINE_MINUTE)
          {
            allowed: false,
            reason: "Entry not allowed after #{EXIT_DEADLINE_HOUR}:#{format_minute(EXIT_DEADLINE_MINUTE)} IST"
          }
        elsif trading_time_restrictions_enabled? && restricted_time_period?(current_ist)
          restricted_period = find_restricted_period(current_ist)
          {
            allowed: false,
            reason: "Entry blocked: Trading restricted during #{restricted_period} (non-profitable period)"
          }
        else
          {
            allowed: true,
            reason: "Entry allowed (current time: #{current_ist.strftime('%H:%M %Z')})"
          }
        end
      end

      # Check if exit should be forced (before 3:15 PM IST)
      # @return [Hash] { should_exit: Boolean, reason: String, time_remaining: Integer (seconds) }
      def should_force_exit?
        current_ist = current_ist_time
        hour = current_ist.hour
        minute = current_ist.min

        # Force exit if at or after 3:15 PM IST
        if hour > EXIT_DEADLINE_HOUR || (hour == EXIT_DEADLINE_HOUR && minute >= EXIT_DEADLINE_MINUTE)
          deadline = current_ist.change(hour: EXIT_DEADLINE_HOUR, min: EXIT_DEADLINE_MINUTE)
          {
            should_exit: true,
            reason: "Session end deadline reached (#{EXIT_DEADLINE_HOUR}:#{format_minute(EXIT_DEADLINE_MINUTE)} IST)",
            time_remaining: 0
          }
        else
          # Calculate time remaining until deadline
          deadline = current_ist.change(hour: EXIT_DEADLINE_HOUR, min: EXIT_DEADLINE_MINUTE)
          time_remaining = deadline.to_i - current_ist.to_i

          {
            should_exit: false,
            reason: "Session active (deadline: #{EXIT_DEADLINE_HOUR}:#{format_minute(EXIT_DEADLINE_MINUTE)} IST)",
            time_remaining: [time_remaining, 0].max
          }
        end
      end

      # Get current time in IST
      # @return [ActiveSupport::TimeWithZone]
      def current_ist_time
        Time.zone.now.in_time_zone(IST_TIMEZONE)
      end

      # Check if we're in trading session (for general checks)
      # @return [Boolean]
      def in_session?
        entry_allowed?[:allowed]
      end

      # Get time until session end
      # @return [Integer] seconds until 3:15 PM IST
      def seconds_until_session_end
        current_ist = current_ist_time
        deadline = current_ist.change(hour: EXIT_DEADLINE_HOUR, min: EXIT_DEADLINE_MINUTE)
        [deadline.to_i - current_ist.to_i, 0].max
      end

      # Check if market is closed (after 3:30 PM IST)
      # Used to skip signal generation and entry attempts
      # @return [Boolean]
      def market_closed?
        current_ist = current_ist_time
        hour = current_ist.hour
        minute = current_ist.min

        hour > MARKET_CLOSE_HOUR || (hour == MARKET_CLOSE_HOUR && minute >= MARKET_CLOSE_MINUTE)
      end

      # Check if market is open (before 3:30 PM IST)
      # @return [Boolean]
      def market_open?
        !market_closed?
      end

      # Check if current time falls within a restricted trading period
      # @param time [Time] Current time in IST
      # @return [Boolean]
      def restricted_time_period?(time)
        restrictions = load_trading_time_restrictions
        return false if restrictions.blank?

        current_minutes = (time.hour * 60) + time.min

        restrictions.any? do |period|
          start_time, end_time = parse_time_period(period)
          next false unless start_time && end_time

          start_hour = start_time[:hour]
          start_min = start_time[:minute]
          end_hour = end_time[:hour]
          end_min = end_time[:minute]
          start_minutes = (start_hour * 60) + start_min
          end_minutes = (end_hour * 60) + end_min

          # Handle period that spans midnight (e.g., 23:00-01:00)
          if start_minutes > end_minutes
            (current_minutes >= start_minutes) || (current_minutes <= end_minutes)
          else
            (current_minutes >= start_minutes) && (current_minutes <= end_minutes)
          end
        end
      end

      # Find which restricted period the current time falls into
      # @param time [Time] Current time in IST
      # @return [String] Period description
      def find_restricted_period(time)
        restrictions = load_trading_time_restrictions
        return 'unknown period' if restrictions.blank?

        current_minutes = (time.hour * 60) + time.min

        restrictions.each do |period|
          start_time, end_time = parse_time_period(period)
          next unless start_time && end_time

          start_hour = start_time[:hour]
          start_min = start_time[:minute]
          end_hour = end_time[:hour]
          end_min = end_time[:minute]
          start_minutes = (start_hour * 60) + start_min
          end_minutes = (end_hour * 60) + end_min

          # Handle period that spans midnight
          if start_minutes > end_minutes
            return period if (current_minutes >= start_minutes) || (current_minutes <= end_minutes)
          else
            return period if (current_minutes >= start_minutes) && (current_minutes <= end_minutes)
          end
        end

        'unknown period'
      end

      # Check if trading time restrictions are enabled
      # @return [Boolean]
      def trading_time_restrictions_enabled?
        config = AlgoConfig.fetch
        config.dig(:trading_time_restrictions, :enabled) == true
      rescue StandardError => e
        Rails.logger.error("[TradingSession] Failed to check trading time restrictions enabled: #{e.class} - #{e.message}")
        false
      end

      # Load trading time restrictions from config
      # @return [Array<String>] Array of time period strings (e.g., ["10:30-11:30", "14:00-15:00"])
      def load_trading_time_restrictions
        config = AlgoConfig.fetch
        restrictions = config.dig(:trading_time_restrictions, :avoid_periods) || []
        
        # Support both array of strings and single string
        restrictions = [restrictions] unless restrictions.is_a?(Array)
        restrictions.compact
      rescue StandardError => e
        Rails.logger.error("[TradingSession] Failed to load trading time restrictions: #{e.class} - #{e.message}")
        []
      end

      # Parse a time period string (e.g., "10:30-11:30")
      # @param period [String] Time period string in format "HH:MM-HH:MM"
      # @return [Array<Hash, Hash>] [start_time, end_time] or [nil, nil] if invalid
      def parse_time_period(period)
        return [nil, nil] unless period.is_a?(String)

        parts = period.split('-')
        return [nil, nil] unless parts.length == 2

        start_str = parts[0].strip
        end_str = parts[1].strip

        start_time = parse_time_string(start_str)
        end_time = parse_time_string(end_str)

        [start_time, end_time] if start_time && end_time
      end

      # Parse a time string (e.g., "10:30")
      # @param time_str [String] Time string in format "HH:MM"
      # @return [Hash] { hour: Integer, minute: Integer } or nil if invalid
      def parse_time_string(time_str)
        return nil unless time_str.match?(/^\d{1,2}:\d{2}$/)

        parts = time_str.split(':')
        hour = parts[0].to_i
        minute = parts[1].to_i

        return nil unless hour.between?(0, 23) && minute.between?(0, 59)

        { hour: hour, minute: minute }
      rescue StandardError
        nil
      end

      private

      def format_minute(min)
        min.to_s.rjust(2, '0')
      end
    end
  end
end

