# frozen_string_literal: true

module Ai
  module DynamicConfig
    # Parses and validates the raw Ollama JSON response for DynamicConfigAgent.
    #
    # Mirrors Ai::Calibration::ResultParser: whitelist known parameter names,
    # enforce per-parameter numeric bounds, filter by confidence. This is the
    # only gate between an Ollama response and a live AlgoConfig write —
    # unknown/out-of-bounds/low-confidence suggestions are silently dropped,
    # never raised past this class.
    class ResultParser
      MIN_CONFIDENCE = 0.70
      KNOWN_INDEX_KEYS = %w[NIFTY BANKNIFTY SENSEX].freeze

      # parameter name => { path: algo.yml key path (relative to index or top-level),
      #                      per_index: bool, min:, max: }
      KNOWN_PARAMS = {
        'capital_alloc_pct' => { path: %i[capital_alloc_pct], per_index: true, min: 0.05, max: 0.35 },
        'base_risk_pct' => { path: %i[risk_model base_risk_pct], per_index: true, min: 0.005, max: 0.03 },
        'strong_trend_risk_pct' => { path: %i[risk_model strong_trend_pct], per_index: true, min: 0.005, max: 0.03 },
        'weak_trend_risk_pct' => { path: %i[risk_model weak_trend_pct], per_index: true, min: 0.002, max: 0.02 },
        'primary_adx_min' => { path: %i[adx_thresholds primary_min_strength], per_index: true, min: 10.0, max: 35.0 },
        'confirmation_adx_min' => { path: %i[adx_thresholds confirmation_min_strength], per_index: true,
                                    min: 10.0, max: 35.0 },
        'premium_band_min' => { path: %i[premium_band min], per_index: true, min: 10, max: 500 },
        'premium_band_max' => { path: %i[premium_band max], per_index: true, min: 50, max: 1000 },
        'cooldown_sec' => { path: %i[cooldown_sec], per_index: true, min: 60, max: 900 },
        'max_trades_per_day' => { path: %i[trade_limits max_trades_per_day], per_index: true, min: 1, max: 20 },
        'sl_pct' => { path: %i[risk sl_pct], per_index: false, min: 0.05, max: 0.40 },
        'tp_pct' => { path: %i[risk tp_pct], per_index: false, min: 0.10, max: 0.80 }
      }.freeze

      class ParseError < StandardError; end
      class SchemaError < StandardError; end

      def self.call(raw_response)
        new(raw_response).call
      end

      def initialize(raw_response)
        @raw = raw_response
      end

      def call
        parsed = parse_json!
        validate_schema!(parsed)

        accepted = filter_and_validate(parsed['parameter_changes'] || [])

        {
          market_assessment: parsed['market_assessment'],
          parameter_changes: accepted,
          proposed_patch: build_proposed_patch(accepted),
          raw_response: @raw
        }
      end

      private

      def parse_json!
        return @raw if @raw.is_a?(Hash)

        JSON.parse(@raw.to_s)
      rescue JSON::ParserError => e
        raise ParseError, "Invalid JSON from Ollama: #{e.message}"
      end

      def validate_schema!(parsed)
        missing = %w[market_assessment parameter_changes].reject { |k| parsed.key?(k) }
        raise SchemaError, "Missing required keys: #{missing.join(', ')}" if missing.any?
      end

      def filter_and_validate(suggestions)
        suggestions.select { |s| valid_suggestion?(s) }
      end

      def valid_suggestion?(suggestion)
        spec = KNOWN_PARAMS[suggestion['parameter']]
        return false unless spec
        return false if suggestion['confidence'].to_f < MIN_CONFIDENCE
        return false if spec[:per_index] && KNOWN_INDEX_KEYS.exclude?(suggestion['index_key'].to_s.upcase)

        in_bounds?(spec, suggestion['suggested'])
      end

      def in_bounds?(spec, value)
        num = Float(value)
        num.between?(spec[:min], spec[:max])
      rescue ArgumentError, TypeError
        false
      end

      # Converts accepted suggestions into a deep-mergeable hash compatible with
      # AlgoConfig::DocumentStore.apply_deep_merge_patch! (array elements matched by :key).
      def build_proposed_patch(suggestions)
        patch = {}
        by_index = Hash.new { |h, k| h[k] = {} }

        suggestions.each do |s|
          spec = KNOWN_PARAMS[s['parameter']]
          if spec[:per_index]
            set_nested(by_index[s['index_key'].to_s.upcase], spec[:path], s['suggested'])
          else
            set_nested(patch, spec[:path], s['suggested'])
          end
        end

        patch['indices'] = by_index.map { |key, fields| { 'key' => key }.merge(fields) } if by_index.any?
        patch
      end

      def set_nested(hash, path, value)
        *parents, last = path
        node = hash
        parents.each do |k|
          node[k.to_s] ||= {}
          node = node[k.to_s]
        end
        node[last.to_s] = value
      end
    end
  end
end
