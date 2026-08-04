BaseStrategy = Strategies::Base unless defined?(BaseStrategy)

class VwapReversalStrategy < BaseStrategy
  def call(context)
    series = context.candles.call("3m")
    return Signals::Hold.new(reason: "no_candle_data") unless series&.candles&.any?

    rsi_period = (params[:rsi_period] || 14).to_i
    oversold = (params[:rsi_oversold] || 30).to_i
    overbought = (params[:rsi_overbought] || 70).to_i
    band_pct = (params[:vwap_band_pct] || 0.5).to_f

    vwap = series.current_vwap
    return Signals::Hold.new(reason: "vwap_unavailable") if vwap.nil? || vwap.zero?

    rsi = series.rsi(rsi_period)
    return Signals::Hold.new(reason: "rsi_unavailable") if rsi.nil?

    close = series.candles.last.close
    distance_pct = ((close - vwap) / vwap) * 100

    if distance_pct < -band_pct && rsi < oversold
      Signals::BuyCall.new(confidence: 0.6, reason: "vwap_pullback_rsi_oversold")
    elsif distance_pct > band_pct && rsi > overbought
      Signals::BuyPut.new(confidence: 0.6, reason: "vwap_rejection_rsi_overbought")
    else
      Signals::Hold.new(reason: "no_reversal_setup")
    end
  end
end
