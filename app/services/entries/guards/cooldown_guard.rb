# frozen_string_literal: true

module Entries
  module Guards
    class CooldownGuard
      class << self
        def call(context)
          index_key = context[:index_cfg][:key]
          cooldown = context[:index_cfg][:cooldown_sec].to_i
          return EntryGuardPipeline::PASS unless EntryGuard.cooldown_active_for_index?(index_key, cooldown)

          { blocked: "cooldown active for index #{index_key}" }
        end
      end
    end
  end
end
