# frozen_string_literal: true

module Ai
  module Agents
    # Blueprint §8.3 "Market Analysis Agent" — multi-timeframe regime
    # detection with confidence scoring. Wraps the existing deterministic
    # MarketContext::RegimeComposer (structure/volatility/participation ->
    # conviction score) rather than making an LLM call on every cycle, so
    # this stays fast and reliable enough to run frequently; publishes
    # :regime_change for observability only (no subscriber may act on it
    # with trading authority — see AgentSupervisor).
    class MarketAnalysisAgent < BaseAgent
      DEFAULT_INTERVAL = '5'

      private

      def perform(index_key:, interval: DEFAULT_INTERVAL)
        index_key = index_key.to_s.upcase
        instrument = resolve_instrument(index_key)
        return no_data_result(index_key, 'no instrument configured') unless instrument

        series = instrument.candle_series(interval: interval)
        return no_data_result(index_key, 'no candle series available') if series.blank? || series.candles.empty?

        snapshot = MarketContext::RegimeComposer.new(series: series, index_key: index_key).call
        confidence = (snapshot.conviction_score.to_f / 100.0).round(4)

        publish(:regime_change, {
                  index_key: index_key,
                  structure: snapshot.structure,
                  conviction_score: snapshot.conviction_score,
                  at: Time.current
                })

        {
          decision_type: 'market_state',
          confidence: confidence,
          published_event: 'regime_change',
          output: {
            index_key: index_key,
            structure: snapshot.structure,
            strength: snapshot.strength,
            volatility_state: snapshot.volatility_state,
            participation: snapshot.participation,
            conviction_score: snapshot.conviction_score,
            legacy_regime: snapshot.legacy_regime
          }
        }
      end

      def resolve_instrument(index_key)
        idx_cfg = IndexConfigLoader.load_indices.find { |c| c[:key].to_s.upcase == index_key }
        return nil unless idx_cfg

        IndexInstrumentCache.instance.get_or_fetch(idx_cfg)
      end

      def no_data_result(index_key, reason)
        { decision_type: 'market_state', confidence: 0.0, output: { index_key: index_key, note: reason } }
      end
    end
  end
end
