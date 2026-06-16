# frozen_string_literal: true

module Positions
  # Resolves the config a position's exit/trailing math should use. Prefers the snapshot
  # pinned on the tracker at entry so a mid-position config change can never move an open
  # stop; falls back to live config for positions opened before snapshots existed.
  class ExitConfigResolver
    def self.for(tracker)
      snapshot = tracker&.meta&.dig('config_snapshot') || tracker&.meta&.dig(:config_snapshot)
      return AlgoConfig.fetch if snapshot.blank?

      snapshot.deep_symbolize_keys
    end
  end
end
