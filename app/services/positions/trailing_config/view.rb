# frozen_string_literal: true

module Positions
  module TrailingConfig
    # Parsed trailing parameters from a risk config subtree (live or pinned snapshot).
    class View
      attr_reader :parsed

      def initialize(risk_config)
        @parsed = build_parsed(risk_config || {})
      end

      def trailing_mode
        parsed[:trailing_mode] || 'tiered'
      end

      def direct_trailing_enabled?
        trailing_mode == 'direct' && parsed[:direct_trailing]&.dig(:enabled) == true
      end

      def direct_trailing_distance_pct
        parsed[:direct_trailing]&.dig(:distance_pct) || 0.05
      end

      def direct_trailing_activation_profit_pct
        parsed[:direct_trailing]&.dig(:activation_profit_pct) || 0.0
      end

      def direct_trailing_min_sl_offset_pct
        parsed[:direct_trailing]&.dig(:min_sl_offset_pct) || -0.30
      end

      def hybrid_atr_enabled?
        trailing_mode == 'hybrid_atr' || parsed[:hybrid_atr]&.dig(:enabled) == true
      end

      def tiers
        parsed[:tiers]
      end

      def sl_offset_for(profit_pct)
        return nil if profit_pct.nil?

        profit_value = profit_pct.to_f
        tiers.reverse_each do |tier|
          return tier[:sl_offset_pct] if profit_value >= tier[:threshold_pct]
        end
        nil
      end

      def calculate_direct_trailing_sl(current_price:, entry_price:, current_profit_pct:)
        return nil unless direct_trailing_enabled?
        return nil unless current_price&.positive? && entry_price&.positive?
        return nil if current_profit_pct.to_f < direct_trailing_activation_profit_pct

        distance_pct = direct_trailing_distance_pct
        new_sl_price = current_price * (1.0 - distance_pct)
        min_sl_price = entry_price * (1.0 + direct_trailing_min_sl_offset_pct)
        [new_sl_price, min_sl_price].max.round(2)
      end

      def calculate_hybrid_atr_trailing_sl(current_price:, entry_price:, peak_price:, current_profit_pct:, atr_value:)
        return nil unless hybrid_atr_enabled?

        options = parsed[:hybrid_atr] || {}
        Positions::HybridAtrCalculator.calculate_sl_price(
          current_price: current_price,
          entry_price: entry_price,
          peak_price: peak_price,
          current_profit_pct: current_profit_pct,
          atr_value: atr_value,
          options: options
        )
      end

      def peak_drawdown_triggered?(peak_profit_pct, current_profit_pct, _capital_deployed: nil)
        return false unless peak_profit_pct && current_profit_pct

        drawdown_threshold = calculate_tiered_drawdown_threshold(peak_profit_pct)
        drawdown = peak_profit_pct - current_profit_pct

        drawdown >= drawdown_threshold
      end

      def calculate_tiered_drawdown_threshold(peak_profit_pct)
        peak = peak_profit_pct.to_f
        tiered_config = parsed[:tiered_drawdown_thresholds] || {}

        case peak
        when 0...0.05
          tiered_config[:very_low] || parsed[:peak_drawdown_pct] || TrailingConfig::DEFAULT_PEAK_DRAWDOWN_PCT
        when 0.05...0.10
          tiered_config[:low] || 0.025
        when 0.10...0.15
          tiered_config[:medium] || 0.02
        when 0.15...0.20
          tiered_config[:medium_high] || 0.015
        when 0.20...0.25
          tiered_config[:high] || 0.012
        when 0.25...0.30
          tiered_config[:very_high] || 0.01
        else
          tiered_config[:ultra_high] || 0.008
        end
      end

      def peak_drawdown_active?(profit_pct:, current_sl_offset_pct:)
        return true if profit_pct.to_f >= parsed[:activation_profit_pct].to_f * 2.0

        profit_pct.to_f >= parsed[:activation_profit_pct] ||
          current_sl_offset_pct.to_f >= parsed[:activation_sl_offset_pct]
      end

      def sl_price_from_entry(entry_price, sl_offset_pct)
        raise ArgumentError, 'entry_price required' if entry_price.nil?

        (entry_price.to_f * (1.0 + sl_offset_pct.to_f)).round(2)
      end

      def calculate_sl_price(entry_price, profit_pct)
        sl_offset_pct = sl_offset_for(profit_pct)
        return nil unless sl_offset_pct

        sl_price_from_entry(entry_price, sl_offset_pct).round(2)
      end

      private

      def build_parsed(risk)
        {
          trailing_mode: (risk[:trailing_mode] || 'tiered').to_s,
          direct_trailing: parse_direct_trailing(risk[:direct_trailing]),
          hybrid_atr: parse_hybrid_atr(risk[:hybrid_atr]),
          tiers: parse_tiers(risk[:trailing_tiers]) || TrailingConfig::DEFAULT_TIERS,
          peak_drawdown_pct: numeric_or_default(risk[:peak_drawdown_exit_pct], TrailingConfig::DEFAULT_PEAK_DRAWDOWN_PCT),
          activation_profit_pct: numeric_or_default(
            risk[:peak_drawdown_activation_profit_pct],
            TrailingConfig::DEFAULT_ACTIVATION_PROFIT_PCT
          ),
          activation_sl_offset_pct: numeric_or_default(
            risk[:peak_drawdown_activation_sl_offset_pct],
            TrailingConfig::DEFAULT_ACTIVATION_SL_OFFSET_PCT
          ),
          tiered_drawdown_thresholds: parse_tiered_drawdown_thresholds(risk[:tiered_drawdown_thresholds])
        }
      end

      def parse_hybrid_atr(hybrid_atr)
        return nil unless hybrid_atr.is_a?(Hash)

        {
          enabled: hybrid_atr[:enabled] == true || hybrid_atr['enabled'] == true,
          base_multiplier: numeric_or_default(hybrid_atr[:base_multiplier] || hybrid_atr['base_multiplier'], 2.0),
          activation_profit_pct: numeric_or_default(
            hybrid_atr[:activation_profit_pct] || hybrid_atr['activation_profit_pct'], 0.15
          ),
          min_sl_offset_pct: numeric_or_default(
            hybrid_atr[:min_sl_offset_pct] || hybrid_atr['min_sl_offset_pct'], -0.15
          )
        }
      rescue StandardError
        nil
      end

      def parse_direct_trailing(direct_trailing)
        return nil unless direct_trailing.is_a?(Hash)

        {
          enabled: direct_trailing[:enabled] == true || direct_trailing['enabled'] == true,
          distance_pct: numeric_or_default(direct_trailing[:distance_pct] || direct_trailing['distance_pct'], 0.05),
          activation_profit_pct: numeric_or_default(
            direct_trailing[:activation_profit_pct] || direct_trailing['activation_profit_pct'], 0.0
          ),
          min_sl_offset_pct: numeric_or_default(
            direct_trailing[:min_sl_offset_pct] || direct_trailing['min_sl_offset_pct'], -0.30
          )
        }
      rescue StandardError
        nil
      end

      def parse_tiered_drawdown_thresholds(thresholds)
        return {} unless thresholds.is_a?(Hash)

        {
          very_low: numeric_or_default(thresholds[:very_low], nil),
          low: numeric_or_default(thresholds[:low], nil),
          medium: numeric_or_default(thresholds[:medium], nil),
          medium_high: numeric_or_default(thresholds[:medium_high], nil),
          high: numeric_or_default(thresholds[:high], nil),
          very_high: numeric_or_default(thresholds[:very_high], nil),
          ultra_high: numeric_or_default(thresholds[:ultra_high], nil)
        }
      rescue StandardError
        {}
      end

      def parse_tiers(tiers)
        return nil unless tiers.is_a?(Array) && tiers.any?

        tiers.map do |tier|
          {
            threshold_pct: tier[:trigger_pct].to_f,
            sl_offset_pct: tier[:sl_offset_pct].to_f
          }
        end
      rescue StandardError
        nil
      end

      def numeric_or_default(value, default)
        return default if value.nil?

        Float(value)
      rescue StandardError
        default
      end
    end
  end
end
