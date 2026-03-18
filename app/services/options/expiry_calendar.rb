# frozen_string_literal: true

module Options
  # Maps index symbols to expiry weekdays and generates weekly windows.
  # Weekday convention: Date#wday (Sunday=0, Monday=1, ..., Thursday=4, Friday=5)
  # NOT Date#cwday (which starts Monday=1).
  class ExpiryCalendar
    EXPIRY_WEEKDAY = {
      'NIFTY' => 4, # Thursday
      'SENSEX' => 5 # Friday
    }.freeze

    # @param symbol [String] 'NIFTY' or 'SENSEX'
    # @param weeks  [Integer] number of past expiry windows to return
    # @return [Array<Hash>] [{expiry: Date, from: Date, to: Date}, ...] oldest first
    def self.windows(symbol:, weeks:)
      wday = EXPIRY_WEEKDAY[symbol.to_s.upcase]
      raise ArgumentError, "unknown symbol: #{symbol} (known: #{EXPIRY_WEEKDAY.keys.join(', ')})" unless wday

      today = Time.zone.today
      # Find most recent past expiry (inclusive of today if today IS expiry day)
      days_since = (today.wday - wday) % 7
      current_expiry = today - days_since.days

      Array.new(weeks) do |i|
        expiry = current_expiry - (i * 7).days
        { expiry: expiry, from: expiry - (expiry.wday - 1).days, to: expiry }
      end.reverse
    end
  end
end
