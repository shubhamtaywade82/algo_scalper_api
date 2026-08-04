# frozen_string_literal: true

module BacktestEngine
  module Market
    class RegimeState
      DEFAULT_STABILITY_CANDLES = 3
      DEFAULT_COOLDOWN_CANDLES = 4

      def initialize(stability_candles: DEFAULT_STABILITY_CANDLES, cooldown_candles: DEFAULT_COOLDOWN_CANDLES)
        @stability_candles = stability_candles
        @cooldown_candles = cooldown_candles
        @last_direction = nil
        @same_count = 0
        @last_flip_at = nil
        @cooldown_until = nil
      end

      def update(candle_index, direction)
        direction = direction.to_sym if direction.respond_to?(:to_sym)
        direction = nil if direction == :range

        if direction != @last_direction
          @last_flip_at = candle_index
          @cooldown_until = @last_direction.nil? ? nil : candle_index + @cooldown_candles
          @last_direction = direction
          @same_count = 1
        else
          @same_count += 1
        end

        stable = (@same_count >= @stability_candles) && !direction.nil?
        in_cooldown = @cooldown_until && candle_index < @cooldown_until
        allowed = stable && !in_cooldown

        {
          direction: @last_direction,
          stable: stable,
          allowed_to_trade: allowed,
          same_count: @same_count
        }
      end
    end
  end
end
