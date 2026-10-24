# frozen_string_literal: true

module Entries
  module Guards
    class CooldownGuard
      class << self
        def call(context)
          symbol = context[:pick][:symbol]
          cooldown = context[:index_cfg][:cooldown_sec].to_i
          return EntryGuardPipeline::PASS unless EntryGuard.cooldown_active?(symbol, cooldown)

          { blocked: "cooldown active for #{context[:index_cfg][:key]}: #{symbol}" }
        end
      end
    end
  end
end
