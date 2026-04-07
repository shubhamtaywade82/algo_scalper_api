# frozen_string_literal: true

module Strategy
  class Registry
    def self.resolve(context)
      case [context.day_type, context.session, context.regime]
      when %i[normal trend trend_bull]
        Strategy::NiftyImpV1
      when %i[normal trend trend_bear]
        Strategy::NiftyImpV1
      when %i[expiry gamma trend_bull]
        Strategy::ExpiryBreakout
      when %i[expiry gamma trend_bear]
        Strategy::ExpiryBreakout
      end
    end
  end
end
