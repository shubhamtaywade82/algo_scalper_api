# frozen_string_literal: true

module Indicators
  # Configuration helper for indicator thresholds
  # Allows easy switching between loose (testing) and tight (production) values
  class ThresholdConfig
    # Preset configurations for different testing phases
    PRESETS = {
      # LOOSE: Very permissive - generates more signals for testing
      loose: {
        adx: {
          min_strength: 10,        # Very low - allows weak trends
          confidence_base: 40      # Lower base confidence
        },
        rsi: {
          oversold: 40,            # Less strict - triggers more often
          overbought: 60,           # Less strict - triggers more often
          confidence_base: 35      # Lower base confidence
        },
        macd: {
          min_histogram: 0.1,      # Very small threshold
          confidence_base: 40
        },
        trend_duration: {
          trend_length: 3,         # Shorter confirmation period
          min_confidence: 40       # Lower confidence threshold
        },
        multi_indicator: {
          min_confidence: 40,      # Lower combined confidence
          confirmation_mode: :any  # Most permissive mode
        }
      },

      # MODERATE: Balanced - good starting point
      moderate: {
        adx: {
          min_strength: 15,
          confidence_base: 50
        },
        rsi: {
          oversold: 35,
          overbought: 65,
          confidence_base: 45
        },
        macd: {
          min_histogram: 0.5,
          confidence_base: 50
        },
        trend_duration: {
          trend_length: 4,
          min_confidence: 50
        },
        multi_indicator: {
          min_confidence: 50,
          confirmation_mode: :majority
        }
      },

      # TIGHT: Strict - fewer but higher quality signals
      tight: {
        adx: {
          min_strength: 25,        # Higher threshold - only strong trends
          confidence_base: 60
        },
        rsi: {
          oversold: 25,            # More extreme levels
          overbought: 75,
          confidence_base: 55
        },
        macd: {
          min_histogram: 1.0,      # Larger threshold
          confidence_base: 60
        },
        trend_duration: {
          trend_length: 6,         # Longer confirmation period
          min_confidence: 65
        },
        multi_indicator: {
          min_confidence: 70,      # Higher combined confidence
          confirmation_mode: :all  # Most strict - all must agree
        }
      },

      # PRODUCTION: Optimized based on backtesting results
      production: {
        adx: {
          min_strength: 20,        # Balanced threshold
          confidence_base: 55
        },
        rsi: {
          oversold: 30,
          overbought: 70,
          confidence_base: 50
        },
        macd: {
          min_histogram: 0.5,
          confidence_base: 55
        },
        trend_duration: {
          trend_length: 5,
          min_confidence: 60
        },
        multi_indicator: {
          min_confidence: 60,
          confirmation_mode: :all
        }
      }
    }.freeze

    class << self
      # Get threshold preset
      # @param preset_name [Symbol] :loose, :moderate, :tight, :production
      # @return [Hash] Threshold configuration
      def get_preset(preset_name = :moderate)
        PRESETS[preset_name.to_sym] || PRESETS[:moderate]
      end

      # Get current preset from config (algo.yml preferred, ENV as fallback)
      # @return [Symbol] Current preset name
      def current_preset
        # Prefer algo.yml over ENV
        preset_name = AlgoConfig.fetch.dig(:signals, :indicator_preset)&.to_sym ||
                      ENV['INDICATOR_PRESET']&.to_sym ||
                      :moderate
        PRESETS.key?(preset_name) ? preset_name : :moderate
      end

      # Get thresholds for specific indicator
      # @param indicator_name [Symbol] :adx, :rsi, :macd, :trend_duration, :multi_indicator
      # @param preset_name [Symbol] Optional preset name, defaults to current preset
      # @return [Hash] Threshold configuration for indicator
      def for_indicator(indicator_name, preset_name = nil)
        preset = preset_name ? get_preset(preset_name) : get_preset(current_preset)
        preset[indicator_name.to_sym] || {}
      end

      # Merge threshold config with indicator config
      # @param indicator_name [Symbol] Indicator name
      # @param base_config [Hash] Base configuration from algo.yml
      # @param preset_name [Symbol] Optional preset override
      # @return [Hash] Merged configuration (base_config takes precedence over thresholds)
      def merge_with_thresholds(indicator_name, base_config = {}, preset_name = nil)
        thresholds = for_indicator(indicator_name, preset_name)
        thresholds.merge(base_config) # Base config overrides thresholds
      end

      # Get all available presets
      # @return [Array<Symbol>] List of preset names
      def available_presets
        PRESETS.keys
      end

      # Check if preset exists
      # @param preset_name [Symbol] Preset name to check
      # @return [Boolean]
      def preset_exists?(preset_name)
        PRESETS.key?(preset_name.to_sym)
      end
    end
  end
end
