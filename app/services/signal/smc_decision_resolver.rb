# frozen_string_literal: true

module Signal
  # Resolves the Smart Money Concepts bias decision for an instrument and
  # checks it against a candidate signal direction. Extracted from Signal::Engine.
  class SmcDecisionResolver
    class << self
      def get_smc_decision(index_cfg, instrument, signals_cfg, signal_direction)
        # Check if SMC decision alignment is enabled
        enable_smc_alignment = signals_cfg.fetch(:enable_smc_decision_alignment, true)
        # Return permissive default based on signal direction when disabled
        unless enable_smc_alignment
          return signal_direction == :bullish ? :call : :put
        end

        begin
          # Use BiasEngine to get SMC decision
          # Note: We use delay_seconds: 0 since we're already in a signal generation context
          # and don't want to add unnecessary delays
          engine = Smc::BiasEngine.new(instrument, delay_seconds: 0)
          decision = engine.decision

          # If BiasEngine returns :no_trade, be permissive and align with signal direction
          if decision == :no_trade
            Rails.logger.debug { "[Signal] SMC decision returned :no_trade for #{index_cfg[:key]}, defaulting to signal direction" }
            return signal_direction == :bullish ? :call : :put
          end

          decision
        rescue StandardError => e
          Rails.logger.fatal("[FATAL_SIGNAL_ERROR] #{e.class}: #{e.message}\n#{e.backtrace.first(10).join(%(\n))}")
          Rails.logger.warn("[Signal] SMC decision check failed for #{index_cfg[:key]}: #{e.class} - #{e.message}")
          # Default to signal direction on error (allows trades instead of blocking)
          # :call for bullish signals, :put for bearish signals
          signal_direction == :bullish ? :call : :put
        end
      end

      # Check if SMC decision aligns with signal direction
      # call = bullish, put = bearish, no_trade = blocks all
      def smc_decision_aligned?(smc_decision, signal_direction)
        return false if smc_decision.nil?
        return false if smc_decision == :no_trade

        case signal_direction
        when :bullish
          smc_decision == :call
        when :bearish
          smc_decision == :put
        else
          false
        end
      end
    end
  end
end
