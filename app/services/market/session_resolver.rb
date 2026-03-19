# frozen_string_literal: true

module Market
  # Resolves current trading session in IST (Kill Zones: Opening 09:15–10:30, Gamma 14:00–15:15).
  class SessionResolver
    OPENING_START = 9 * 60 + 15   # 09:15
    OPENING_END   = 10 * 60 + 30  # 10:30
    GAMMA_START   = 14 * 60 + 0   # 14:00
    GAMMA_END     = 15 * 60 + 15  # 15:15

    class << self
      # @return [Symbol] :opening, :gamma, or :midday
      def current
        minutes_since_midnight = current_ist_minutes

        return :opening if minutes_since_midnight >= OPENING_START && minutes_since_midnight < OPENING_END
        return :gamma if minutes_since_midnight >= GAMMA_START && minutes_since_midnight < GAMMA_END

        :midday
      end

      private

      def current_ist_minutes
        time = Time.current.in_time_zone("Asia/Kolkata")
        time.hour * 60 + time.min
      end
    end
  end
end
