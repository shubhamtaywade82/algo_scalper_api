# frozen_string_literal: true

module Backtest
  # Loads optimized indicator parameters from BestIndicatorParam
  # Falls back to defaults if not found, allows manual override
  class OptimizedParamsLoader
    DEFAULT_SUPERTREND = { period: 7, base_multiplier: 3.0 }.freeze
    DEFAULT_ADX_MIN_STRENGTH = 0

    class << self
      # Load optimized parameters for backtesting
      # @param instrument [Instrument] Instrument to load params for
      # @param interval [String] Timeframe interval (e.g., '5' for 5m)
      # @param supertrend_cfg [Hash, nil] Manual override for Supertrend (optional)
      # @param adx_min_strength [Integer, nil] Manual override for ADX (optional)
      # @return [Hash] Hash with :supertrend_cfg and :adx_min_strength
      def load_for_backtest(instrument:, interval:, supertrend_cfg: nil, adx_min_strength: nil)
        # If manual overrides provided, use them (highest priority)
        if supertrend_cfg.present? || !adx_min_strength.nil?
          Rails.logger.info("[OptimizedParamsLoader] Using manual override parameters for #{instrument.symbol_name}")
          return {
            supertrend_cfg: supertrend_cfg || DEFAULT_SUPERTREND.dup,
            adx_min_strength: adx_min_strength || DEFAULT_ADX_MIN_STRENGTH,
            source: :manual
          }
        end

        # Try to load from BestIndicatorParam
        optimized = load_from_database(instrument: instrument, interval: interval)

        if optimized
          Rails.logger.info("[OptimizedParamsLoader] Using optimized parameters from BestIndicatorParam for #{instrument.symbol_name} @ #{interval}m")
          optimized[:source] = :optimized
          optimized
        else
          Rails.logger.info("[OptimizedParamsLoader] No optimized parameters found, using defaults for #{instrument.symbol_name}")
          {
            supertrend_cfg: DEFAULT_SUPERTREND.dup,
            adx_min_strength: DEFAULT_ADX_MIN_STRENGTH,
            source: :default
          }
        end
      end

      private

      # Load optimized parameters from database
      # @param instrument [Instrument] Instrument to load params for
      # @param interval [String] Timeframe interval
      # @return [Hash, nil] Hash with :supertrend_cfg and :adx_min_strength, or nil if not found
      def load_from_database(instrument:, interval:)
        return nil unless defined?(BestIndicatorParam)
        return nil unless BestIndicatorParam.table_exists?

        candidates = []

        # Try Supertrend-specific optimization
        supertrend_best = BestIndicatorParam.best_for_indicator(instrument.id, interval, 'supertrend').first
        if supertrend_best
          params = supertrend_best.params || {}
          supertrend_cfg = extract_supertrend_params(params)
          if supertrend_cfg
            adx_min_strength = extract_adx_threshold(params) || DEFAULT_ADX_MIN_STRENGTH
            candidates << {
              supertrend_cfg: supertrend_cfg,
              adx_min_strength: adx_min_strength,
              score: supertrend_best.score,
              metrics: supertrend_best.metrics,
              source_type: 'supertrend'
            }
          end
        end

        # Try combined optimization
        combined_best = BestIndicatorParam.best_for(instrument.id, interval).first
        if combined_best
          params = combined_best.params || {}
          supertrend_cfg = extract_supertrend_params(params)
          if supertrend_cfg
            adx_min_strength = extract_adx_threshold(params) || DEFAULT_ADX_MIN_STRENGTH
            candidates << {
              supertrend_cfg: supertrend_cfg,
              adx_min_strength: adx_min_strength,
              score: combined_best.score,
              metrics: combined_best.metrics,
              source_type: 'combined'
            }
          end
        end

        # Return the candidate with the best score (highest score wins)
        return nil if candidates.empty?

        best_candidate = candidates.max_by { |c| c[:score] }
        best_candidate.delete(:source_type) # Remove internal tracking field
        best_candidate
      rescue StandardError => e
        Rails.logger.warn("[OptimizedParamsLoader] Error loading optimized params: #{e.class} - #{e.message}")
        nil
      end

      # Extract Supertrend parameters from params hash
      # Handles multiple naming conventions:
      # - st_atr/st_mult (from IndicatorOptimizer)
      # - atr_period/multiplier (from combined optimization)
      # - supertrend_period/supertrend_multiplier (from optimize_indicator_parameters.rb)
      # - period/base_multiplier (standard format)
      # @param params [Hash] Parameters hash from BestIndicatorParam
      # @return [Hash, nil] Supertrend config hash or nil
      def extract_supertrend_params(params)
        # Normalize keys (handle both string and symbol keys)
        normalized = params.with_indifferent_access

        # Try different naming conventions for period
        period = normalized[:atr_period] || normalized['atr_period'] ||
                 normalized[:st_atr] || normalized['st_atr'] ||
                 normalized[:supertrend_period] || normalized['supertrend_period'] ||
                 normalized[:period] || normalized['period']

        # Try different naming conventions for multiplier
        multiplier = normalized[:multiplier] || normalized['multiplier'] ||
                     normalized[:st_mult] || normalized['st_mult'] ||
                     normalized[:supertrend_multiplier] || normalized['supertrend_multiplier'] ||
                     normalized[:base_multiplier] || normalized['base_multiplier']

        return nil unless period && multiplier

        {
          period: period.to_i,
          base_multiplier: multiplier.to_f
        }
      end

      # Extract ADX threshold from params hash
      # Handles multiple naming conventions:
      # - adx_thresh (from IndicatorOptimizer)
      # - adx_1m_threshold, adx_5m_threshold (from optimize_indicator_parameters.rb)
      # - adx_min_strength (standard format)
      # @param params [Hash] Parameters hash from BestIndicatorParam
      # @return [Integer, nil] ADX threshold or nil
      def extract_adx_threshold(params)
        normalized = params.with_indifferent_access

        # Try different naming conventions
        normalized[:adx_thresh] || normalized['adx_thresh'] ||
          normalized[:adx_1m_threshold] || normalized['adx_1m_threshold'] ||
          normalized[:adx_min_strength] || normalized['adx_min_strength']
      end
    end
  end
end
