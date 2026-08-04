# frozen_string_literal: true

class GetMarketContextTool < RubyLLM::Tool
  description "Fetches current price, daily OHLC, standard technical indicators (RSI, MACD, ADX, Supertrend, ATR, Bollinger Bands), and SMC market structure (Order Blocks, Fair Value Gaps, Premium/Discount zones, Liquidity pools) for a given index (e.g., NIFTY, BANKNIFTY, SENSEX)."

  param :index_key, type: :string, description: "The index symbol (e.g., NIFTY, BANKNIFTY, SENSEX)", required: true
  param :interval,  type: :string, description: "Candle interval in minutes (e.g., 1, 5, 15, 60)",   required: false

  def execute(index_key:, interval: "5")
    index_key           = index_key.to_s.upcase
    normalized_interval = interval.to_s.delete_suffix("m").presence || "5"

    index_configs = IndexConfigLoader.load_indices
    index_cfg     = index_configs.find { |idx| idx[:key].to_s.upcase == index_key }
    return { error: "Unknown index: #{index_key}" } unless index_cfg

    security_id = index_cfg[:security_id] || index_cfg[:sid]
    segment     = index_cfg[:segment]
    return { error: "Missing security_id or segment for #{index_key}" } unless security_id && segment

    instrument = Instrument.find_by_sid_and_segment(
      security_id: security_id,
      segment_code: segment,
      symbol_name: index_key
    )
    return { error: "Instrument not found for #{index_key}" } unless instrument

    ltp    = instrument.ltp
    series = instrument.candles(interval: normalized_interval)
    return { error: "No candle data available for #{index_key}" } unless series&.candles&.any?

    indicators = build_indicators(series)
    smc_data   = build_smc(series)

    latest = series.candles.last
    ohlc   = if latest
  {
      open: latest.open.to_f, high: latest.high.to_f,
      low: latest.low.to_f, close: latest.close.to_f,
      volume: latest.volume.to_i
    }
             else
  {}
             end

    { index: index_key, ltp: ltp.to_f, ohlc: ohlc, interval: normalized_interval,
      indicators: indicators, smc: smc_data, timestamp: Time.current }
  rescue StandardError => e
    { error: e.message }
  end

  private

  def build_indicators(series)
    macd_res = series.macd(12, 26, 9)
    bb_res   = series.bollinger_bands(period: 20, std_dev: 2.0)
    {
      rsi: series.rsi(14),
      macd: macd_res ? { macd: macd_res[0], signal: macd_res[1], histogram: macd_res[2] } : nil,
      adx: series.adx(14),
      supertrend: series.supertrend_signal,
      atr: series.atr(14),
      bollinger_bands: bb_res ? { upper: bb_res[:upper], middle: bb_res[:middle], lower: bb_res[:lower] } : nil
    }
  rescue StandardError => e
    Rails.logger.warn("[GetMarketContextTool] indicators error: #{e.message}")
    {}
  end

  def build_smc(series)
    Smc::Context.new(series).to_h
  rescue StandardError => e
    Rails.logger.warn("[GetMarketContextTool] SMC error: #{e.message}")
    {}
  end
end
