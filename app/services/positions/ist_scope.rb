# frozen_string_literal: true

module Positions
  class IstScope
    class << self
      def today_start
        now_in_zone.beginning_of_day
      end

      def today_end
        now_in_zone.end_of_day
      end

      def today_range
        today_start..today_end
      end

      private

      def now_in_zone
        Time.current.in_time_zone('Asia/Kolkata')
      end
    end
  end
end
