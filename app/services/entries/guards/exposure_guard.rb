# frozen_string_literal: true

module Entries
  module Guards
    class ExposureGuard
      class << self
        def call(context)
          index_cfg = context[:index_cfg]
          instrument = context[:instrument]
          direction = context[:direction]
          side = direction == :bullish ? 'long_ce' : 'long_pe'
          is_supertrend = context[:entry_metadata]&.dig(:entry_contract).to_s == EntryGuard::SUPERTREND_CONTRACT

          context[:side] = side
          context[:is_supertrend] = is_supertrend

          if is_supertrend
            return { blocked: "Supertrend: active position already exists for #{index_cfg[:key]}" } if active_supertrend_position?(index_cfg[:key])

            return EntryGuardPipeline::PASS
          end

          return EntryGuardPipeline::PASS if EntryGuard.exposure_ok?(
            instrument: instrument,
            side: side,
            max_same_side: index_cfg[:max_same_side]
          )

          { blocked: "exposure limit for #{index_cfg[:key]} (#{side})" }
        end

        private

        def active_supertrend_position?(index_key)
          PositionTracker.active.where("(meta->>'index_key') = ?", index_key.to_s).exists?
        end
      end
    end
  end
end
