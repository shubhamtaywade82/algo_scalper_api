# frozen_string_literal: true

module Options
  # Generates weekly expiry windows from actual expiry dates.
  # No weekday hardcoding or assumptions — dates come from the caller (DhanHQ data).
  # Weekday convention for window start: Date#wday (Sunday=0, Monday=1, ...)
  class ExpiryCalendar
    # @param expiry_dates [Array<Date, String, Time>] actual expiry dates from DhanHQ
    # @return [Array<Hash>] [{expiry: Date, from: Date, to: Date}, ...] oldest first
    def self.windows(expiry_dates:)
      raise ArgumentError, 'expiry_dates must be an array' unless expiry_dates.respond_to?(:each)

      expiry_dates.compact.filter_map { |raw| coerce_date(raw) }.uniq.sort.map do |expiry|
        monday = expiry - (expiry.wday - 1).days
        { expiry: expiry, from: monday, to: expiry }
      end
    end

    private_class_method def self.coerce_date(raw)
      case raw
      when Date then raw
      when Time, DateTime, ActiveSupport::TimeWithZone then raw.to_date
      when String
        begin
          Date.parse(raw)
        rescue ArgumentError
          nil
        end
      end
    end
  end
end
