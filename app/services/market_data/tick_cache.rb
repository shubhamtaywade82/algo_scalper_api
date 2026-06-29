# frozen_string_literal: true

module AlgoScalper
  module MarketData
    class TickCache
      def initialize
        @ticks = Concurrent::Map.new
        @callbacks = []
      end

      def put(tick)
        key = "#{tick[:segment]}:#{tick[:security_id]}"
        @ticks[key] = tick.merge(received_at: Time.now)
        @callbacks.each { |cb| cb.call(tick) }
      end

      def get(segment, security_id)
        @ticks["#{segment}:#{security_id}"]
      end

      def ltp(segment, security_id)
        get(segment, security_id)&.dig(:ltp)
      end

      def on_tick(&block)
        @callbacks << block
      end

      def all
        @ticks.values
      end
    end
  end
end