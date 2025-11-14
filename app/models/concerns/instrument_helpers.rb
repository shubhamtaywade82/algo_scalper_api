# frozen_string_literal: true

require 'bigdecimal'
require 'date'

module InstrumentHelpers
  extend ActiveSupport::Concern
  include CandleExtension

  included do
    enum :exchange, { nse: 'NSE', bse: 'BSE', mcx: 'MCX' }
    enum :segment, { index: 'I', equity: 'E', currency: 'C', derivatives: 'D', commodity: 'M' }, prefix: true
    enum :instrument_code, {
      index: 'INDEX',
      futures_index: 'FUTIDX',
      options_index: 'OPTIDX',
      equity: 'EQUITY',
      futures_stock: 'FUTSTK',
      options_stock: 'OPTSTK',
      futures_currency: 'FUTCUR',
      options_currency: 'OPTCUR',
      futures_commodity: 'FUTCOM',
      options_commodity: 'OPTFUT'
    }, prefix: true

    scope :nse, -> { where(exchange: 'NSE') }
    scope :bse, -> { where(exchange: 'BSE') }

    def subscribe
      Live::WsHub.instance.subscribe(seg: exchange_segment, sid: security_id.to_s)
      # Rails.logger.info("Subscribed #{self.class.name} #{security_id} to WS feed.")
      true
    rescue StandardError => e
      Rails.logger.error("Failed to subscribe #{self.class.name} #{security_id}: #{e.message}")
      false
    end

    def unsubscribe
      Live::WsHub.instance.unsubscribe(seg: exchange_segment, sid: security_id.to_s)
      # Rails.logger.info("Unsubscribed #{self.class.name} #{security_id} from WS feed.")
      true
    rescue StandardError => e
      Rails.logger.error("Failed to unsubscribe #{self.class.name} #{security_id}: #{e.message}")
      false
    end
  end

  def ltp
    # Priority: WebSocket TickCache > REST API
    hub = Live::MarketFeedHub.instance

    # Check WebSocket cache first
    if hub.running? && hub.connected?
      cached_ltp = ws_ltp
      return cached_ltp if cached_ltp.present? && cached_ltp.to_f.positive?
    end

    # Fallback to REST API
    fetch_ltp_from_api
  rescue StandardError => e
    # Suppress 429 rate limit errors (expected during high load)
    error_msg = e.message.to_s
    is_rate_limit = error_msg.include?('429') || error_msg.include?('rate limit') || error_msg.include?('Rate limit')
    Rails.logger.error("Failed to fetch LTP for #{self.class.name} #{security_id}: #{error_msg}") unless is_rate_limit
    nil
  end

  def latest_ltp
    price = ws_ltp || quote_ltp || fetch_ltp_from_api
    price.present? ? BigDecimal(price.to_s) : nil
  end

  # Resolves an actionable LTP for downstream order placement.
  # Priority order:
  # 1. `meta[:ltp]` if provided
  # 2. WebSocket tick cache via Live::RedisPnlCache (if WS connected and fresh)
  # 3. REST API via instrument/derivative object (fallback when WS unavailable)
  # 4. nil (if all methods fail)
  #
  # @param segment [String]
  # @param security_id [String, Integer]
  # @param meta [Hash]
  # @param fallback_to_api [Boolean] Whether to fallback to REST API if WS unavailable
  # @return [BigDecimal, nil]
  def resolve_ltp(segment:, security_id:, meta: {}, fallback_to_api: true)
    ltp_from_meta = meta&.dig(:ltp)
    return BigDecimal(ltp_from_meta.to_s) if ltp_from_meta.present?

    # Try WebSocket cache if hub is connected and ticks are fresh
    hub = Live::MarketFeedHub.instance
    if hub.running? && hub.connected?
      tick = Live::RedisPnlCache.instance.fetch_tick(segment: segment, security_id: security_id)
      return BigDecimal(tick[:ltp].to_s) if tick&.dig(:ltp)
    end

    # Fallback to REST API when WebSocket unavailable or cache miss
    if fallback_to_api
      api_ltp = fetch_ltp_from_api_for_segment(segment: segment, security_id: security_id)
      return BigDecimal(api_ltp.to_s) if api_ltp.present?
    end

    nil
  rescue StandardError => e
    Rails.logger.error("Failed to resolve LTP for #{segment}:#{security_id} - #{e.message}")
    nil
  end

  # Fetches LTP from REST API for a specific segment and security_id
  # Prioritizes WebSocket/TickCache to avoid API rate limits
  # @param segment [String] Exchange segment (e.g., "IDX_I", "NSE_FNO")
  # @param security_id [String, Integer] Security ID
  # @return [Numeric, nil]
  def fetch_ltp_from_api_for_segment(segment:, security_id:)
    hub = Live::MarketFeedHub.instance

    # Strategy 1: Check WebSocket TickCache first (fastest, no API rate limits)
    if hub.running? && hub.connected?
      cached_ltp = Live::TickCache.ltp(segment, security_id)
      if cached_ltp.present? && cached_ltp.to_f.positive?
        Rails.logger.debug { "[InstrumentHelpers] Got LTP from TickCache for #{segment}:#{security_id}: ₹#{cached_ltp}" }
        return cached_ltp.to_f
      end

      # If not in cache, try subscribing and waiting briefly for a tick
      begin
        hub.subscribe(segment: segment, security_id: security_id)
        # Wait up to 200ms for tick to arrive
        4.times do
          sleep(0.05) # 50ms intervals
          cached_ltp = Live::TickCache.ltp(segment, security_id)
          if cached_ltp.present? && cached_ltp.to_f.positive?
            Rails.logger.debug { "[InstrumentHelpers] Got LTP from TickCache after subscription for #{segment}:#{security_id}: ₹#{cached_ltp}" }
            return cached_ltp.to_f
          end
        end
      rescue StandardError => e
        Rails.logger.debug { "[InstrumentHelpers] WebSocket subscription failed for #{segment}:#{security_id}: #{e.message}, falling back to API" }
      end
    end

    # Strategy 2: REST API fallback (only if WebSocket unavailable or no tick received)
    segment_enum = segment.to_s.upcase
    payload = { segment_enum => [security_id.to_i] }
    response = DhanHQ::Models::MarketFeed.ltp(payload)

    return nil unless response.is_a?(Hash) && response['status'] == 'success'

    data = response.dig('data', segment_enum, security_id.to_s)
    data&.dig('last_price')
  rescue StandardError => e
    # Suppress 429 rate limit errors (expected during high load)
    error_msg = e.message.to_s
    is_rate_limit = error_msg.include?('429') || error_msg.include?('rate limit') || error_msg.include?('Rate limit')
    unless is_rate_limit
      Rails.logger.error("Failed to fetch LTP from API for #{self.class.name} #{security_id}: #{error_msg}")
    end
    nil
  end

  # Generates a short, gateway-safe client order identifier.
  # @param side [Symbol, String]
  # @param security_id [String]
  # @return [String]
  def default_client_order_id(side:, security_id:)
    ts = Time.current.to_i.to_s[-6..]
    "AS-#{side.to_s.upcase[0..2]}-#{security_id}-#{ts}"
  end

  # Ensures the WebSocket hub is actively streaming ticks for the instrument.
  # Raises if the hub is offline to avoid blind entries.
  # @param segment [String]
  # @param security_id [String]
  # @return [true]
  def ensure_ws_subscription!(segment:, security_id:)
    hub = Live::WsHub.instance
    unless hub.running?
      Rails.logger.error('[InstrumentHelpers] WebSocket hub is not running. Aborting subscription.')
      raise 'WebSocket hub not running'
    end

    hub.subscribe(seg: segment, sid: security_id.to_s)
    true
  end

  # Creates a PositionTracker immediately after order placement and primes caches.
  # @param instrument [Instrument]
  # @param order_no [String]
  # @param segment [String]
  # @param security_id [String]
  # @param side [String]
  # @param qty [Integer]
  # @param entry_price [Numeric]
  # @param symbol [String]
  # @param index_key [String, nil]
  # @return [PositionTracker]
  def after_order_track!(instrument:, order_no:, segment:, security_id:, side:, qty:, entry_price:, symbol:,
                         index_key: nil)
    # Determine watchable: if self is a Derivative, use self; otherwise use instrument
    watchable = is_a?(Derivative) ? self : instrument

    tracker = PositionTracker.build_or_average!(
      watchable: watchable,
      instrument: watchable.is_a?(Derivative) ? watchable.instrument : watchable, # Backward compatibility
      order_no: order_no,
      security_id: security_id.to_s,
      symbol: symbol,
      segment: segment,
      side: side,
      status: PositionTracker::STATUSES[:active],
      quantity: qty.to_i,
      entry_price: BigDecimal(entry_price.to_s),
      meta: index_key ? { 'index_key' => index_key } : {}
    )

    ensure_ws_subscription!(segment: segment, security_id: security_id)
    Live::RedisPnlCache.instance.clear_tick(segment: segment, security_id: security_id.to_s)

    tracker
  end

  def quote_ltp
    return unless respond_to?(:quotes)

    quote = quotes.order(tick_time: :desc).first
    quote&.ltp&.to_f
  rescue StandardError => e
    Rails.logger.error("Failed to fetch latest quote LTP for #{self.class.name} #{security_id}: #{e.message}")
    nil
  end

  def fetch_ltp_from_api
    # This method is called by ltp() which already checks WebSocket first
    # But we still check here as a safety net in case called directly
    hub = Live::MarketFeedHub.instance

    if hub.running? && hub.connected?
      cached_ltp = ws_ltp
      return cached_ltp if cached_ltp.present? && cached_ltp.to_f.positive?

      # Try subscribing and waiting for tick
      begin
        segment = exchange_segment
        return nil unless segment.present? && security_id.present?

        hub.subscribe(segment: segment, security_id: security_id.to_s)
        # Wait up to 200ms for tick
        4.times do
          sleep(0.05)
          cached_ltp = ws_ltp
          return cached_ltp if cached_ltp.present? && cached_ltp.to_f.positive?
        end
      rescue StandardError => e
        Rails.logger.debug { "[InstrumentHelpers] WebSocket subscription failed for #{segment}:#{security_id}: #{e.message}" }
      end
    end

    # REST API fallback
    response = DhanHQ::Models::MarketFeed.ltp(exch_segment_enum)
    response.dig('data', exchange_segment, security_id.to_s, 'last_price') if response['status'] == 'success'
  rescue StandardError => e
    # Suppress 429 rate limit errors (expected during high load)
    error_msg = e.message.to_s
    is_rate_limit = error_msg.include?('429') || error_msg.include?('rate limit') || error_msg.include?('Rate limit')
    unless is_rate_limit
      Rails.logger.error("Failed to fetch LTP from API for #{self.class.name} #{security_id}: #{error_msg}")
    end
    nil
  end

  def subscribe_params
    { ExchangeSegment: exchange_segment, SecurityId: security_id.to_s }
  end

  def ws_get
    Live::TickCache.get(exchange_segment, security_id.to_s)
  end

  def ws_ltp
    ws_get&.dig(:ltp)
  end

  def ohlc
    response = DhanHQ::Models::MarketFeed.ohlc(exch_segment_enum)
    response['status'] == 'success' ? response.dig('data', exchange_segment, security_id.to_s) : nil
  rescue StandardError => e
    Rails.logger.error("Failed to fetch OHLC for #{self.class.name} #{security_id}: #{e.message}")
    nil
  end

  def historical_ohlc(from_date: nil, to_date: nil, oi: false)
    DhanHQ::Models::HistoricalData.daily(
      securityId: security_id,
      exchangeSegment: exchange_segment,
      instrument: instrument_type || resolve_instrument_code,
      oi: oi,
      fromDate: from_date || (Time.zone.today - 365).to_s,
      toDate: to_date || (Time.zone.today - 1).to_s,
      expiryCode: 0
    )
  rescue StandardError => e
    Rails.logger.error("Failed to fetch Historical OHLC for #{self.class.name} #{security_id}: #{e.message}")
    nil
  end

  def intraday_ohlc(interval: '5', oi: false, from_date: nil, to_date: nil, days: 2)
    to_date ||= if defined?(MarketCalendar) && MarketCalendar.respond_to?(:today_or_last_trading_day)
                  MarketCalendar.today_or_last_trading_day.to_s
                else
                  (Time.zone.today - 1).to_s
                end
    from_date ||= (Date.parse(to_date) - days).to_s

    instrument_code = resolve_instrument_code
    DhanHQ::Models::HistoricalData.intraday(
      security_id: security_id,
      exchange_segment: exchange_segment,
      instrument: instrument_code,
      interval: interval,
      oi: oi,
      from_date: from_date || (Time.zone.today - days).to_s,
      to_date: to_date || (Time.zone.today - 1).to_s
    )
  rescue StandardError => e
    Rails.logger.error("Failed to fetch Intraday OHLC for #{self.class.name} #{security_id}: #{e.message}")
    nil
  end

  def exchange_segment
    return self[:exchange_segment] if self[:exchange_segment].present?

    case [exchange&.to_sym, segment&.to_sym]
    when %i[nse index], %i[bse index]
      'IDX_I'
    when %i[nse equity]
      'NSE_EQ'
    when %i[bse equity]
      'BSE_EQ'
    when %i[nse derivatives]
      'NSE_FNO'
    when %i[bse derivatives]
      'BSE_FNO'
    when %i[nse currency]
      'NSE_CURRENCY'
    when %i[bse currency]
      'BSE_CURRENCY'
    when %i[mcx commodity]
      'MCX_COMM'
    else
      raise "Unsupported exchange and segment combination: #{exchange}, #{segment}"
    end
  end

  private

  def resolve_instrument_code
    code = instrument_code.presence || instrument_type.presence
    code ||= InstrumentTypeMapping.underlying_for(self[:instrument_code]).presence if respond_to?(:instrument_code)

    segment_value = respond_to?(:segment) ? segment.to_s.downcase : nil
    code ||= 'EQUITY' if segment_value == 'equity'
    code ||= 'INDEX' if segment_value == 'index'

    raise "Missing instrument code for #{symbol_name || security_id}" if code.blank?

    code.to_s.upcase
  end

  def depth
    response = DhanHQ::Models::MarketFeed.quote(exch_segment_enum)
    response['status'] == 'success' ? response.dig('data', exchange_segment, security_id.to_s) : nil
  rescue StandardError => e
    Rails.logger.error("Failed to fetch Depth for #{self.class.name} #{security_id}: #{e.message}")
    nil
  end

  def exch_segment_enum
    { exchange_segment => [security_id.to_i] }
  end

  def numeric_value?(value)
    value.is_a?(Numeric) || value.to_s.match?(/\A-?\d+(\.\d+)?\z/)
  end
end
