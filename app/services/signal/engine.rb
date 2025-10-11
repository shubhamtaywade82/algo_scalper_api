# frozen_string_literal: true

module Signal
  class Engine
    class << self
      def run_for(index_cfg)
        timeframe = AlgoConfig.fetch.dig(:signals, :timeframe)

        candles = DhanHQ::Models::MarketData.intraday_ohlc(
          exchange_segment: index_cfg[:segment],
          security_id: index_cfg[:sid],
          timeframe: timeframe,
          limit: 400
        )
        return if candles.blank?

        supertrend_cfg = AlgoConfig.fetch.dig(:signals, :supertrend)
        return unless supertrend_cfg
        st = Indicators::Supertrend.call(candles, **supertrend_cfg)
        adx = Indicators::Calculator.adx(candles)

        direction = decide_direction(st, adx)
        return if direction == :avoid

        picks = Options::ChainAnalyzer.pick_strikes(index_cfg: index_cfg, direction: direction)
        picks.each do |pick|
          Entries::EntryGuard.try_enter(index_cfg: index_cfg, pick: pick, direction: direction)
        end
      rescue StandardError => e
        Rails.logger.error("[Signal] #{index_cfg[:key]} #{e.class} #{e.message}")
      end

      def decide_direction(supertrend, adx)
        min_strength = AlgoConfig.fetch.dig(:signals, :adx, :min_strength).to_f
        return :avoid if adx[:value].to_f < min_strength

        case supertrend[:trend]
        when :up
          :bullish
        when :down
          :bearish
        else
          :avoid
        end
      end
    end
  end
end
