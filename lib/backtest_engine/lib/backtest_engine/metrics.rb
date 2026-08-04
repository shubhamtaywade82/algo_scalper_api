# frozen_string_literal: true

module BacktestEngine
  class Metrics
    Trade = Struct.new(
      :entry_time,
      :exit_time,
      :side,
      :option_type,
      :strike,
      :entry_price,
      :exit_price,
      :pnl,
      :pnl_pct,
      :day_type,
      :session,
      :regime,
      :mfe,
      :mae,
      :exit_efficiency,
      :trend_capture_pct,
      :exit_reason
    )

    attr_reader :trades, :decision_counts, :skip_reasons

    def initialize
      @trades = []
      @decision_counts = Hash.new(0)
      @skip_reasons = Hash.new(0)
    end

    def record_trade(trade)
      return if trade.nil?

      if trade.is_a?(Numeric)
        trades << Trade.new(pnl: trade.to_f)
        return
      end

      trades << trade
    end

    def record_decision(action:, day_type: nil, session: nil, regime: nil, reason: nil)
      key = [action&.to_sym, day_type, session, regime].freeze
      decision_counts[key] += 1

      return unless action&.to_sym == :skip && reason

      skip_reasons[reason.to_s] += 1
    end

    def total_pnl
      trades.sum { |t| t.pnl.to_f }
    end

    def average_pnl
      return 0.0 if trades.empty?

      total_pnl / trades.size
    end

    def winning_rate
      return 0.0 if trades.empty?

      wins = trades.count { |t| t.pnl.to_f.positive? }
      (wins.to_f / trades.size) * 100.0
    end

    def trades_by(key)
      unless Trade.members.include?(key.to_sym)
        raise ArgumentError, "Unknown trade field: #{key}. Supported: #{Trade.members.join(', ')}"
      end

      trades.group_by { |t| t.public_send(key) }
    end

    # Backwards compatibility for older callers/tests
    def trade_pnls
      trades.map { |t| t.pnl.to_f }
    end
  end
end

