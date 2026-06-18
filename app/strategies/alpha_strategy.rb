# frozen_string_literal: true

class AlphaStrategy
  attr_reader :index_key, :signal_score, :confidence, :metadata

  INDEX_CONFIG = {
    nifty:     { security_id: "13", exchange_segment: "IDX_I", lot_size: 75,  tick_step: 50,  min_sl_pct: 0.010, max_otm_pct: 0.015 },
    banknifty: { security_id: "25", exchange_segment: "IDX_I", lot_size: 30,  tick_step: 100, min_sl_pct: 0.012, max_otm_pct: 0.020 },
    sensex:    { security_id: "51", exchange_segment: "IDX_I", lot_size: 10,  tick_step: 100, min_sl_pct: 0.010, max_otm_pct: 0.015 }
  }.freeze
  def initialize(index_key:)
    @index_key = index_key.to_sym
    @config = INDEX_CONFIG[@index_key]
    @signal_score = 0.0
    @confidence = 0.0
    @metadata = {}
  end

  def scan
    raise NotImplementedError
  end

  def enabled?
    AlgoConfig.fetch[:alpha_strategies]&.fetch(@index_key.to_s, {})&.fetch(self.class.name.underscore, true) != false
  end

  protected

  def instrument
    @instrument ||= Instrument.find_by(symbol_name: @index_key.to_s.upcase, segment: 'index')
  end

  def underlying_ltp
    instrument&.resolve_ltp(segment: @config[:exchange_segment], security_id: @config[:security_id]) || fetch_cached_ltp
  end

  def fetch_cached_ltp
    Rails.cache.read("ltp:#{@config[:security_id]}") || instrument&.ltp
  end

  def atm_strike(ltp)
    step = @config[:tick_step]
    (ltp.to_f / step).round * step
  end

  def nearest_expiry
    instrument&.expiry_list&.first
  end

  # Shares the cache CandlesController populates — Signal::Engine, the dashboard,
  # and this scanner were each hitting DhanHQ's intraday endpoint independently
  # every cycle, tripping DH-904 rate limits and silently returning [] on every
  # scan (AlphaSignal/positions count stayed at zero despite the job "finishing").
  def fetch_historical_bars(interval:, count: 20)
    return [] unless instrument

    days = [count, 1].max
    to_date = Market::Calendar.today_or_last_trading_day.to_s
    from_date = Market::Calendar.trading_days_ago(days).to_s
    cache_key = "candles/#{@config[:security_id]}/#{interval}/#{days}d/#{to_date}"
    Rails.cache.fetch(cache_key, expires_in: bars_cache_ttl(interval)) do
      DhanHQ::Models::HistoricalData.intraday(
        security_id: @config[:security_id],
        exchange_segment: @config[:exchange_segment],
        instrument: DhanHQ::Constants::InstrumentType::INDEX,
        interval: interval.to_s,
        from_date: from_date,
        to_date: to_date
      )
    end
  rescue StandardError => e
    Rails.logger.error "[AlphaStrategy] Historical data fetch failed for #{@index_key}: #{e.message}"
    []
  end

  def bars_cache_ttl(interval)
    { '1' => 30.seconds, '5' => 1.minute, '15' => 3.minutes, '25' => 5.minutes, '60' => 10.minutes }
      .fetch(interval.to_s, 1.minute)
  end

  def calculate_atr(bars, period: 14)
    return 0.0 if bars.size < period + 1

    trs = bars.each_cons(2).map do |prev, curr|
      h = curr[:high]  || curr['high']  || 0
      l = curr[:low]   || curr['low']   || 0
      c = prev[:close] || prev['close'] || 0
      [(h - l), (h - c).abs, (l - c).abs].max
    end

    (trs.sum / trs.size.to_f).round(2)
  end

  def iv_percentile(current_iv:, history:)
    return 50.0 if history.blank? || current_iv.blank?
    sorted = history.sort
    rank = sorted.index { |v| v >= current_iv } || sorted.size
    (rank.to_f / sorted.size * 100).round(2)
  end

  def build_signal(direction:, strike:, option_type:, entry_price:, stop_loss:, target:, trailing_jump: 0, confidence:, alpha_source:, iv_context: {})
    ltp = underlying_ltp
    # Sanity check: Ensure strike is not too far from current LTP
    max_dist = ltp * (@config[:max_otm_pct] || 0.015)
    if (strike - ltp).abs > max_dist
      Rails.logger.warn "[AlphaStrategy] Signal rejected: Strike #{strike} is too far from LTP #{ltp}"
      return nil
    end

    {
      index_key: @index_key,
      direction: direction,
      strike: strike,
      option_type: option_type,
      expiry: nearest_expiry,
      entry_price: entry_price.to_f,
      underlying_ltp: ltp.to_f,
      stop_loss: stop_loss.to_f,
      target: target.to_f,
      trailing_jump: trailing_jump.to_f,
      confidence: confidence.round(2),
      alpha_source: alpha_source,
      iv_context: iv_context,
      timestamp: Time.current.iso8601,
      instrument_id: instrument&.id,
      underlying_security_id: @config[:security_id],
      lot_size: @config[:lot_size]
    }
  end
end
