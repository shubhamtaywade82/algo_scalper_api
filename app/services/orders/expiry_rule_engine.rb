# frozen_string_literal: true

module Orders
  class ExpiryRuleEngine
    def initialize(symbol: nil)
      @symbol = symbol.to_s.upcase
    end

    def force_exit?
      return false unless expiry_day?

      now = Time.current.in_time_zone('Asia/Kolkata')
      # after 15:10 force exit
      now.hour == 15 && now.min >= 10 || now.hour > 15
    end

    def tighten_trailing?
      return false unless expiry_day?

      now = Time.current.in_time_zone('Asia/Kolkata')
      # after 14:45 tighten SL
      (now.hour == 14 && now.min >= 45) || (now.hour >= 15)
    end

    private

    def expiry_day?
      # In India, weekly options expire on different days depending on index:
      # NIFTY: Thursday
      # BANKNIFTY: Wednesday (mostly)
      # FINNIFTY: Tuesday
      # MIDCPNIFTY: Monday
      # SENSEX: Friday
      
      today = Time.current.in_time_zone('Asia/Kolkata').wday
      
      case
      when @symbol.include?('SENSEX') || @symbol.include?('BANKEX')
        today == 5 # Friday
      when @symbol.include?('NIFTY') && !@symbol.include?('BANK') && !@symbol.include?('FIN') && !@symbol.include?('MIDCP')
        today == 4 # Thursday
      when @symbol.include?('BANKNIFTY')
        today == 3 # Wednesday
      when @symbol.include?('FINNIFTY')
        today == 2 # Tuesday
      when @symbol.include?('MIDCPNIFTY')
        today == 1 # Monday
      else
        false
      end
    end
  end
end
