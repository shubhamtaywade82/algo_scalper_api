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

      private

      def format_minute(min)
        min.to_s.rjust(2, '0')
      end
    end
  end
end

