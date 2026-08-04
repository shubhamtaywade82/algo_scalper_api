# frozen_string_literal: true

class GetOptionChainTool < RubyLLM::Tool
  description "Fetches the current option chain contracts (CE/PE), strike prices, current premiums (LTP), bid/ask spreads, Greeks (Delta, Gamma, Theta, Vega), Implied Volatility (IV), and Open Interest (OI) for a given index based on a trading bias (bullish/bearish)."

  param :index_key, type: :string, description: "The index symbol (e.g., NIFTY, BANKNIFTY, SENSEX)", required: true
  param :direction, type: :string, description: "Trading bias to filter candidates ('bullish' or 'bearish')", required: false
  param :limit, type: :integer, description: "Maximum number of option candidate contracts to return", required: false

  def execute(index_key:, direction: "bullish", limit: 5)
    index_key = index_key.to_s.upcase
    dir_sym = direction.to_s.downcase == "bearish" ? :bearish : :bullish
    limit_val = limit ? limit.to_i : 5

    begin
      analyzer = Options::DerivativeChainAnalyzer.new(index_key: index_key)
      candidates = analyzer.select_candidates(limit: limit_val, direction: dir_sym)

      {
        index: index_key,
        direction: dir_sym.to_s,
        candidates: candidates.map do |c|
          {
            selected_contract: c[:derivative]&.then { |d| d.symbol_name || d.symbol }.to_s,
            strike: c[:strike],
            type: c[:type],
            ltp: c[:ltp],
            bid: c[:bid],
            ask: c[:ask],
            spread: c[:spread],
            iv: c[:iv],
            oi: c[:oi],
            oi_change: c[:oi_change],
            volume: c[:volume],
            delta: c[:delta],
            gamma: c[:gamma],
            theta: c[:theta],
            vega: c[:vega],
            score: c[:score],
            reason: c[:reason]
          }
        end,
        timestamp: Time.current
      }
    rescue StandardError => e
      { error: "Failed to fetch option chain: #{e.message}" }
    end
  end
end
