# frozen_string_literal: true

module Entries
  # Handles direct execution of orders when not delegating to the agent engine.
  class DirectOrderPlacer
    def self.execute(context)
      :unhandled
    end
  end
end
