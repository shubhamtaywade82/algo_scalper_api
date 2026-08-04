# frozen_string_literal: true

module Research
  class NegativeResearch
    # Attribute breakout failure to a primary market mechanism.
    # @param underlying_candles [Array<Hash>] NIFTY candles
    # @param option_candles [Array<Hash>] Option candles
    # @param trade_opp [Hash] Breakout opportunity context
    # @param expansion_ctx [Hash] Option expansion metrics
    # @param regime [Hash] Volatility/trend regime context
    # @return [Symbol] Primary failure reason (:none if trade was successful)
    def self.analyze(underlying_candles, option_candles, trade_opp, expansion_ctx, regime)
      return :none unless trade_opp[:failed]

      trade_opp[:entry_time]
      entry_idx = trade_opp[:entry_index]
      breakout_type = trade_opp[:breakout_type]

      # Find post-entry candle segments
      post_und = underlying_candles[entry_idx..]
      option_candles[entry_idx..]

      # 1. VWAP Reclaim: check if NIFTY crosses back across VWAP
      vwap_reclaimed = false
      post_und.each do |c|
        series = CandleSeries.new(symbol: "NIFTY", interval: "1")
        underlying_candles.first(underlying_candles.index(c) + 1).each do |cand|
          series.add_candle(Candle.new(
            timestamp: cand[:timestamp], open: cand[:open], high: cand[:high], low: cand[:low], close: cand[:close], volume: cand[:volume]
          ))
        end
        vwap = series.current_vwap
        if vwap
          if breakout_type == :bullish && c[:close] < vwap
            vwap_reclaimed = true
            break
          elsif breakout_type == :bearish && c[:close] > vwap
            vwap_reclaimed = true
            break
          end
        end
      end
      return :vwap_reclaimed if vwap_reclaimed

      # 2. Volume Vanished: check if breakout volume dropped by 50% in subsequent 5 minutes
      brk_vol = underlying_candles[entry_idx][:volume]
      if brk_vol.positive?
        post_5m = post_und.first(5)
        avg_post_vol = post_5m.any? ? (post_5m.pluck(:volume).sum.to_f / post_5m.size) : 0.0
        return :volume_vanished if avg_post_vol < (brk_vol * 0.5)
      end

      # 3. Premium Divergence
      return :premium_divergence if expansion_ctx[:exhaustion][:divergence_detected]

      # 4. Exhaustion Score limit reached (PES >= 75)
      return :exhaustion_reached if expansion_ctx[:exhaustion][:peak_exhaustion_score] >= 75

      # 5. Gap Filled: did the gap close back to previous close?
      prev_close = trade_opp[:prev_day_close] || 0.0
      if prev_close.positive?
        gap_filled = post_und.any? do |c|
          breakout_type == :bullish ? (c[:close] <= prev_close) : (c[:close] >= prev_close)
        end
        return :gap_filled if gap_filled
      end

      # 6. Mean Reverting regime: index was classified as range-bound/mean-reverting
      return :mean_reverting_regime if regime[:trend] == :mean_reverting

      # 7. Time Decay / Drift: trade stayed open > 45 mins without hitting target
      time_to_peak = expansion_ctx[:time_to_peak_minutes] || 0
      return :decay_drift if time_to_peak > 45

      :general_reversal
    end
  end
end
