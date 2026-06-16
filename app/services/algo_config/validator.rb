# frozen_string_literal: true

class AlgoConfig
  # Raised when a config write would persist out-of-range / wrong-typed gate values.
  class ValidationError < StandardError
    attr_reader :errors

    def initialize(errors)
      @errors = Array(errors)
      super(@errors.join('; '))
    end
  end

  # Hard-reject validation for the dangerous numeric/enum gates in the algo config.
  # Intentionally focused (not every key) and extensible via RULES.
  class Validator
    RULES = [
      { path: %i[entry_quality min_score],   kind: :number,  min: 0,    max: 100 },
      { path: %i[entry_quality gates min_adx], kind: :number, min: 0,   max: 100 },
      { path: %i[entry_quality gates min_body_ratio], kind: :number, min: 0.0, max: 1.0 },
      { path: %i[signals min_confidence],    kind: :number,  min: 0,    max: 100 },
      { path: %i[signals signal_tier],       kind: :enum,    allowed: %w[exploratory standard selective] },
      { path: %i[signals entry_dte_guard reject_when_days_to_expiry_lte], kind: :integer, min: -5, max: 30 },
      { path: %i[option_chain min_strike_score], kind: :number, min: 0 },
      { path: %i[risk sl_pct],               kind: :number,  min: 0.0,  max: 1.0 }
    ].freeze

    class << self
      # Validates +config+ (symbol-keyed). When +changed_paths+ is given, only rules whose
      # top-level key was changed are checked, so a pre-existing bad value under an untouched
      # key never blocks an unrelated write. Raises AlgoConfig::ValidationError on any failure.
      def validate!(config, changed_paths: nil)
        errors = collect_errors(config, scope_keys(changed_paths))
        raise ValidationError, errors if errors.any?

        true
      end

      private

      def collect_errors(config, allowed_keys)
        applicable_rules(allowed_keys).filter_map do |rule|
          value = config.dig(*rule[:path])
          rule_error(rule, value) unless value.nil?
        end
      end

      def applicable_rules(allowed_keys)
        return RULES if allowed_keys.nil?

        RULES.select { |rule| allowed_keys.include?(rule[:path].first) }
      end

      # nil => validate everything (no scope given, or a sentinel path like /__forced_bootstrap__).
      def scope_keys(changed_paths)
        return nil if changed_paths.blank?

        keys = Array(changed_paths).map { |path| path.to_s.delete_prefix('/').to_sym }
        return nil if keys.any? { |key| key.to_s.start_with?('__') }

        keys
      end

      def rule_error(rule, value)
        case rule[:kind]
        when :enum    then enum_error(rule, value)
        when :integer then integer_error(rule, value)
        else number_error(rule, value)
        end
      end

      def enum_error(rule, value)
        return if rule[:allowed].include?(value.to_s)

        "#{label(rule)} must be one of #{rule[:allowed].join(', ')} (got #{value.inspect})"
      end

      def integer_error(rule, value)
        return "#{label(rule)} must be an integer (got #{value.inspect})" unless integer_like?(value)

        range_error(rule, value.to_i)
      end

      def number_error(rule, value)
        return "#{label(rule)} must be a number (got #{value.inspect})" unless numeric_like?(value)

        range_error(rule, Float(value))
      end

      def range_error(rule, number)
        return "#{label(rule)} must be >= #{rule[:min]} (got #{number})" if rule[:min] && number < rule[:min]
        return "#{label(rule)} must be <= #{rule[:max]} (got #{number})" if rule[:max] && number > rule[:max]

        nil
      end

      def numeric_like?(value)
        return true if value.is_a?(Numeric)

        Float(value)
        true
      rescue ArgumentError, TypeError
        false
      end

      def integer_like?(value)
        return true if value.is_a?(Integer)

        Integer(value)
        true
      rescue ArgumentError, TypeError
        false
      end

      def label(rule)
        rule[:path].join('.')
      end
    end
  end
end
