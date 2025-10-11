# frozen_string_literal: true

module Options
  class ChainAnalyzer
    class << self
      def pick_strikes(index_cfg:, direction:)
        chain = DhanHQ::Models::Options.chain(
          index: index_cfg[:key],
          expiry: AlgoConfig.fetch.dig(:option_chain, :expiry)
        )
        return [] unless chain

        atm_price = chain[:atm_price]
        return [] unless atm_price

        side = direction == :bullish ? :ce : :pe
        window = atm_price.to_f * (AlgoConfig.fetch.dig(:option_chain, :atm_window_pct).to_f / 100.0)

        legs = filter_and_rank(chain[:legs], atm: atm_price, side: side, window: window)
        legs.first(2).map do |leg|
          leg.slice(:segment, :security_id, :symbol, :ltp, :iv, :oi, :spread)
        end
      end

      def filter_and_rank(legs, atm:, side:, window:)
        return [] unless legs

        min_iv = AlgoConfig.fetch.dig(:option_chain, :min_iv).to_f
        max_iv = AlgoConfig.fetch.dig(:option_chain, :max_iv).to_f
        min_oi = AlgoConfig.fetch.dig(:option_chain, :min_oi).to_i
        max_spread_pct = AlgoConfig.fetch.dig(:option_chain, :max_spread_pct).to_f

        legs.select do |leg|
          leg[:type] == side &&
            (leg[:strike].to_f - atm.to_f).abs <= window &&
            leg[:iv].to_f.between?(min_iv, max_iv) &&
            leg[:oi].to_i >= min_oi &&
            leg.fetch(:spread_pct, 0.0).to_f <= max_spread_pct
        end.sort_by { |leg| [-leg[:oi].to_i, leg.fetch(:spread_pct, 0.0).to_f] }
      end
    end
  end
end
