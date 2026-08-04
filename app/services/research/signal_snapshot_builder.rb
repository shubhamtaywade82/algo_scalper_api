# frozen_string_literal: true

module Research
  # Builds a Research::Signal snapshot — the anchor every candidate/backtest
  # row is derived from. Signals can be entered manually (research done on a
  # hypothesis) or lifted from an already-persisted TradingSignal so live
  # signal history can be replayed through the research pipeline.
  class SignalSnapshotBuilder
    DIRECTION_ALIASES = { "avoid" => "no_trade" }.freeze

    class << self
      def build(underlying_symbol:, signal_timestamp:, direction:, spot_price:, strategy_name: nil,
                confidence: nil, reason: {}, metadata: {}, source: "manual", source_record: nil)
        Research::Signal.create!(
          strategy_name: strategy_name,
          underlying_symbol: underlying_symbol.to_s.upcase,
          signal_timestamp: signal_timestamp,
          direction: normalize_direction(direction),
          spot_price: spot_price,
          confidence: confidence,
          reason: reason,
          metadata: metadata,
          source: source,
          source_type: source_record&.class&.name,
          source_id: source_record&.id
        )
      end

      def from_trading_signal(trading_signal, spot_price: nil)
        effective_metadata = trading_signal.effective_metadata || {}
        resolved_spot = spot_price || effective_metadata["spot_price"] || effective_metadata["spot"]
        raise ArgumentError, "spot_price required (not present in TradingSignal##{trading_signal.id} metadata)" if resolved_spot.blank?

        build(
          underlying_symbol: trading_signal.index_key,
          signal_timestamp: trading_signal.signal_timestamp,
          direction: trading_signal.direction,
          spot_price: resolved_spot,
          strategy_name: "trading_signal",
          confidence: trading_signal.confidence_score,
          metadata: effective_metadata,
          source: "trading_signal",
          source_record: trading_signal
        )
      end

      private

      def normalize_direction(direction)
        key = direction.to_s
        DIRECTION_ALIASES.fetch(key, key)
      end
    end
  end
end
