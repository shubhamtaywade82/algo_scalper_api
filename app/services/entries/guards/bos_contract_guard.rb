# frozen_string_literal: true

module Entries
  module Guards
    class BosContractGuard
      class << self
        def call(context)
          entry_metadata = context[:entry_metadata]
          return EntryGuardPipeline::PASS if EntryGuard.bos_contract_present?(entry_metadata)

          { blocked: "BOS contract missing. Metadata: #{entry_metadata.inspect}" }
        end
      end
    end
  end
end
