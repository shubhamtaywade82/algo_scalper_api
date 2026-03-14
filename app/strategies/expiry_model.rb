# frozen_string_literal: true

module Strategies
  # Session-based logic for index options expiry days
  class ExpiryModel
    def self.session
      now = Time.current.in_time_zone('Asia/Kolkata')

      # Market hours: 9:15 AM to 3:30 PM
      if (now.hour == 9 && now.min >= 15) || (now.hour == 10 && now.min < 30)
        :morning # 9:15-10:30
      elsif (now.hour == 10 && now.min >= 30) || (now.hour >= 11 && now.hour < 13)
        :midday # 10:30-13:00
      elsif (now.hour == 13) || (now.hour == 14 && now.min < 30)
        :afternoon # 13:00-14:30
      elsif (now.hour == 14 && now.min >= 30) || (now.hour == 15 && now.min <= 30)
        :gamma_session # 14:30-15:30
      else
        :closed
      end
    end

    def self.trade_allowed?(symbol: nil)
      s = session
      return false if s == :closed

      # Institutional rule: On expiry days, avoid trading during midday decay period
      if expiry_day?(symbol) && (s == :midday)
        return false
      end

      true
    end

    def self.expiry_day?(symbol)
      return false if symbol.blank?

      sym = symbol.to_s.upcase
      today = Time.current.in_time_zone('Asia/Kolkata').wday

      # Indian Index Expiry Days:
      # MIDCPNIFTY: Monday (1)
      # FINNIFTY: Tuesday (2)
      # BANKNIFTY: Wednesday (3)
      # NIFTY: Thursday (4)
      # SENSEX/BANKEX: Friday (5)

      if sym.include?('SENSEX') || sym.include?('BANKEX')
        today == 5
      elsif sym.include?('NIFTY') && !sym.include?('BANK') && !sym.include?('FIN') && !sym.include?('MIDCP')
        today == 4
      elsif sym.include?('BANKNIFTY')
        today == 3
      elsif sym.include?('FINNIFTY')
        today == 2
      elsif sym.include?('MIDCPNIFTY')
        today == 1
      else
        false
      end
    end
  end
end
