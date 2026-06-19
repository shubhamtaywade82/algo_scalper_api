# frozen_string_literal: true

module Options
  class ExpiryCalendar
    EXPIRY_WEEKDAY = {
      'NIFTY' => 4,
      'SENSEX' => 5
    }.freeze

    def self.windows(symbol:, weeks:)
      wday = EXPIRY_WEEKDAY[symbol.to_s.upcase]
      unless wday
        raise ArgumentError,
              "unknown symbol: #{symbol} (known: #{EXPIRY_WEEKDAY.keys.join(', ')})"
      end

      today = Time.zone.today
      days_since = (today.wday - wday) % 7
      current_expiry = today - days_since.days

      Array.new(weeks) do |i|
        expiry = current_expiry - (i * 7).days
        { expiry: expiry, from: expiry - 6.days, to: expiry }
      end.reverse
    end
  end
end
