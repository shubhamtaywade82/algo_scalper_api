# frozen_string_literal: true

module Positions
  module TrailingConfig
    DEFAULT_PEAK_DRAWDOWN_PCT = 5.0
    PEAK_DRAWDOWN_PCT = DEFAULT_PEAK_DRAWDOWN_PCT
    DEFAULT_ACTIVATION_PROFIT_PCT = 25.0
    DEFAULT_ACTIVATION_SL_OFFSET_PCT = 10.0
    DEFAULT_TIERS = [
      { threshold_pct: 5.0,   sl_offset_pct: -15.0 },
      { threshold_pct: 10.0,  sl_offset_pct: -5.0  },
      { threshold_pct: 15.0,  sl_offset_pct: 0.0   },
      { threshold_pct: 25.0,  sl_offset_pct: 10.0  },
      { threshold_pct: 40.0,  sl_offset_pct: 20.0  },
      { threshold_pct: 60.0,  sl_offset_pct: 30.0  },
      { threshold_pct: 80.0,  sl_offset_pct: 40.0  },
      { threshold_pct: 120.0, sl_offset_pct: 60.0  }
    ].freeze

    module_function

    def trailing_mode
      config[:trailing_mode] || 'tiered'
    end

    def direct_trailing_enabled?
      trailing_mode == 'direct' && config[:direct_trailing]&.dig(:enabled) == true
    end

    def direct_trailing_distance_pct
      config[:direct_trailing]&.dig(:distance_pct) || 5.0
    end

    def direct_trailing_activation_profit_pct
      config[:direct_trailing]&.dig(:activation_profit_pct) || 0.0
    end

    def direct_trailing_min_sl_offset_pct
      config[:direct_trailing]&.dig(:min_sl_offset_pct) || -30.0
    end

    def tiers
      config[:tiers]
    end

    def sl_offset_for(profit_pct)
      return nil if profit_pct.nil?

      profit_value = profit_pct.to_f
      tiers.reverse_each do |tier|
        return tier[:sl_offset_pct] if profit_value >= tier[:threshold_pct]
      end
      nil
    end

    # Calculate SL price using direct trailing mode (based on current price)
    # @param current_price [Float] Current LTP
    # @param entry_price [Float] Entry price
    # @param current_profit_pct [Float] Current profit percentage
    # @return [Float, nil] New SL price or nil if not applicable
    def calculate_direct_trailing_sl(current_price:, entry_price:, current_profit_pct:)
      return nil unless direct_trailing_enabled?
      return nil unless current_price&.positive? && entry_price&.positive?

      # Check activation threshold
      return nil if current_profit_pct.to_f < direct_trailing_activation_profit_pct

      # Calculate SL as: current_price * (1 - distance_pct / 100)
      # For CE calls: SL should be below current price
      distance_pct = direct_trailing_distance_pct
      new_sl_price = current_price * (1.0 - (distance_pct / 100.0))

      # Ensure SL doesn't go below minimum offset from entry
      min_sl_price = entry_price * (1.0 + (direct_trailing_min_sl_offset_pct / 100.0))
      new_sl_price = [new_sl_price, min_sl_price].max

      new_sl_price.round(2)
    end

    def peak_drawdown_triggered?(peak_profit_pct, current_profit_pct, _capital_deployed: nil)
      return false unless peak_profit_pct && current_profit_pct

      # Use tiered drawdown threshold based on peak height
      # Higher peaks get tighter protection to preserve profits
      drawdown_threshold = calculate_tiered_drawdown_threshold(peak_profit_pct)
      drawdown = peak_profit_pct - current_profit_pct

      drawdown >= drawdown_threshold
    end

    # Calculate tiered drawdown threshold based on peak profit percentage
    # Higher peaks get progressively tighter protection
    # @param peak_profit_pct [Float] Peak profit percentage
    # @return [Float] Drawdown threshold percentage
    def calculate_tiered_drawdown_threshold(peak_profit_pct)
      peak = peak_profit_pct.to_f

      # Get tiered thresholds from config if available
      tiered_config = config[:tiered_drawdown_thresholds] || {}

      # Tiered protection: Higher peaks = tighter drawdown allowed
      # Use exclusive upper bounds to avoid overlap
      case peak
      when 0...5
        # Very low peaks: Use base threshold
        tiered_config[:very_low] || config[:peak_drawdown_pct] || DEFAULT_PEAK_DRAWDOWN_PCT
      when 5...10
        # Low peaks: Slightly tighter
        tiered_config[:low] || 2.5
      when 10...15
        # Medium peaks: Tighter protection
        tiered_config[:medium] || 2.0
      when 15...20
        # Medium-high peaks: Even tighter
        tiered_config[:medium_high] || 1.5
      when 20...25
        # High peaks: Very tight protection
        tiered_config[:high] || 1.2
      when 25...30
        # Very high peaks: Extremely tight
        tiered_config[:very_high] || 1.0
      else
        # Ultra high peaks (>=30%): Maximum protection (0.8% drawdown)
        tiered_config[:ultra_high] || 0.8
      end
    end

    def peak_drawdown_active?(profit_pct:, current_sl_offset_pct:)
      profit_pct.to_f >= config[:activation_profit_pct] &&
        current_sl_offset_pct.to_f >= config[:activation_sl_offset_pct]
    end

    def sl_price_from_entry(entry_price, sl_offset_pct)
      raise ArgumentError, 'entry_price required' if entry_price.nil?

      entry_price.to_f * (1.0 + (sl_offset_pct.to_f / 100.0))
    end

    def calculate_sl_price(entry_price, profit_pct)
      sl_offset_pct = sl_offset_for(profit_pct)
      return nil unless sl_offset_pct

      sl_price_from_entry(entry_price, sl_offset_pct).round(2)
    end

    def config
      @config ||= begin
        risk = fetch_risk_config
        {
          trailing_mode: (risk[:trailing_mode] || 'tiered').to_s,
          direct_trailing: parse_direct_trailing(risk[:direct_trailing]),
          tiers: parse_tiers(risk[:trailing_tiers]) || DEFAULT_TIERS,
          peak_drawdown_pct: numeric_or_default(risk[:peak_drawdown_exit_pct], DEFAULT_PEAK_DRAWDOWN_PCT),
          dynamic_drawdown_thresholds: parse_dynamic_drawdown_thresholds(risk[:dynamic_drawdown_thresholds]),
          capital_based_thresholds: parse_capital_based_thresholds(risk[:capital_based_thresholds]),
          activation_profit_pct: numeric_or_default(risk[:peak_drawdown_activation_profit_pct],
                                                    DEFAULT_ACTIVATION_PROFIT_PCT),
          activation_sl_offset_pct: numeric_or_default(risk[:peak_drawdown_activation_sl_offset_pct],
                                                       DEFAULT_ACTIVATION_SL_OFFSET_PCT),
          tiered_drawdown_thresholds: parse_tiered_drawdown_thresholds(risk[:tiered_drawdown_thresholds])
        }
      end
    end

    def parse_direct_trailing(direct_trailing)
      return nil unless direct_trailing.is_a?(Hash)

      {
        enabled: direct_trailing[:enabled] == true || direct_trailing['enabled'] == true,
        distance_pct: numeric_or_default(direct_trailing[:distance_pct] || direct_trailing['distance_pct'], 5.0),
        activation_profit_pct: numeric_or_default(direct_trailing[:activation_profit_pct] || direct_trailing['activation_profit_pct'], 0.0),
        min_sl_offset_pct: numeric_or_default(direct_trailing[:min_sl_offset_pct] || direct_trailing['min_sl_offset_pct'], -30.0)
      }
    rescue StandardError
      nil
    end

    def parse_dynamic_drawdown_thresholds(thresholds)
      return {} unless thresholds.is_a?(Hash)

      {}
    rescue StandardError
      {}
    end

    def parse_capital_based_thresholds(thresholds)
      return {} unless thresholds.is_a?(Hash)

      {}
    rescue StandardError
      {}
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

    def fetch_risk_config
      AlgoConfig.fetch[:risk] || {}
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
