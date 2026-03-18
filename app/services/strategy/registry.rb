module Strategy
  class Registry
    def self.resolve(context)
      case [context.day_type, context.session, context.regime]
      when [:normal, :trend, :trend_bull]
        Strategy::NiftyImpV1
      when [:normal, :trend, :trend_bear]
        Strategy::NiftyImpV1
      when [:expiry, :gamma, :trend_bull]
        Strategy::ExpiryBreakout
      when [:expiry, :gamma, :trend_bear]
        Strategy::ExpiryBreakout
      else
        nil
      end
    end
  end
end
