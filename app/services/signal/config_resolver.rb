# frozen_string_literal: true

module Signal
  # Resolves signal-generation config: validation-mode presets and
  # multi-indicator-strategy eligibility. Extracted from Signal::Engine.
  class ConfigResolver
    class << self
      def validation_mode_config(override_mode: nil)
        signals_cfg = AlgoConfig.fetch[:signals] || {}
        mode = override_mode || signals_cfg[:validation_mode] || 'balanced'
        mode_config = signals_cfg.dig(:validation_modes, mode.to_sym) ||
                      signals_cfg.dig(:validation_modes, :balanced) || {}

        # Ensure mode_config is always a Hash (handle edge cases where config might be wrong type)
        mode_config = {} unless mode_config.is_a?(Hash)

        # Merge with mode name for logging
        mode_config.merge(mode: mode)
      end

      def multi_indicator_enabled?(signals_cfg)
        signals_cfg.fetch(:use_multi_indicator_strategy, false) && signals_cfg[:indicators].present?
      end
    end
  end
end
