# frozen_string_literal: true

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
      Rails.logger.info("Subscribed #{self.class.name} #{security_id} to WS feed.")
      true
    rescue StandardError => e
      Rails.logger.error("Failed to subscribe #{self.class.name} #{security_id}: #{e.message}")
      false
    end

    def unsubscribe
      Live::WsHub.instance.unsubscribe(seg: exchange_segment, sid: security_id.to_s)
      Rails.logger.info("Unsubscribed #{self.class.name} #{security_id} from WS feed.")
      true
    rescue StandardError => e
      Rails.logger.error("Failed to unsubscribe #{self.class.name} #{security_id}: #{e.message}")
      false
    end
  end

  def ltp
    fetch_ltp_from_api
  rescue StandardError => e
    Rails.logger.error("Failed to fetch LTP for #{self.class.name} #{security_id}: #{e.message}")
    nil
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
    response = DhanHQ::Models::MarketFeed.ltp(exch_segment_enum)
    response.dig('data', exchange_segment, security_id.to_s, 'last_price') if response['status'] == 'success'
  rescue StandardError => e
    Rails.logger.error("Failed to fetch LTP from API for #{self.class.name} #{security_id}: #{e.message}")
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
