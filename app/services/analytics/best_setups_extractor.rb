# frozen_string_literal: true

module Analytics
  class BestSetupsExtractor
    TOP_PERCENT = 0.2

    def initialize(trades)
      @trades = trades
    end

    def call
      return {} if @trades.empty?

      sorted = @trades.sort_by { |t| -t[:pnl] }
      top_n = [(sorted.size * TOP_PERCENT).ceil, 1].max
      best = sorted.first(top_n)

      {
        count: best.size,
        avg_pnl: avg(best),
        common: common_features(best)
      }
    end

    private

    def avg(trades)
      trades.sum { |t| t[:pnl] } / trades.size.to_f
    end

    def common_features(trades)
      {
        regime: mode(trades.map { |t| t[:context].regime }),
        session: mode(trades.map { |t| t[:context].session }),
        day_type: mode(trades.map { |t| t[:context].day_type }),
        score_avg: (trades.sum { |t| t[:context].score } / trades.size.to_f).round(2)
      }
    end

    def mode(arr)
      arr.group_by(&:itself).max_by { |_k, v| v.size }&.first
    end
  end
end
