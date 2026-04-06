# frozen_string_literal: true

module Smc
  module TickAi
    # Rising-edge detection on LTF rows of {Smc::Confluence::MtfDigest} alignment (Delta-style).
    class EdgeDetector
      FLAG_KEYS = %w[
        long_signal short_signal choch_bull choch_bear
        liq_sweep_bull liq_sweep_bear pdh_sweep pdl_sweep
      ].freeze

      Result = Struct.new(:bootstrap, :fired_keys, :current)

      class << self
        # @param digest [Hash] MtfDigest#to_h
        # @param ltf_interval [String] e.g. "5"
        # @param previous_snapshot [Hash] string keys => boolean-ish
        def evaluate(digest:, ltf_interval:, previous_snapshot:)
          current = extract_flags(digest, ltf_interval.to_s)

          if previous_snapshot.blank?
            return Result.new(bootstrap: true, fired_keys: [], current: current)
          end

          prev = normalize_previous(previous_snapshot)
          fired = FLAG_KEYS.select { |k| truthy?(current[k]) && !truthy?(prev[k]) }
          Result.new(bootstrap: false, fired_keys: fired, current: current)
        end

        def extract_flags(digest, ltf)
          return {} unless digest.is_a?(Hash)

          alignment = digest['alignment'] || digest[:alignment] || {}
          FLAG_KEYS.each_with_object({}) do |key, memo|
            row = alignment[key] || alignment[key.to_sym]
            memo[key] = row.is_a?(Hash) ? truthy?(row[ltf] || row[ltf.to_sym]) : false
          end
        end

        def truthy?(value)
          value == true || value.to_s == 'true'
        end

        def normalize_previous(snapshot)
          return {} unless snapshot.is_a?(Hash)

          FLAG_KEYS.index_with do |k|
            snapshot[k] || snapshot[k.to_sym]
          end
        end
      end
    end
  end
end
