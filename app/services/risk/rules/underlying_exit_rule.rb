# frozen_string_literal: true

module Risk
  module Rules
    # Rule that enforces underlying-aware exits
    # Triggers exit based on underlying instrument state (structure breaks, trend weakness, ATR collapse)
    class UnderlyingExitRule < BaseRule
      PRIORITY = 60

      def evaluate(context)
        return skip_result unless context.active?

        # Check if underlying exits are enabled
        return skip_result unless underlying_exits_enabled?

        underlying_state = Live::UnderlyingMonitor.evaluate(context.position)
        return no_action_result unless underlying_state

        # Check structure break
        if structure_break_against_position?(context, underlying_state)
          return exit_result(
            reason: 'underlying_structure_break',
            metadata: {
              underlying_state: underlying_state,
              position_direction: normalized_position_direction(context)
            }
          )
        end

        # Check trend weakness
        if underlying_state.trend_score &&
           underlying_state.trend_score.to_f < underlying_trend_score_threshold
          return exit_result(
            reason: 'underlying_trend_weak',
            metadata: {
              underlying_state: underlying_state,
              trend_score: underlying_state.trend_score,
              threshold: underlying_trend_score_threshold
            }
          )
        end

        # Check ATR collapse
        if atr_collapse?(underlying_state)
          return exit_result(
            reason: 'underlying_atr_collapse',
            metadata: {
              underlying_state: underlying_state,
              atr_ratio: underlying_state.atr_ratio,
              threshold: underlying_atr_ratio_threshold
            }
          )
        end

        # Check SMC bias flip (opt-in via use_smc_bias_flip config)
        if smc_bias_flip_exit?(underlying_state)
          return exit_result(
            reason: 'smc_bias_flip',
            metadata: {
              underlying_state: underlying_state,
              trend_score: underlying_state.trend_score,
              threshold: smc_bias_flip_trend_threshold
            }
          )
        end

        no_action_result
      end

      private

      def underlying_exits_enabled?
        feature_flags[:enable_underlying_aware_exits] == true
      end

      def feature_flags
        AlgoConfig.fetch[:feature_flags] || {}
      rescue StandardError
        {}
      end

      def structure_break_against_position?(context, underlying_state)
        return false unless underlying_state&.bos_state == :broken

        direction = normalized_position_direction(context)
        (direction == :bullish && underlying_state.bos_direction == :bearish) ||
          (direction == :bearish && underlying_state.bos_direction == :bullish)
      end

      def normalized_position_direction(context)
        direction = context.position.position_direction
        return direction.to_s.downcase.to_sym if direction.present?

        Positions::MetadataResolver.direction(context.tracker)
      end

      def underlying_trend_score_threshold
        config_value = @config.fetch(:underlying_trend_score_threshold, 10.0)
        config_value.to_f.positive? ? config_value.to_f : 10.0
      end

      def underlying_atr_ratio_threshold
        value = @config[:underlying_atr_collapse_multiplier]
        value ? value.to_f : 0.65
      end

      def atr_collapse?(underlying_state)
        return false unless underlying_state

        underlying_state.atr_trend == :falling &&
          underlying_state.atr_ratio &&
          underlying_state.atr_ratio.to_f < underlying_atr_ratio_threshold
      end

      def smc_bias_flip_exit?(underlying_state)
        return false unless @config.fetch(:use_smc_bias_flip, false) == true
        return false unless underlying_state&.smc_bias_flip == true

        score = underlying_state.trend_score
        score.nil? || score.to_f < smc_bias_flip_trend_threshold
      end

      def smc_bias_flip_trend_threshold
        @config.fetch(:smc_bias_flip_trend_threshold, 40).to_f
      end
    end
  end
end
