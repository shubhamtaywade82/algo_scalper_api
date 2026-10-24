# frozen_string_literal: true

module Orders
  class TrailingEngine
    # Define parameters as decimals (5% = 0.05, etc.)
    NIFTY = {
      early_trigger: 0.05,        # +5%
      breakeven_trigger: 0.10,    # +10%
      activate_trigger: 0.20,     # +20%
      early_sl_offset: -0.12,     # -12%
      trail_distance: 0.22        # 22% trailing gap
    }.freeze

    SENSEX = {
      early_trigger: 0.06,        # +6%
      breakeven_trigger: 0.12,    # +12%
      activate_trigger: 0.18,     # +18%
      early_sl_offset: -0.10,     # -10%
      trail_distance: 0.30        # 30% trailing gap
    }.freeze

    def initialize(position:, ltp:, highest_price: nil)
      @position = position
      @entry_price = position.entry_price.to_f
      @ltp = ltp.to_f
      @highest = (highest_price || position.highest_price || @entry_price).to_f
      @config = load_config(position.symbol.to_s)
    end

    # Calculate and return the new stop-loss price (or nil if no change)
    # Does NOT update the database.
    def calculate_sl
      profit_pct = (@ltp - @entry_price) / @entry_price

      # Phase 1: initial slack (Survival)
      if profit_pct >= @config[:early_trigger] && profit_pct < @config[:breakeven_trigger]
        return (@entry_price * (1 + @config[:early_sl_offset])).round(2)
      end

      # Phase 2: breakeven lock (Capital protection)
      if profit_pct >= @config[:breakeven_trigger] && profit_pct < @config[:activate_trigger]
        return @entry_price.round(2)
      end

      # Phase 3: high-watermark trailing (Profit locking)
      if profit_pct >= @config[:activate_trigger]
        # Use provided highest price or tracked highest price
        effective_highest = [@ltp, @highest].max
        return (effective_highest * (1 - @config[:trail_distance])).round(2)
      end

      nil # no stop change
    end

    # Standard call method for backwards compatibility, updates HWM in DB
    def call
      update_highest_price
      calculate_sl
    end

    private

    def load_config(symbol)
      symbol = symbol.upcase
      key = if symbol.include?('SENSEX')
              :sensex
            elsif symbol.include?('BANKNIFTY')
              :banknifty
            else
              :nifty
            end

      # Try to load from AlgoConfig
      yml = begin
        AlgoConfig.fetch.dig(:risk, :institutional_trailing)
      rescue StandardError
        nil
      end

      raw = yml&.[](key) || (key == :sensex ? SENSEX : NIFTY)

      # Handle BANKNIFTY default if not in constants
      if key == :banknifty && !yml&.[](key)
        raw = {
          early_trigger: 0.06,
          early_sl_offset: -0.15,
          breakeven_trigger: 0.18,
          activate_trigger: 0.25,
          trail_distance: 0.35
        }
      end

      # Ensure keys are symbols and values are floats
      {
        early_trigger: (raw[:early_trigger] || raw['early_trigger']).to_f,
        early_sl_offset: (raw[:early_sl_offset] || raw['early_sl_offset']).to_f,
        breakeven_trigger: (raw[:breakeven_trigger] || raw['breakeven_trigger']).to_f,
        activate_trigger: (raw[:activate_trigger] || raw['activate_trigger']).to_f,
        trail_distance: (raw[:trailing_distance] || raw['trailing_distance'] || raw[:trail_distance] || raw['trail_distance']).to_f
      }
    end

    # Update the highest observed price in the position record
    def update_highest_price
      if @ltp > @highest
        @highest = @ltp
        @position.update!(highest_price: @highest)
      end
    end
  end
end
