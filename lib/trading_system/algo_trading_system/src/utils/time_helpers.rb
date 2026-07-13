# frozen_string_literal: true

module Utils
  # Utilities for time manipulation and market hours
  module TimeHelpers
    class << self
      def current_ist(time_source = Time)
        time_source.now.getlocal('+05:30')
      end

      def market_open?(time = current_ist)
        start_time = build_time(time, 9, 15)
        end_time = build_time(time, 15, 30)

        time >= start_time && time <= end_time
      end

      def exit_window?(time = current_ist)
        start_time = build_time(time, 15, 20)
        end_time = build_time(time, 15, 30)

        time >= start_time && time <= end_time
      end

      private

      def build_time(base_time, hour, min, time_class = Time)
        time_class.new(base_time.year, base_time.month, base_time.day, hour, min, 0, '+05:30')
      end
    end
  end
end
