# frozen_string_literal: true

module Risk
  module Rules
    # Rule that triggers an exit based on a specific time of day.
    # Matches logic from UnifiedExitChecker#time_based_exit?
    class TimeBasedExitRule < BaseRule
      PRIORITY = 60 # Check after structural and technical indicators

      def evaluate(context)
        return skip_result unless enabled?
        return skip_result unless context.active?

        config = config_for_rule
        exit_time_str = config[:exit_time] || '15:20'
        
        begin
          exit_time = Time.zone.parse(exit_time_str)
          return skip_result unless exit_time
          
          if Time.current >= exit_time
            return exit_result(
              reason: 'TIME_BASED',
              metadata: {
                exit_time: exit_time_str,
                path: 'time_exit'
              }
            )
          end
        rescue StandardError => e
          Rails.logger.error("[TimeBasedExitRule] Invalid exit_time: #{exit_time_str} - #{e.message}")
        end

        no_action_result
      end

      def enabled?
        config_for_rule[:enabled] == true
      end

      private
        # Handle both flat and nested config structures
        cfg = context_risk_config.dig(:exits, :time_based) || 
              context_risk_config[:time_based] || {}
        
        # Fallback to legacy location in AlgoConfig if needed
        if cfg.empty?
          cfg = AlgoConfig.fetch.dig(:exit, :time_based) || {}
        end

        cfg
      end
      
      def enabled?
        config_for_rule[:enabled] == true
      end
    end
  end
end
