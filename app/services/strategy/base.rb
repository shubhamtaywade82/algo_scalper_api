# frozen_string_literal: true

module Strategy
  class Base
    def call(context:, market:, indicators:)
      raise NotImplementedError, "Strategy must implement call(context:, market:, indicators:)"
    end
  end
end
