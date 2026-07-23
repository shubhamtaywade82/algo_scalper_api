# frozen_string_literal: true

module Research
  # Generates Research::Signal rows from underlying regime state instead of
  # a fixed entry rule (ORB). Checkpoint-based (4 fixed times/day, aligned to
  # Research::ContextClassifier's own time_context bucket boundaries) rather
  # than a continuous per-bar scanner — no cooldown/state-machine needed
  # since checkpoints are already ~2hrs apart.
  class RegimeSignalGenerator
    STRATEGY_NAME = "regime_scan"
    DEFAULT_CHECKPOINT_TIMES = %w[09:45 11:30 13:30 15:00].freeze
    TRENDING_BULLISH = %w[strong_bullish weak_bullish].freeze
    TRENDING_BEARISH = %w[strong_bearish weak_bearish].freeze

    class << self
      def run(symbol:, from_date:, to_date:, checkpoint_times: DEFAULT_CHECKPOINT_TIMES)
        symbol = symbol.to_s.upcase
        from = Date.parse(from_date.to_s)
        to = Date.parse(to_date.to_s)

        (from..to).select { |date| Market::Calendar.trading_day?(date) }.flat_map do |date|
          checkpoint_times.filter_map { |time_str| signal_for(symbol, date, time_str) }
        end
      end

      private

      def signal_for(symbol, date, time_str)
        timestamp = Time.zone.parse("#{date} #{time_str}")
        snapshot = Research::UnderlyingContextSnapshot.at(symbol: symbol, timestamp: timestamp)
        return nil if snapshot.blank? || snapshot["close"].blank?

        direction = direction_for(snapshot["regime"] || {})
        return nil if direction.nil?

        existing = Research::Signal.find_by(
          underlying_symbol: symbol, signal_timestamp: timestamp, strategy_name: STRATEGY_NAME
        )
        return existing if existing

        Research::SignalSnapshotBuilder.build(
          underlying_symbol: symbol, signal_timestamp: timestamp, direction: direction,
          spot_price: snapshot["close"], strategy_name: STRATEGY_NAME,
          metadata: { "regime" => snapshot["regime"], "checkpoint" => time_str }
        )
      rescue StandardError => e
        Rails.logger.error(
          "[Research::RegimeSignalGenerator] #{symbol} #{date} #{time_str} failed: #{e.class}: #{e.message}"
        )
        nil
      end

      def direction_for(regime)
        trend = regime["trend"]
        volatility = regime["volatility_regime"]
        sweep = regime["liquidity_sweep"]

        return "bullish" if TRENDING_BULLISH.include?(trend) && volatility == "expanding"
        return "bearish" if TRENDING_BEARISH.include?(trend) && volatility == "expanding"
        return "bullish" if trend == "neutral" && sweep == "sell_side_sweep"
        return "bearish" if trend == "neutral" && sweep == "buy_side_sweep"

        nil
      end
    end
  end
end
