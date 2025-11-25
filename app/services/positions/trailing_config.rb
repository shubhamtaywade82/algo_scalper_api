# frozen_string_literal: true

module Positions
  module TrailingConfig
    PEAK_DRAWDOWN_PCT = 5.0.freeze
    PEAK_DRAWDOWN_ACTIVATION_PCT = 25.0.freeze
    PEAK_DRAWDOWN_MIN_SL_OFFSET_PCT = 10.0.freeze

    TIERS = [
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
      TIERS.dup
    end

    def sl_offset_for(profit_pct)
      return nil if profit_pct.nil?

      profit_value = profit_pct.to_f
      TIERS.reverse_each do |tier|
        return tier[:sl_offset_pct] if profit_value >= tier[:threshold_pct]
      end
      nil
    end

    def peak_drawdown_triggered?(peak_profit_pct, current_profit_pct)
      return false unless peak_profit_pct && current_profit_pct

      (peak_profit_pct - current_profit_pct) >= PEAK_DRAWDOWN_PCT
    end

    def peak_drawdown_active?(profit_pct:, current_sl_offset_pct:)
      profit_pct.to_f >= PEAK_DRAWDOWN_ACTIVATION_PCT &&
        current_sl_offset_pct.to_f >= PEAK_DRAWDOWN_MIN_SL_OFFSET_PCT
    end

    def sl_price_from_entry(entry_price, sl_offset_pct)
      raise ArgumentError, 'entry_price required' if entry_price.nil?

      entry_price.to_f * (1.0 + sl_offset_pct.to_f / 100.0)
    end

    def calculate_sl_price(entry_price, profit_pct)
      sl_offset_pct = sl_offset_for(profit_pct)
      return nil unless sl_offset_pct
      (sl_price_from_entry(entry_price, sl_offset_pct)).round(2)
    end
  end
end
