# frozen_string_literal: true

module Ai
  module Calibration
    # Parses and validates the raw Ollama JSON response.
    #
    # Responsibilities:
    # - Validates required keys from the schema
    # - Filters parameter suggestions by confidence threshold
    # - Enforces a whitelist of known config keys to prevent hallucinated params
    # - Enforces sane value bounds per parameter
    #
    # Returns a structured hash: { diagnosis:, parameter_changes:, entry_filters:,
    #                               exit_improvements:, regime_rules:, proposed_patch: }
    class ResultParser
      MIN_CONFIDENCE = 0.70

      # Maps known AI-suggested param names → algo.yml deep key paths and value bounds.
      # Format: key => { path: [...], min:, max: }
      KNOWN_PARAMS = {
        'sl_pct' => { path: %i[risk sl_pct], min: 0.05, max: 0.40 },
        'sl' => { path: %i[risk sl_pct], min: 0.05, max: 0.40 }, # Alias
        'sl_multiplier' => { path: %i[risk sl_pct], min: 0.05, max: 0.40 }, # Alias
        'stop_loss' => { path: %i[risk sl_pct], min: 0.05, max: 0.40 }, # Alias
        'tp_pct' => { path: %i[risk tp_pct], min: 0.10, max: 0.80 },
        'tp' => { path: %i[risk tp_pct], min: 0.10, max: 0.80 }, # Alias
        'tp_multiplier' => { path: %i[risk tp_pct], min: 0.10, max: 0.80 }, # Alias
        'take_profit' => { path: %i[risk tp_pct], min: 0.10, max: 0.80 }, # Alias
        'per_trade_risk_pct' => { path: %i[risk per_trade_risk_pct], min: 0.05, max: 0.80 },
        'target_rr' => { path: %i[risk rr_profit_booking target_rr],
                         min: 1.0, max: 10.0 },
        'trailing_activation' => { path: %i[position_sizing trailing activation_pct],
                                   min: 0.03, max: 0.30 },
        'trailing_drawdown' => { path: %i[position_sizing trailing drawdown_pct],
                                 min: 0.01, max: 0.20 },
        'direct_trailing_distance' => { path: %i[position_sizing direct_trailing distance_pct],
                                        min: 0.02, max: 0.25 },
        'profit_floor_lock_pct' => { path: %i[risk profit_floor lock_pct], min: 0.05, max: 0.50 },
        'profit_floor_trail_pct' => { path: %i[risk profit_floor trail_pct], min: 0.40, max: 0.95 },
        'primary_adx_min' => { path: nil, min: 10.0, max: 35.0 }, # per-index, handled separately
        'adx_threshold' => { path: nil, min: 10.0, max: 35.0 }, # Alias for primary_adx_min
        'rolling_window_threshold' => { path: %i[risk edge_failure_detector rolling_window_threshold_rupees],
                                        min: -20_000, max: -500 },
        'max_consecutive_sls' => { path: %i[risk edge_failure_detector max_consecutive_sls],
                                   min: 1, max: 10 },
        'trailing_activation_threshold' => { path: %i[position_sizing trailing activation_pct],
                                             min: 0.03, max: 0.30 } # Alias
      }.freeze

      class ParseError     < StandardError; end
      class SchemaError    < StandardError; end

      def self.call(raw_response)
        new(raw_response).call
      end

      def initialize(raw_response)
        @raw = raw_response
      end

      def call
        parsed = parse_json!

        validate_schema!(parsed)

        diagnosis          = parsed['system_diagnosis']
        parameter_changes  = filter_and_validate(parsed['parameter_changes'] || [])
        entry_filters      = filter_and_validate(parsed['entry_filters'] || [])
        exit_improvements  = filter_and_validate(parsed['exit_improvements'] || [])
        regime_rules       = parsed['regime_rules'] || []

        proposed_patch = build_proposed_patch(parameter_changes + entry_filters + exit_improvements)

        {
          diagnosis: diagnosis,
          parameter_changes: parameter_changes,
          entry_filters: entry_filters,
          exit_improvements: exit_improvements,
          regime_rules: regime_rules,
          proposed_patch: proposed_patch,
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
        missing = %w[system_diagnosis parameter_changes].reject { |k| parsed.key?(k) }
        raise SchemaError, "Missing required keys: #{missing.join(', ')}" if missing.any?
      end

      def filter_and_validate(suggestions)
        suggestions.select do |s|
          param_name = s['parameter']
          if param_name.blank?
            Rails.logger.debug("[ResultParser] Skipping empty parameter name")
            next false
          end

          unless KNOWN_PARAMS.key?(param_name)
            Rails.logger.debug("[ResultParser] Skipping unknown parameter: #{param_name}")
            next false
          end

          conf = s['confidence'].to_f
          if conf < MIN_CONFIDENCE
            Rails.logger.debug("[ResultParser] Skipping #{param_name}: confidence #{conf} < #{MIN_CONFIDENCE}")
            next false
          end

          spec = KNOWN_PARAMS[param_name]
          val  = s['suggested'].to_f

          # Enforce bounds
          if val < spec[:min] || val > spec[:max]
            Rails.logger.warn(
              "[ResultParser] #{param_name}=#{val} out of bounds [#{spec[:min]}, #{spec[:max]}], skipping"
            )
            next false
          end

          true
        end
      end

      # Converts accepted suggestions into a deep-mergeable hash compatible
      # with CalibrationRun#apply! + AlgoConfig.reset!
      def build_proposed_patch(suggestions)
        patch = {}

        suggestions.each do |s|
          param_name = s['parameter']
          spec       = KNOWN_PARAMS[param_name]
          next unless spec[:path] # skip params that need special handling (e.g. per-index ADX)

          set_nested(patch, spec[:path], s['suggested'])
        end

        patch
      end

      def set_nested(hash, path, value)
        *parents, last = path
        node = parents.each_with_object(hash) do |k, h|
          h[k.to_s] ||= {}
          h[k.to_s]
        end
        node[last.to_s] = value
      end
    end
  end
end
