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
    #
    # When `stressed` (circuit breaker tripped or a recent losing streak),
    # also enforces the "only move risk knobs the safe direction" rule in
    # code — not just as a prompt instruction the model could ignore — and
    # checks the move against the AUTHORITATIVE current config value
    # (`current_config`, from ContextBuilder), never the LLM's self-reported
    # "current", which could be wrong or crafted to dodge the check.
    class ResultParser
      MIN_CONFIDENCE = 0.70

      # parameter name => { path: algo.yml key path (relative to index or top-level) for the patch,
      #                      current_path: key path within ContextBuilder's current_config slice,
      #                      per_index: bool, min:, max:,
      #                      safer_direction: :down/:up/nil — the direction that REDUCES risk,
      #                        enforced only while stressed; nil means this knob isn't a risk
      #                        lever in the loss-streak sense (e.g. tp_pct) and is never blocked }
      KNOWN_PARAMS = {
        'capital_alloc_pct' => { path: %i[capital_alloc_pct], current_path: %i[capital_alloc_pct],
                                 per_index: true, min: 0.05, max: 0.35, safer_direction: :down },
        'base_risk_pct' => { path: %i[risk_model base_risk_pct], current_path: %i[risk_model base_risk_pct],
                             per_index: true, min: 0.005, max: 0.03, safer_direction: :down },
        'strong_trend_risk_pct' => { path: %i[risk_model strong_trend_pct],
                                     current_path: %i[risk_model strong_trend_pct],
                                     per_index: true, min: 0.005, max: 0.03, safer_direction: :down },
        'weak_trend_risk_pct' => { path: %i[risk_model weak_trend_pct],
                                   current_path: %i[risk_model weak_trend_pct],
                                   per_index: true, min: 0.002, max: 0.02, safer_direction: :down },
        'primary_adx_min' => { path: %i[adx_thresholds primary_min_strength],
                               current_path: %i[adx_thresholds primary_min_strength],
                               per_index: true, min: 10.0, max: 35.0, safer_direction: :up },
        'confirmation_adx_min' => { path: %i[adx_thresholds confirmation_min_strength],
                                    current_path: %i[adx_thresholds confirmation_min_strength],
                                    per_index: true, min: 10.0, max: 35.0, safer_direction: :up },
        'premium_band_min' => { path: %i[premium_band min], current_path: %i[premium_band min],
                                per_index: true, min: 10, max: 500, safer_direction: :up },
        'premium_band_max' => { path: %i[premium_band max], current_path: %i[premium_band max],
                                per_index: true, min: 50, max: 1000, safer_direction: :down },
        'cooldown_sec' => { path: %i[cooldown_sec], current_path: %i[cooldown_sec],
                            per_index: true, min: 60, max: 900, safer_direction: :up },
        'max_trades_per_day' => { path: %i[trade_limits max_trades_per_day], current_path: %i[max_trades_per_day],
                                  per_index: true, min: 1, max: 20, safer_direction: :down },
        'sl_pct' => { path: %i[risk sl_pct], current_path: %i[sl_pct],
                      per_index: false, min: 0.05, max: 0.40, safer_direction: :down },
        'tp_pct' => { path: %i[risk tp_pct], current_path: %i[tp_pct],
                      per_index: false, min: 0.10, max: 0.80, safer_direction: nil }
      }.freeze

      class ParseError < StandardError; end
      class SchemaError < StandardError; end

      def self.call(raw_response, index_key:, current_config: {}, stressed: false)
        new(raw_response, index_key: index_key, current_config: current_config, stressed: stressed).call
      end

      def initialize(raw_response, index_key:, current_config: {}, stressed: false)
        @raw = raw_response
        @index_key = index_key.to_s.upcase
        @current_config = current_config || {}
        @stressed = stressed
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
        return false unless index_scope_ok?(spec, suggestion)
        return false unless in_bounds?(spec, suggestion['suggested'])
        return false if @stressed && unsafe_direction?(spec, suggestion['suggested'])

        true
      end

      # A per-index suggestion must target THIS agent run's own index — not an unknown index,
      # and not a different known index either (closes an unenforced escape hatch: nothing else
      # stops a suggestion from naming a different index_key than the one actually analyzed).
      def index_scope_ok?(spec, suggestion)
        return true unless spec[:per_index]

        suggestion['index_key'].to_s.upcase == @index_key
      end

      def in_bounds?(spec, value)
        num = Float(value)
        num.between?(spec[:min], spec[:max])
      rescue ArgumentError, TypeError
        false
      end

      # Blocks a move toward more risk (per spec[:safer_direction]) while stressed, checked
      # against the AUTHORITATIVE live value — never the LLM's self-reported "current". If the
      # authoritative current can't be resolved, fail closed (block) rather than trust the model.
      def unsafe_direction?(spec, suggested_value)
        return false unless spec[:safer_direction]

        current = @current_config.dig(*spec[:current_path])
        return true if current.nil?

        suggested = Float(suggested_value)
        current = Float(current)

        case spec[:safer_direction]
        when :down then suggested > current
        when :up then suggested < current
        end
      rescue ArgumentError, TypeError
        true
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
