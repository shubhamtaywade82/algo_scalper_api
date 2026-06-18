# frozen_string_literal: true

module Positions
  module TrailingConfig
    DEFAULT_PEAK_DRAWDOWN_PCT = 0.05 # 5% in DECIMAL format
    PEAK_DRAWDOWN_PCT = DEFAULT_PEAK_DRAWDOWN_PCT
    DEFAULT_ACTIVATION_PROFIT_PCT = 0.25 # 25% in DECIMAL format
    DEFAULT_ACTIVATION_SL_OFFSET_PCT = 0.10 # 10% in DECIMAL format
    DEFAULT_TIERS = [
      { threshold_pct: 0.05,   sl_offset_pct: -0.15 },
      { threshold_pct: 0.10,   sl_offset_pct: -0.05 },
      { threshold_pct: 0.15,   sl_offset_pct: 0.0   },
      { threshold_pct: 0.25,   sl_offset_pct: 0.10  },
      { threshold_pct: 0.40,   sl_offset_pct: 0.20  },
      { threshold_pct: 0.60,   sl_offset_pct: 0.30  },
      { threshold_pct: 0.80,   sl_offset_pct: 0.40  },
      { threshold_pct: 1.20,   sl_offset_pct: 0.60  }
    ].freeze

    module_function

    def from(effective_config)
      View.new(extract_risk(effective_config))
    end

    def from_tracker(tracker)
      from(ExitConfigResolver.for(tracker))
    end

    def trailing_mode
      live_view.trailing_mode
    end

    def direct_trailing_enabled?
      live_view.direct_trailing_enabled?
    end

    def direct_trailing_distance_pct
      live_view.direct_trailing_distance_pct
    end

    def direct_trailing_activation_profit_pct
      live_view.direct_trailing_activation_profit_pct
    end

    def direct_trailing_min_sl_offset_pct
      live_view.direct_trailing_min_sl_offset_pct
    end

    def tiers
      live_view.tiers
    end

    def sl_offset_for(profit_pct)
      live_view.sl_offset_for(profit_pct)
    end

    def calculate_direct_trailing_sl(current_price:, entry_price:, current_profit_pct:)
      live_view.calculate_direct_trailing_sl(
        current_price: current_price,
        entry_price: entry_price,
        current_profit_pct: current_profit_pct
      )
    end

    def peak_drawdown_triggered?(peak_profit_pct, current_profit_pct, _capital_deployed: nil)
      live_view.peak_drawdown_triggered?(peak_profit_pct, current_profit_pct, _capital_deployed: _capital_deployed)
    end

    def calculate_tiered_drawdown_threshold(peak_profit_pct)
      live_view.calculate_tiered_drawdown_threshold(peak_profit_pct)
    end

    def peak_drawdown_active?(profit_pct:, current_sl_offset_pct:)
      live_view.peak_drawdown_active?(profit_pct: profit_pct, current_sl_offset_pct: current_sl_offset_pct)
    end

    def sl_price_from_entry(entry_price, sl_offset_pct)
      live_view.sl_price_from_entry(entry_price, sl_offset_pct)
    end

    def calculate_sl_price(entry_price, profit_pct)
      live_view.calculate_sl_price(entry_price, profit_pct)
    end

    # Select drawdown threshold based on peak profit using adaptive tiers.
    def adaptive_drawdown_for_peak(peak_profit_pct, tiers)
      return nil unless tiers.is_a?(Array) && tiers.any?

      peak = peak_profit_pct.to_f
      selected = nil

      tiers.each do |tier|
        min_profit = tier[:min_profit] || tier['min_profit']
        drawdown = tier[:drawdown] || tier['drawdown']
        next unless min_profit && drawdown

        selected = drawdown.to_f if peak >= min_profit.to_f
      end

      selected
    end

    def config
      live_view.to_h
    end

    def reset_config!
      nil
    end

    def live_view
      View.new(fetch_risk_config)
    end

    def extract_risk(effective_config)
      cfg = effective_config || {}
      risk = cfg[:risk] || cfg['risk'] || cfg
      risk.respond_to?(:deep_symbolize_keys) ? risk.deep_symbolize_keys : risk
    rescue StandardError
      {}
    end

    def fetch_risk_config
      AlgoConfig.fetch[:risk] || {}
    rescue StandardError
      {}
    end
  end
end
