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

    def peak_drawdown_triggered?(peak_profit_pct, current_profit_pct)
      return false unless peak_profit_pct && current_profit_pct

      (peak_profit_pct - current_profit_pct) >= config[:peak_drawdown_pct]
    end

    def peak_drawdown_active?(profit_pct:, current_sl_offset_pct:)
      profit_pct.to_f >= config[:activation_profit_pct] &&
        current_sl_offset_pct.to_f >= config[:activation_sl_offset_pct]
    end

    def sl_price_from_entry(entry_price, sl_offset_pct)
      raise ArgumentError, 'entry_price required' if entry_price.nil?

      entry_price.to_f * (1.0 + sl_offset_pct.to_f / 100.0)
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
          tiers: parse_tiers(risk[:trailing_tiers]) || DEFAULT_TIERS,
          peak_drawdown_pct: numeric_or_default(risk[:peak_drawdown_exit_pct], DEFAULT_PEAK_DRAWDOWN_PCT),
          activation_profit_pct: numeric_or_default(risk[:peak_drawdown_activation_profit_pct],
                                                    DEFAULT_ACTIVATION_PROFIT_PCT),
          activation_sl_offset_pct: numeric_or_default(risk[:peak_drawdown_activation_sl_offset_pct],
                                                       DEFAULT_ACTIVATION_SL_OFFSET_PCT)
        }
      end
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
