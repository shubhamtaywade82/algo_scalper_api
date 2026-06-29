# frozen_string_literal: true

module AlgoScalper
  module MarketData
    class DepthCache
      def initialize
        @depth = Concurrent::Map.new
        @callbacks = []
      end

      def put(depth)
        key = "#{depth[:segment]}:#{depth[:security_id]}"
        @depth[key] = depth.merge(received_at: Time.now)
        @callbacks.each { |cb| cb.call(depth) }
      end

      def get(segment, security_id)
        @depth["#{segment}:#{security_id}"]
      end

      def on_update(&block)
        @callbacks << block
      end

      def spread_pct(segment, security_id)
        d = get(segment, security_id)
        return nil unless d && d[:best_bid] && d[:best_ask]

        ((d[:best_ask] - d[:best_bid]) / d[:best_ask]) * 100
      end

      def bid_ask_imbalance(segment, security_id)
        d = get(segment, security_id)
        return nil unless d && d[:bids] && d[:asks]

        bid_vol = d[:bids].sum { |b| b[:quantity] }
        ask_vol = d[:asks].sum { |a| a[:quantity] }
        return 1.0 if (bid_vol + ask_vol).zero?

        bid_vol.to_f / (bid_vol + ask_vol)
      end
    end
  end
end