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

    def peak_drawdown_triggered?(peak_profit_pct, current_profit_pct, capital_deployed: nil)
      return false unless peak_profit_pct && current_profit_pct

      # Use dynamic drawdown threshold based on peak profit level and capital
      threshold = dynamic_drawdown_threshold(peak_profit_pct, capital_deployed: capital_deployed)
      (peak_profit_pct - current_profit_pct) >= threshold
    end

    # Dynamic drawdown threshold based on profit level and capital deployed
    # Lower profit = tighter protection, higher profit = more room
    # Larger capital = tighter protection to ensure profitable exits
    # @param peak_profit_pct [Float] Peak profit percentage
    # @param capital_deployed [Float, nil] Capital deployed (entry_price * quantity)
    # @return [Float] Drawdown threshold percentage
    def dynamic_drawdown_threshold(peak_profit_pct, capital_deployed: nil)
      return config[:peak_drawdown_pct] unless peak_profit_pct

      peak = peak_profit_pct.to_f

      # Determine profit level category
      profit_category = if peak < 10.0
                          :low_profit
                        elsif peak < 25.0
                          :medium_profit
                        else
                          :high_profit
                        end

      # Use capital-based thresholds if capital is provided and thresholds are configured
      if capital_deployed&.positive? && config[:capital_based_thresholds]
        capital_thresholds = capital_based_threshold_for_capital(capital_deployed)
        if capital_thresholds
          threshold = capital_thresholds[profit_category]
          return threshold if threshold
        end
      end

      # Fallback to profit-level based thresholds
      case profit_category
      when :low_profit
        config[:dynamic_drawdown_thresholds]&.dig(:low_profit) || 2.0
      when :medium_profit
        config[:dynamic_drawdown_thresholds]&.dig(:medium_profit) || 3.0
      else
        config[:dynamic_drawdown_thresholds]&.dig(:high_profit) || config[:peak_drawdown_pct]
      end
    end

    # Get capital-based thresholds for a given capital amount
    # @param capital_deployed [Float] Capital deployed (entry_price * quantity)
    # @return [Hash, nil] Thresholds hash with :low_profit, :medium_profit, :high_profit or nil
    def capital_based_threshold_for_capital(capital_deployed)
      return nil unless capital_deployed&.positive?

      capital = capital_deployed.to_f
      thresholds = config[:capital_based_thresholds]
      return nil unless thresholds.is_a?(Hash)

      # Check large capital first (> ₹50k)
      if thresholds[:large_capital] && thresholds[:large_capital][:min_capital]
        min = thresholds[:large_capital][:min_capital].to_f
        return thresholds[:large_capital] if capital >= min
      end

      # Check medium capital (₹30k - ₹50k)
      if thresholds[:medium_capital]
        min = thresholds[:medium_capital][:min_capital]&.to_f || 0.0
        max = thresholds[:medium_capital][:max_capital]&.to_f || Float::INFINITY
        return thresholds[:medium_capital] if capital >= min && capital < max
      end

      # Check small capital (< ₹30k)
      if thresholds[:small_capital] && thresholds[:small_capital][:max_capital]
        max = thresholds[:small_capital][:max_capital].to_f
        return thresholds[:small_capital] if capital < max
      end

      nil
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
                                                       DEFAULT_ACTIVATION_SL_OFFSET_PCT)
        }
      end
    end

    def parse_capital_based_thresholds(thresholds)
      return nil unless thresholds.is_a?(Hash)

      result = {}
      %i[small_capital medium_capital large_capital].each do |key|
        next unless thresholds[key].is_a?(Hash)

        tier = thresholds[key]
        result[key] = {
          min_capital: numeric_or_default(tier[:min_capital], nil),
          max_capital: numeric_or_default(tier[:max_capital], nil),
          low_profit: numeric_or_default(tier[:low_profit], nil),
          medium_profit: numeric_or_default(tier[:medium_profit], nil),
          high_profit: numeric_or_default(tier[:high_profit], nil)
        }
      end
      result.empty? ? nil : result
    rescue StandardError
      nil
    end

    def parse_direct_trailing(direct_trailing)
      return nil unless direct_trailing.is_a?(Hash)

      {
        enabled: direct_trailing[:enabled] == true,
        distance_pct: numeric_or_default(direct_trailing[:distance_pct], 5.0),
        activation_profit_pct: numeric_or_default(direct_trailing[:activation_profit_pct], 0.0),
        min_sl_offset_pct: numeric_or_default(direct_trailing[:min_sl_offset_pct], -30.0)
      }
    rescue StandardError
      nil
    end

    def parse_dynamic_drawdown_thresholds(thresholds)
      return nil unless thresholds.is_a?(Hash)

      {
        low_profit: numeric_or_default(thresholds[:low_profit], 2.0),
        medium_profit: numeric_or_default(thresholds[:medium_profit], 3.0),
        high_profit: numeric_or_default(thresholds[:high_profit], 5.0)
      }
    rescue StandardError
      nil
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
