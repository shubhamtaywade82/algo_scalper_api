# frozen_string_literal: true

module Signal
  # Builds the diagnostic entry_path string (strategy_timeframe_confirmation)
  # stored on signal metadata. Extracted from Signal::Engine.
  class EntryPathIdentifier
    class << self
      def build(strategy_recommendation:, use_strategy_recommendations:, effective_timeframe:, confirmation_tf:, enable_confirmation:)
        strategy_part = if use_strategy_recommendations && strategy_recommendation&.dig(:recommended)
                          strategy_recommendation[:strategy_name].downcase.gsub(/\s+/, '_')
                        else
                          'supertrend_adx'
                        end

        timeframe_part = effective_timeframe

        confirmation_part = if enable_confirmation && confirmation_tf.present?
                              confirmation_tf
                            else
                              'none'
                            end

        "#{strategy_part}_#{timeframe_part}_#{confirmation_part}"
      end
    end
  end
end
