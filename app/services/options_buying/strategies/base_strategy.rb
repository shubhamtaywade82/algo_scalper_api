# frozen_string_literal: true

module OptionsBuying
  module Strategies
    # Base class defining the interface for all options buying entry strategies.
    class BaseStrategy
      def initialize(index_key:, security_id:)
        @index_key = index_key.to_s.upcase
        @security_id = security_id.to_s
      end

      # Required: Evaluate current market state and return an entry signal if valid.
      # @param market_state [Hash] Pre-assembled state from StrategyEngine
      # @return [Hash, nil] Signal hash with :direction, :option_security_id, :metrics
      def check_entry(market_state)
        raise NotImplementedError, "#{self.class} must implement #check_entry"
      end

      # Required: The name of the strategy (used for logging and telemetry)
      def name
        raise NotImplementedError, "#{self.class} must implement #name"
      end

      # Required: The market regime this strategy is valid for (e.g. :trending, :ranging)
      def required_regime
        raise NotImplementedError, "#{self.class} must implement #required_regime"
      end

      protected

      def config
        Mode.config.dig(:strategies, name.to_sym) || {}
      end

      def sink_telemetry!(direction:, option_security_id:, metrics:)
        return unless Mode.telemetry_sink_enabled?

        OptionsBuying::TelemetrySinkJob.perform_later(
          index_key: @index_key,
          security_id: option_security_id,
          event_type: "strategy_entry_#{direction}_#{name}",
          occurred_at: Time.current.iso8601,
          metadata: metrics.merge(strategy: name)
        )
      rescue StandardError => e
        Rails.logger.warn("[#{self.class.name}] telemetry enqueue failed: #{e.message}")
      end
    end
  end
end
