# frozen_string_literal: true

module Trading
  # Rule-based SMC entry rules (pullback + sweep + displacement + volume + MTF).
  # Does not place orders — use {Smc::TradingSignalContract} for JSON + persistence.
  class EntryEngine
    Signal = Struct.new(:action, :reason, :sl, :target, :rr)

    MIN_RR = 1.8

    def initialize(structure:, liquidity:, zones:, price:, displacement:, volume:, mtf:)
      @structure = structure
      @liquidity = liquidity
      @zones = zones
      @price = price.to_f
      @disp = displacement
      @vol = volume
      @mtf = mtf
    end

    def call
      return nil unless @mtf.valid
      return nil if @zones[:location] == :equilibrium

      try_bullish || try_bearish
    end

    private

    def try_bullish
      return nil unless bullish_setup?

      sl = @liquidity.level - 5
      tgt = @price + (@disp.range * 1.8)
      rr = risk_reward_bullish(sl, tgt)
      return nil if rr.nil? || rr < MIN_RR

      Signal.new('BUY_CE', 'discount_sweep_disp_vol', sl, tgt, rr)
    end

    def try_bearish
      return nil unless bearish_setup?

      sl = @liquidity.level + 5
      tgt = @price - (@disp.range * 1.8)
      rr = risk_reward_bearish(sl, tgt)
      return nil if rr.nil? || rr < MIN_RR

      Signal.new('BUY_PE', 'premium_sweep_disp_vol', sl, tgt, rr)
    end

    def risk_reward_bullish(sl, tgt)
      den = @price - sl
      return nil if den <= 1e-9

      (tgt - @price) / den
    end

    def risk_reward_bearish(sl, tgt)
      den = sl - @price
      return nil if den <= 1e-9

      (@price - tgt) / den
    end

    def bullish_setup?
      @structure.trend == :bullish &&
        @mtf.bias == :bullish &&
        in_discount? &&
        @liquidity&.type == :sweep_low &&
        @disp.bullish &&
        @vol.spike
    end

    def bearish_setup?
      @structure.trend == :bearish &&
        @mtf.bias == :bearish &&
        in_premium? &&
        @liquidity&.type == :sweep_high &&
        @disp.bearish &&
        @vol.spike
    end

    def in_discount?
      d = @zones[:discount]
      d&.include?(@price)
    end

    def in_premium?
      p = @zones[:premium]
      p&.include?(@price)
    end
  end
end
