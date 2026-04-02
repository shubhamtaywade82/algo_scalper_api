# frozen_string_literal: true

module Entries
  module Guards
    class InstrumentLookupGuard
      class << self
        def call(context)
          instrument = IndexInstrumentCache.instance.get_or_fetch(context[:index_cfg])
          return { blocked: "instrument not found for #{context[:index_cfg][:key]}" } unless instrument

          context[:instrument] = instrument
          EntryGuardPipeline::PASS
        end
      end
    end
  end
end
