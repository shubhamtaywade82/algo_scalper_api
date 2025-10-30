# frozen_string_literal: true

module Paper
  module TradingClock
    TIMEZONE = 'Asia/Kolkata'

    def self.trading_date(now = Time.current)
      now.in_time_zone(TIMEZONE).to_date
    end

    def self.redis_ns(now = Time.current)
      "paper:#{trading_date(now)}"
    end
  end
end


