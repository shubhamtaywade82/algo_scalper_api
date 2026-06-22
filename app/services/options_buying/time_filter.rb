# frozen_string_literal: true

module OptionsBuying
  # Time-of-day gate for Options Buying
  class TimeFilter
    def self.allowed?(index_key:)
      new(index_key: index_key).allowed?
    end

    def initialize(index_key:)
      @index_key = index_key
    end

    def allowed?
      current_time = Time.current.strftime('%H:%M')

      return false if current_time < entry_start
      return false if current_time > entry_end

      # Check expiry day lockout
      if CarryPolicy.expiry_day?(index_key: @index_key) && current_time > expiry_lockout
        return false
      end

      true
    end

    private

    def config
      Mode.config[:time_filter] || {}
    end

    def entry_start
      config[:entry_start] || '09:20'
    end

    def entry_end
      config[:entry_end] || '14:30'
    end

    def expiry_lockout
      Mode.config.dig(:expiry_day, :lockout_after) || '13:00'
    end
  end
end
