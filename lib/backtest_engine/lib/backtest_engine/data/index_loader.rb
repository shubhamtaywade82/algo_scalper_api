module BacktestEngine
  module Data
    class IndexLoader
      NIFTY_SECURITY_ID = "13"

      def self.fetch(interval:, from:, to:, security_id: NIFTY_SECURITY_ID)
        require "dhan_hq"

        raw = DhanHQ::Models::HistoricalData.intraday(
          security_id: security_id.to_s,
          exchange_segment: "IDX_I",
          instrument: "INDEX",
          interval: interval.to_s,
          from_date: from,
          to_date: to
        )

        CandleNormalizer.normalize(raw)
      end
    end
  end
end

