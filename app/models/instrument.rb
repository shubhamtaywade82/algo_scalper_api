# frozen_string_literal: true

require "bigdecimal"

class Instrument < ApplicationRecord
  include InstrumentHelpers

  has_many :derivatives, dependent: :destroy
  accepts_nested_attributes_for :derivatives, allow_destroy: true
  has_many :watchlist_items, as: :watchable, dependent: :nullify, inverse_of: :watchable
  has_one  :watchlist_item,  -> { where(active: true) }, as: :watchable, class_name: "WatchlistItem"
  has_many :position_trackers, dependent: :restrict_with_error

  scope :enabled, -> { where(enabled: true) }

  validates :security_id, presence: true, uniqueness: true
  validates :symbol_name, presence: true
  validates :exchange_segment, presence: true, unless: -> { exchange.present? && segment.present? }

  SEGMENT_FROM_EXCHANGE = {
    "IDX_I" => "index",
    "BSE_IDX" => "index",
    "NSE_IDX" => "index",
    "I" => "index",
    "NSE_EQ" => "equity",
    "BSE_EQ" => "equity",
    "E" => "equity",
    "NSE_FNO" => "derivatives",
    "BSE_FNO" => "derivatives",
    "D" => "derivatives",
    "NSE_CURRENCY" => "currency",
    "BSE_CURRENCY" => "currency",
    "C" => "currency",
    "MCX_COMM" => "commodity",
    "M" => "commodity"
  }.freeze

  class << self
    def segment_key_for(segment_code)
      return if segment_code.blank?

      code = segment_code.to_s.upcase.strip
      SEGMENT_FROM_EXCHANGE[code] || code.downcase
    end

    def find_by_sid_and_segment(security_id:, segment_code:, symbol_name: nil)
      segment_key = segment_key_for(segment_code)
      return nil unless security_id.present? && segment_key.present?

      sid = security_id.to_s
      instrument = find_by(security_id: sid, segment: segment_key)
      return instrument if instrument.present? || symbol_name.blank?

      find_by(symbol_name: symbol_name.to_s, segment: segment_key)
    end
  end

  def subscribe!
    subscribe
  end

  def unsubscribe!
    unsubscribe
  end

  def latest_ltp
    price = ws_ltp || quote_ltp || fetch_ltp_from_api
    price.present? ? BigDecimal(price.to_s) : nil
  end

  # API Methods
  def fetch_option_chain(expiry = nil)
    expiry ||= expiry_list.first

    # Check if caching is disabled for fresh data
    freshness_config = AlgoConfig.fetch[:data_freshness] || {}
    disable_caching = freshness_config[:disable_option_chain_caching] || false

    if disable_caching
      Rails.logger.debug("[Instrument] Fresh data mode - bypassing option chain cache for #{symbol_name}")
      return fetch_fresh_option_chain(expiry)
    end

    # Use cached data if available and not stale
    cache_key = "option_chain:#{security_id}:#{expiry}"
    cached_data = Rails.cache.read(cache_key)

    if cached_data && !option_chain_stale?(expiry)
      Rails.logger.debug("[Instrument] Using cached option chain for #{symbol_name} #{expiry}")
      return cached_data
    end

    # Fetch fresh data and cache it
    fresh_data = fetch_fresh_option_chain(expiry)
    if fresh_data
      cache_duration_minutes = freshness_config[:option_chain_cache_duration_minutes] || 2
      Rails.cache.write(cache_key, fresh_data, expires_in: cache_duration_minutes.minutes)
      Rails.cache.write("#{cache_key}:timestamp", Time.current, expires_in: cache_duration_minutes.minutes)
      Rails.logger.debug("[Instrument] Cached fresh option chain for #{symbol_name} #{expiry}")
    end

    fresh_data
  end

  def fetch_fresh_option_chain(expiry)
    data = DhanHQ::Models::OptionChain.fetch(
      underlying_scrip: security_id.to_i,
      underlying_seg: exchange_segment,
      expiry: expiry
    )
    return nil unless data

    filtered_data = filter_option_chain_data(data)

    { last_price: data["last_price"], oc: filtered_data }
  rescue StandardError => e
    Rails.logger.error("Failed to fetch Option Chain for Instrument #{security_id}: #{e.message}")
    nil
  end

  def option_chain_stale?(expiry)
    freshness_config = AlgoConfig.fetch[:data_freshness] || {}
    cache_duration_minutes = freshness_config[:option_chain_cache_duration_minutes] || 2

    cache_key = "option_chain:#{security_id}:#{expiry}"
    cached_at = Rails.cache.read("#{cache_key}:timestamp")

    return true unless cached_at

    Time.current - cached_at > cache_duration_minutes.minutes
  end

  def filter_option_chain_data(data)
    data["oc"].select do |_strike, option_data|
      call_data = option_data["ce"]
      put_data = option_data["pe"]

      has_call_values = call_data && call_data.except("implied_volatility").values.any? do |v|
        numeric_value?(v) && v.to_f.positive?
      end
      has_put_values = put_data && put_data.except("implied_volatility").values.any? do |v|
        numeric_value?(v) && v.to_f.positive?
      end

      has_call_values || has_put_values
    end
  end

  def expiry_list
    DhanHQ::Models::OptionChain.fetch_expiry_list(
      underlying_scrip: security_id.to_i,
      underlying_seg: exchange_segment
    )
  end

  def option_chain(expiry: nil)
    Trading::DataFetcherService.new.fetch_option_chain(
      instrument: self,
      expiry: expiry
    )
  end
end
