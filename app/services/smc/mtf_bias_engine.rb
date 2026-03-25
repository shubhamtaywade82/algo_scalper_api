# frozen_string_literal: true

module Smc
  # 15m structure trend must match 5m for directional bias.
  class MtfBiasEngine
    Result = Struct.new(:bias, :valid)

    def initialize(series_5m:, series_15m:)
      @s5 = series_5m
      @s15 = series_15m
    end

    def call
      s15 = Smc::StructureEngine.new(@s15).call
      s5 = Smc::StructureEngine.new(@s5).call

      bias = if s15.trend == :bullish && s5.trend == :bullish
               :bullish
             elsif s15.trend == :bearish && s5.trend == :bearish
               :bearish
             else
               :neutral
             end

      Result.new(bias: bias, valid: bias != :neutral)
    end
  end
end
