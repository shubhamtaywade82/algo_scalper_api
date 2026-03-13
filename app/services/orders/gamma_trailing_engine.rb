# frozen_string_literal: true

module Orders
  # Gamma-Aware Trailing Engine for weekly index options (NIFTY/SENSEX)
  # Detects gamma expansion via price velocity and acceleration
  class GammaTrailingEngine
    CONFIG = {
      nifty: {
        gamma_trigger: 0.25,
        velocity_threshold: 0.05,
        gamma_trail: 0.65,
        normal_trail: 0.80,
        exhaust_trail: 0.90
      },
      sensex: {
        gamma_trigger: 0.20,
        velocity_threshold: 0.07,
        gamma_trail: 0.60,
        normal_trail: 0.75,
        exhaust_trail: 0.88
      }
    }.freeze

    def initialize(position:, prices:, entry_price: nil, highest_price: nil)
      @position = position
      @prices = Array(prices)
      @entry_price = (entry_price || position.entry_price).to_f
      @highest = (highest_price || position.highest_price || @entry_price).to_f
    end

    def call
      current = @prices.last
      return nil unless current

      update_highest(current)

      cfg = config

      profit = (current - @entry_price) / @entry_price
      velocity = compute_velocity
      acceleration = compute_acceleration

      # State 1 — Early trade (Survival)
      return (@entry_price * 0.88).round(2) if profit < 0.10

      # State 3 — Gamma expansion (Loosen trailing to avoid premature exit)
      if profit > cfg[:gamma_trigger] && acceleration > 0
        return (@highest * cfg[:gamma_trail]).round(2)
      end

      # State 4 — Exhaustion (Tighten trailing aggressively)
      if velocity < cfg[:velocity_threshold]
        return (@highest * cfg[:exhaust_trail]).round(2)
      end

      # State 2 — Normal Trend (Moderate trailing)
      (@highest * cfg[:normal_trail]).round(2)
    end

    private

    def config
      symbol = @position.symbol.to_s.upcase
      if symbol.include?('SENSEX')
        CONFIG[:sensex]
      else
        CONFIG[:nifty]
      end
    end

    def compute_velocity
      return 0.0 if @prices.length < 2
      (@prices[-1] - @prices[-2]) / @prices[-2]
    end

    def compute_acceleration
      return 0.0 if @prices.length < 3

      v1 = (@prices[-2] - @prices[-3]) / @prices[-3]
      v2 = (@prices[-1] - @prices[-2]) / @prices[-2]

      v2 - v1
    end

    def update_highest(price)
      if price > @highest
        @highest = price
        # highest_price is a store_accessor on meta
        if @position.respond_to?(:update_columns)
          meta = (@position.meta || {}).merge('highest_price' => @highest)
          @position.update_columns(meta: meta)
        elsif @position.respond_to?(:meta=)
          @position.meta = (@position.meta || {}).merge('highest_price' => @highest)
        end
      end
    end
  end
end
