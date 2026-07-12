module BacktestEngine
  class InstrumentEngine
    DEFAULT_SEGMENT = "NSE_FNO"

    def lot_size_for(security_id, exchange_segment: DEFAULT_SEGMENT)
      require_dhanhq!

      instrument = DhanHQ::Models::Instrument.find(exchange_segment, security_id.to_s)
      return instrument.lot_size if instrument&.lot_size

      raise ArgumentError, "Lot size missing for security_id=#{security_id} in #{exchange_segment}"
    end

    private

    def require_dhanhq!
      require "dhanhq-client"
    rescue LoadError
      raise LoadError, "dhanhq-client gem is required to resolve lot sizes"
    end
  end
end

