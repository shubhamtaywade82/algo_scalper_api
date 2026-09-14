# == Schema Information
#
# Table name: instruments
#
#  id                            :integer          not null, primary key
#  exchange                      :string           not null
#  segment                       :string           not null
#  security_id                   :string           not null
#  isin                          :string
#  instrument_code               :string
#  underlying_security_id        :string
#  underlying_symbol             :string
#  underlying_instrument_id      :bigint
#  symbol_name                   :string
#  display_name                  :string
#  instrument_type               :string
#  series                        :string
#  lot_size                      :integer
#  expiry_date                   :date
#  strike_price                  :decimal(15, 5)
#  option_type                   :string
#  tick_size                     :decimal(, )
#  expiry_flag                   :string
#  bracket_flag                  :string
#  cover_flag                    :string
#  asm_gsm_flag                  :string
#  asm_gsm_category              :string
#  buy_sell_indicator            :string
#  active                        :boolean
#  tradable                      :boolean
#  contract_multiplier           :decimal(, )
#  custom_symbol                 :string
#  settlement_type               :string           default("cash")
#  created_at                    :datetime         not null
#  updated_at                    :datetime         not null
#
# Indexes
#
#  index_instruments_on_exchange_segment_security_id_unique  (exchange,segment,security_id) UNIQUE
#  index_instruments_on_option_contract_identity             (exchange,segment,underlying_security_id,expiry_date,strike_price,option_type) UNIQUE (partial)
#  index_instruments_on_future_contract_identity             (exchange,segment,underlying_security_id,expiry_date) UNIQUE (partial)
#  index_instruments_on_underlying_instrument_id             (underlying_instrument_id)
#  index_instruments_on_security_id_and_segment              (security_id,segment)
#  index_instruments_on_instrument_code                      (instrument_code)
#  index_instruments_on_symbol_name                          (symbol_name)
#  index_instruments_on_underlying_symbol_and_expiry_date    (underlying_symbol,expiry_date)
#

# frozen_string_literal: true

require "bigdecimal"

# Single canonical tradable-security master.
#
# Domain decision (architecture review 2026-09):
#   Instrument = one broker/exchange-specific tradable contract
#   (equity, index, future, option). The legacy `derivatives` table was a
#   duplicate copy of the Dhan scrip master and is now a frozen archive —
#   everything lives here.
#
# Identity:
#   * Broker identity ... (exchange, segment, security_id)  — DB-unique.
#   * Internal identity .. id (referenced by every FK).
#   * Contract identity .. (exchange, segment, underlying_security_id,
#     expiry_date, strike_price, option_type) for options — DB-unique via a
#     partial index.
#
# Underlying relationship (self-referential):
#   NIFTY index row  <-underlying_instrument_id-  NIFTY 25000 CE row
#   The underlying link is metadata about a contract, NOT a separate master
#   entity, mirroring Dhan's own UNDERLYING_SECURITY_ID field.
class Instrument < ApplicationRecord
  include InstrumentHelpers

  # --- Identity -----------------------------------------------------------
  # DB invariant (index_instruments_on_exchange_segment_security_id_unique)
  # and application invariant now agree: one row per tradable security per
  # exchange segment. The previous model validated global security_id
  # uniqueness while the database only enforced it per (security_id,
  # symbol_name, exchange, segment) — two different contracts.
  validates :security_id, presence: true, uniqueness: { scope: %i[exchange segment] }
  validates :symbol_name, presence: true
  validates :exchange_segment, presence: true, unless: -> { exchange.present? && segment.present? }
  validates :option_type, inclusion: { in: %w[CE PE], allow_blank: true }

  # --- Associations -------------------------------------------------------
  belongs_to :underlying_instrument, class_name: 'Instrument', optional: true,
                                     inverse_of: :derivative_contracts
  has_many :derivative_contracts, class_name: 'Instrument',
           foreign_key: :underlying_instrument_id,
           inverse_of: :underlying_instrument, dependent: :nullify

  # Legacy association over the frozen `derivatives` table (Derivative is a
  # deprecated read-only facade — see that class). This is the ORIGINAL name
  # and contract; the consolidation briefly repurposed it for the
  # self-referential contract rows, which silently changed what every legacy
  # reader (specs, rake tasks, chain analyzers) got back. The consolidated
  # contract rows live on #derivative_contracts above — use that for anything
  # new (review P1: one name, one meaning).
  has_many :derivatives, class_name: 'Derivative',
           inverse_of: :instrument, dependent: :destroy

  has_many :position_trackers, dependent: :restrict_with_error
  has_many :executions, dependent: :restrict_with_error
  has_many :watchlist_items, as: :watchable, dependent: :nullify, inverse_of: :watchable
  has_one  :watchlist_item,  lambda {
    where(active: true)
  }, as: :watchable, class_name: 'WatchlistItem', dependent: :nullify, inverse_of: :watchable

  # --- Scopes -------------------------------------------------------------
  scope :active, -> { where(active: true) }
  scope :tradable, -> { where(tradable: true) }
  scope :fno, -> { where(segment: :derivatives) }
  scope :options, -> { where.not(option_type: [nil, '']) }
  scope :futures, -> { where(option_type: [nil, '']).where.not(expiry_date: nil) }
  scope :ce, -> { where(option_type: 'CE') }
  scope :pe, -> { where(option_type: 'PE') }
  scope :current_expiry, -> { where(expiry_date: Date.current) }
  scope :expired, -> { where(expiry_date: ...Date.current) }
  scope :not_expired, -> { where(expiry_date: Date.current..).or(where(expiry_date: nil)) }

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
    def option_chain_adapter
      @option_chain_adapter ||= Adapters::OptionChain::DhanAdapter.new
    end

    attr_writer :option_chain_adapter

    def segment_key_for(segment_code)
      return if segment_code.blank?

      code = segment_code.to_s.upcase.strip
      SEGMENT_FROM_EXCHANGE[code] || code.downcase
    end

    # Strict broker-identity lookup: security_id + segment only.
    #
    # Error-handling review 2026-09: this used to fall back to a symbol_name
    # lookup when the security_id missed — silently substituting a *different
    # security* with a shared symbol (NIFTY index vs NIFTY future vs historical
    # contracts). A failed broker-ID lookup is now simply nil; symbol-based
    # discovery lives explicitly in #resolve_index_by_sid_or_symbol.
    #
    # @return [Instrument, nil] nil when the broker identity is unknown
    def find_by_sid_and_segment(security_id:, segment_code:)
      return nil unless security_id.present? && segment_code.present?

      sid = security_id.to_s
      segment_keys_for(segment_code).each do |segment_key|
        instrument = find_by(security_id: sid, segment: segment_key)
        return instrument if instrument.present?
      end

      nil
    end

    # Explicit DISCOVERY lookup for index master rows: try the broker identity
    # first, then the symbol. Only for read/discovery paths (index config
    # resolution, VIX) — never for placing orders, where identity must be exact.
    #
    # @return [Instrument, nil]
    def resolve_index_by_sid_or_symbol(security_id:, segment_code:, symbol_name:)
      instrument = find_by_sid_and_segment(security_id: security_id, segment_code: segment_code)
      return instrument if instrument
      return nil if symbol_name.blank?

      segment_keys_for(segment_code).each do |segment_key|
        instrument = find_by(symbol_name: symbol_name.to_s, segment: segment_key)
        return instrument if instrument.present?
      end

      nil
    end

    def segment_keys_for(segment_code)
      primary = segment_key_for(segment_code)
      return [] if primary.blank?

      keys = [primary]
      case primary
      when "index" then keys.push("I", "i")
      when "derivatives" then keys.push("D", "d")
      when "equity" then keys.push("E", "e")
      end
      keys.uniq
    end

    # Find index instrument by security_id and symbol_name
    # @param security_id [String, Integer] Security ID
    # @param symbol_name [String] Symbol name (e.g., "NIFTY", "BANKNIFTY")
    # @return [Instrument, nil]
    def find_index_by_sid_and_symbol(security_id:, symbol_name:)
      segment_index.find_by(security_id: security_id.to_s, symbol_name: symbol_name.to_s)
    end

    # --- Contract resolution (Q19 query surface) --------------------------

    # Exact option resolution in a single SQL statement.
    #
    # The business identity of an option contract — exchange + underlying +
    # expiry + strike + CE/PE — is a database invariant
    # (index_instruments_on_option_contract_identity), so this lookup no
    # longer depends on in-Ruby BigDecimal comparison the way the legacy
    # Derivative.find_by_params did.
    #
    # @param underlying_symbol [String] e.g. "NIFTY"
    # @param expiry_date [Date, String]
    # @param strike_price [Numeric, String]
    # @param option_type [String] "CE" or "PE"
    # @param exchange [String, nil] e.g. "NSE"
    # @return [Instrument, nil]
    def find_option(underlying_symbol:, expiry_date:, strike_price:, option_type:, exchange: nil)
      options
        .where(underlying_symbol: underlying_symbol.to_s.upcase)
        .where(expiry_date: coerce_date(expiry_date))
        .where(option_type: option_type.to_s.upcase)
        .where(strike_price: BigDecimal(strike_price.to_s))
        .then { |scope| exchange.present? ? scope.where(exchange: exchange.to_s.upcase) : scope }
        .first
    end

    # Back-compat alias for the legacy Derivative.find_by_params call shape.
    def find_derivative_by_params(underlying_symbol:, strike_price:, expiry_date:, option_type:, exchange: nil)
      find_option(
        underlying_symbol: underlying_symbol,
        expiry_date: expiry_date,
        strike_price: strike_price,
        option_type: option_type,
        exchange: exchange
      )
    end

    # Back-compat alias for the legacy Derivative.find_security_id.
    def find_security_id_by_params(underlying_symbol:, strike_price:, expiry_date:, option_type:)
      find_option(
        underlying_symbol: underlying_symbol,
        expiry_date: expiry_date,
        strike_price: strike_price,
        option_type: option_type
      )&.security_id
    end

    # All option contracts for one underlying + expiry (strike-ordered).
    # @return [ActiveRecord::Relation<Instrument>]
    def options_for(underlying_symbol:, expiry_date:, option_type: nil, exchange: nil)
      scope = options
              .where(underlying_symbol: underlying_symbol.to_s.upcase)
              .where(expiry_date: coerce_date(expiry_date))
              .order(:strike_price)
      scope = scope.where(option_type: option_type.to_s.upcase) if option_type.present?
      scope = scope.where(exchange: exchange.to_s.upcase) if exchange.present?
      scope
    end

    # Distinct tradable expiries for an underlying, nearest first.
    # @param include_expired [Boolean] keep already-expired contract listings
    # @return [Array<Date>]
    def option_expiries_for(underlying_symbol:, exchange: nil, include_expired: false)
      scope = options.where(underlying_symbol: underlying_symbol.to_s.upcase)
      scope = scope.where(exchange: exchange.to_s.upcase) if exchange.present?
      scope = scope.not_expired unless include_expired
      scope.distinct.order(:expiry_date).pluck(:expiry_date).compact
    end

    # Options within +-range of the ATM strike for the current expiry.
    # @return [ActiveRecord::Relation<Instrument>]
    def atm_options(underlying_symbol:, spot:, expiry_date: nil, range: 100, limit: 5)
      expiry = expiry_date.present? ? coerce_date(expiry_date) : option_expiries_for(underlying_symbol: underlying_symbol).first
      return none if expiry.blank?

      options
        .where(underlying_symbol: underlying_symbol.to_s.upcase, expiry_date: expiry)
        .where('ABS(strike_price - ?) <= ?', spot.to_f, range.to_f)
        .order(:strike_price)
        .limit(limit)
    end

    # Strict date coercion for contract queries: an unparseable expiry used to
    # collapse to nil and silently match nothing. Malformed query input is now
    # an explicit error.
    #
    # @raise [Errors::InvalidParameter]
    def coerce_date(raw)
      case raw
      when Date then raw
      when Time, DateTime, ActiveSupport::TimeWithZone then raw.to_date
      when String then Date.parse(raw)
      else Date.parse(raw.to_s)
      end
    rescue ArgumentError, TypeError => e
      raise Errors::InvalidParameter, "unparseable expiry date #{raw.inspect} (#{e.class}: #{e.message})"
    end
  end

  # --- Predicates ---------------------------------------------------------
  def option?
    option_type.present?
  end

  def future?
    option_type.blank? && expiry_date.present?
  end

  # True for FNO contracts (futures + options) — i.e. anything that has an
  # underlying and expiry semantics.
  def derivative?
    return true if option? || future?
    return true if underlying_security_id.present?

    segment_derivatives?
  end

  def index_master?
    segment_index?
  end

  def expired?
    expiry_date.present? && expiry_date < Date.current
  end

  # Operational availability: an instrument row is kept forever for history
  # but expired contracts must never be selected for new orders.
  def currently_tradable?
    return false if expired?

    active != false && tradable != false
  end

  # Composite key used for logging / reconciliation.
  def broker_identity_key
    "#{exchange}:#{segment}:#{security_id}"
  end

  def contract_identity_key
    [exchange, segment, underlying_security_id, expiry_date, strike_price, option_type].compact.join(':')
  end

  def subscribe!
    subscribe
  end

  def unsubscribe!
    unsubscribe
  end

  # Places a market BUY order for this instrument and tracks it.
  #
  # Quantity contract (error-handling review 2026-09): qty is REQUIRED and
  # must be a positive whole number. The previous `qty.to_i.positive? ?
  # qty.to_i : 1` turned nil/0/-50/"abc" into a live order for ONE unit.
  #
  # @param qty [Integer] positive whole quantity (required)
  # @param product_type [String]
  # @param meta [Hash]
  # @return [Object, nil] Order response from gateway
  # @raise [Errors::InvalidQuantity]
  def buy_market!(qty: nil, product_type: "NORMAL", meta: {})
    segment_code = exchange_segment
    security = security_id.to_s
    raise "Instrument missing segment/security_id" if segment_code.blank? || security.blank?

    quantity = Orders::Quantity.resolve!(qty, context: "#{symbol_name} buy_market!")

    ltp = resolve_ltp(segment: segment_code, security_id: security, meta: meta)
    raise "LTP unavailable" unless ltp

    order = Orders.config.gateway.place_market(
      side: 'buy',
      segment: segment_code,
      security_id: security,
      qty: quantity,
      meta: {
        client_order_id: meta[:client_order_id] || default_client_order_id(side: :buy, security_id: security),
        ltp: ltp,
        product_type: product_type
      }
    )
    return nil unless order.respond_to?(:order_id) && order.order_id.present?

    order_no = order.order_id
    tracker = after_order_track!(
      instrument: self,
      order_no: order_no,
      segment: segment_code,
      security_id: security,
      side: "LONG",
      qty: quantity,
      entry_price: ltp,
      symbol: symbol_name || display_name,
      index_key: meta[:index_key],
      meta: meta.slice(:alpha_source, :signal_confidence, :expected_value, :entry_strategy, :direction, :client_order_id)
    )

    execution = Execution.record_from_order!(
      order: order, instrument: self, side: :buy, quantity: quantity,
      purpose: :entry, position_tracker: tracker, requested_price: ltp
    )

    if Ledger::OrderResponse.paper?(order) || (order.is_a?(Hash) && order[:paper])
      Ledger::EntryPoster.post!(
        tracker: tracker,
        fill_price: execution&.fill_price || ltp,
        quantity: quantity,
        order_no: order_no
      )
    end

    order
  end

  # Places a market SELL order for a specific quantity of this instrument.
  #
  # Quantity contract: explicit sell-to-open/reduce orders MUST pass qty.
  # Closing the whole position is a separate, explicit command:
  # #close_market_position! — the previous "qty missing -> liquidate
  # everything" behaviour is gone.
  #
  # @param qty [Integer] positive whole quantity (required)
  # @param meta [Hash]
  # @return [Object, nil]
  # @raise [Errors::InvalidQuantity]
  def sell_market!(qty: nil, meta: {})
    segment_code = exchange_segment
    security = security_id.to_s
    raise "Instrument missing segment/security_id" if segment_code.blank? || security.blank?

    quantity = Orders::Quantity.resolve!(qty, context: "#{symbol_name} sell_market!")

    Orders.config.gateway.place_market(
      side: 'sell',
      segment: segment_code,
      security_id: security,
      qty: quantity,
      meta: {
        client_order_id: meta[:client_order_id] || default_client_order_id(side: :sell, security_id: security)
      }
    )
  end

  # EXPLICIT whole-position exit: sells the total active tracked quantity for
  # this security. This is the deliberate liquidation policy that sell_market!
  # used to infer from a missing qty.
  #
  # @return [Object, nil] order response, or nil when there is no active
  #   position to close (documented domain outcome)
  def close_market_position!(meta: {})
    segment_code = exchange_segment
    security = security_id.to_s
    raise "Instrument missing segment/security_id" if segment_code.blank? || security.blank?

    quantity = PositionTracker.active.where(security_id: security).sum(:quantity).to_i
    if quantity <= 0
      Rails.logger.info("[Instrument] close_market_position! — no active position for #{symbol_name} (#{security})")
      return nil
    end

    Orders.config.gateway.place_market(
      side: 'sell',
      segment: segment_code,
      security_id: security,
      qty: quantity,
      meta: {
        client_order_id: meta[:client_order_id] || default_client_order_id(side: :sell, security_id: security),
        close_position: true
      }
    )
  end

  # Places a market BUY order for this option contract (CE/PE).
  #
  # Quantity contract (error-handling review 2026-09): sizing is EXPLICIT.
  #   * qty given ............ used as-is (strictly validated)
  #   * qty absent + auto_size: true ... strategy/admin sizing policy that
  #     deliberately requests Capital::Allocator sizing (requires index_cfg)
  #   * qty absent + auto_size: false .. Errors::InvalidQuantity
  # Previously a missing qty silently manufactured an index config and
  # auto-sized the order — a trading decision nobody explicitly made.
  #
  # @param qty [Integer, nil]
  # @param auto_size [Boolean] explicitly opt in to allocator sizing
  # @param product_type [String]
  # @param index_cfg [Hash, nil] required when auto_size is true
  # @param meta [Hash]
  # @return [Object, nil] Order response from gateway
  # @raise [Errors::InvalidQuantity, Errors::ConfigurationError]
  def buy_option!(qty: nil, auto_size: false, product_type: "NORMAL", index_cfg: nil, meta: {})
    segment_code = exchange_segment
    security = security_id.to_s
    raise "Instrument missing segment/security_id" if segment_code.blank? || security.blank?

    ltp = resolve_ltp(segment: segment_code, security_id: security, meta: meta)
    raise "LTP unavailable" unless ltp

    quantity = if qty.present?
      Orders::Quantity.resolve!(qty, context: "#{symbol_name} buy_option!")
               elsif auto_size
      unless index_cfg.is_a?(Hash) && index_cfg.present?
        raise Errors::ConfigurationError,
              "index_cfg is required to auto-size #{symbol_name} — refusing to manufacture one"
      end

      Capital::Allocator.qty_for(
        index_cfg: index_cfg,
        entry_price: ltp.to_f,
        derivative_lot_size: lot_size.to_i,
        scale_multiplier: 1
      ).tap do |resolved|
        unless resolved.present? && resolved.to_i.positive?
          raise Errors::InvalidQuantity,
                "allocator returned no usable quantity for #{symbol_name} (got #{resolved.inspect})"
        end
      end.to_i
               else
      raise Errors::InvalidQuantity,
            "qty is required for buy_option! on #{symbol_name} " \
            "(pass auto_size: true to request allocator sizing)"
               end

    order = Orders.config.gateway.place_market(
      side: 'buy',
      segment: segment_code,
      security_id: security,
      qty: quantity,
      meta: {
        client_order_id: meta[:client_order_id] || default_client_order_id(side: :buy, security_id: security),
        ltp: ltp,
        product_type: product_type
      }
    )
    order_no = Ledger::OrderResponse.extract_order_id(order)
    return nil if order_no.blank?

    side_label = option_type.to_s.upcase == "CE" ? "long_ce" : "long_pe"

    tracker = after_order_track!(
      instrument: self,
      order_no: order_no,
      segment: segment_code,
      security_id: security,
      side: side_label,
      qty: quantity,
      entry_price: ltp,
      symbol: symbol_name || display_name,
      index_key: (index_cfg || {})[:key],
      meta: meta.slice(:alpha_source, :signal_confidence, :expected_value, :entry_strategy, :signal_timestamp, :direction, :client_order_id)
    )
    execution = Execution.record_from_order!(
      order: order, instrument: self, side: :buy, quantity: quantity,
      purpose: :entry, position_tracker: tracker, requested_price: ltp
    )

    if Ledger::OrderResponse.paper?(order) || (order.is_a?(Hash) && order[:paper])
      Ledger::EntryPoster.post!(
        tracker: tracker,
        # Ledger books the SIMULATED fill (bid/ask + slippage from the paper
        # gateway), not the raw LTP — previously this overstated paper P&L.
        fill_price: execution&.fill_price || ltp,
        quantity: quantity,
        order_no: order_no
      )
    end

    order
  end

  # Places a market SELL order for a specific quantity of this option.
  #
  # Quantity contract: SELL-to-open/reduce requires an explicit qty. Closing
  # the whole tracked position is the separate, explicit #close_position!
  # command — the previous "qty missing -> sell the entire position" implicit
  # liquidation policy is gone.
  #
  # @param qty [Integer] positive whole quantity (required)
  # @param meta [Hash]
  # @return [Object, nil]
  # @raise [Errors::InvalidQuantity]
  def sell_option!(qty: nil, meta: {})
    segment_code = exchange_segment
    security = security_id.to_s
    raise "Instrument missing segment/security_id" if segment_code.blank? || security.blank?

    quantity = Orders::Quantity.resolve!(qty, context: "#{symbol_name} sell_option!")

    Orders.config.gateway.place_market(
      side: 'sell',
      segment: segment_code,
      security_id: security,
      qty: quantity,
      meta: {
        client_order_id: meta[:client_order_id] || default_client_order_id(side: :sell, security_id: security)
      }
    )
  end

  # EXPLICIT whole-position exit for this option contract: sells the total
  # active tracked quantity. This is the deliberate close policy that
  # sell_option! used to infer from a missing qty.
  #
  # @return [Object, nil] order response, or nil when there is no active
  #   position to close (documented domain outcome)
  def close_position!(meta: {})
    segment_code = exchange_segment
    security = security_id.to_s
    raise "Instrument missing segment/security_id" if segment_code.blank? || security.blank?

    quantity = PositionTracker.active.where(security_id: security).sum(:quantity).to_i
    if quantity <= 0
      Rails.logger.info("[Instrument] close_position! — no active position for #{symbol_name} (#{security})")
      return nil
    end

    Orders.config.gateway.place_market(
      side: 'sell',
      segment: segment_code,
      security_id: security,
      qty: quantity,
      meta: {
        client_order_id: meta[:client_order_id] || default_client_order_id(side: :sell, security_id: security),
        close_position: true
      }
    )
  end

  # API Methods
  def fetch_option_chain(expiry = nil)
    expiry ||= expiry_list.first

    # Check if caching is disabled for fresh data
    freshness_config = AlgoConfig.fetch[:data_freshness] || {}
    disable_caching = freshness_config[:disable_option_chain_caching] || false

    if disable_caching
      # Rails.logger.debug { "[Instrument] Fresh data mode - bypassing option chain cache for #{symbol_name}" }
      return fetch_fresh_option_chain(expiry)
    end

    # Use cached data if available and not stale
    cache_key = "option_chain:#{security_id}:#{expiry}"
    cached_data = Rails.cache.read(cache_key)

    if cached_data && !option_chain_stale?(expiry)
      # Rails.logger.debug { "[Instrument] Using cached option chain for #{symbol_name} #{expiry}" }
      return cached_data
    end

    # Fetch fresh data and cache it
    fresh_data = fetch_fresh_option_chain(expiry)
    if fresh_data
      cache_duration_minutes = freshness_config[:option_chain_cache_duration_minutes] || 2
      Rails.cache.write(cache_key, fresh_data, expires_in: cache_duration_minutes.minutes)
      Rails.cache.write("#{cache_key}:timestamp", Time.current, expires_in: cache_duration_minutes.minutes)
      # Rails.logger.debug { "[Instrument] Cached fresh option chain for #{symbol_name} #{expiry}" }
    end

    fresh_data
  end

  def fetch_fresh_option_chain(expiry)
    data = self.class.option_chain_adapter.fetch_chain(
      underlying_scrip: security_id.to_i,
      underlying_seg: exchange_segment,
      expiry: expiry
    )
    return nil unless data

    normalized = normalize_option_chain_response(data)
    return nil unless normalized

    filter_option_chain_data(normalized)

    filtered_data = filter_option_chain_data(normalized)

    { last_price: data["last_price"], oc: filtered_data }
  rescue StandardError => e
    DhanhqErrorHandler.handle_dhanhq_error(
      e,
      context: "fetch_option_chain(Instrument #{security_id}, expiry: #{expiry})"
    )
    msg = "Failed to fetch Option Chain for Instrument #{security_id}: #{e.message}"
    Notifications::TelegramNotifier.instance.notify_error(msg, context: 'Instrument')
    Rails.logger.error(msg)
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

  # Normalize DhanHQ option chain response to consistent Hash format.
  # DhanHQ 2.7.0+ returns {"strikes": [{strike:, call:, put:}, ...]}
  # Legacy format:        {"oc": {"23400": {"ce": {...}, "pe": {...}}, ...}}
  # Returns: Hash with string strike keys and ce/pe sub-hashes
  def normalize_option_chain_response(data)
    # Legacy format — already a hash keyed by strike
    return data if data['oc'].is_a?(Hash)

    # DhanHQ 2.7.0+ format — array of strike objects
    strikes = data['strikes']
    return data if strikes.nil? && data['oc']

    return nil unless strikes.is_a?(Array)

    oc_hash = {}
    strikes.each do |strike_obj|
      key = strike_obj['strike'].to_f.to_s
      oc_hash[key] = {
        'ce' => strike_obj['call'],
        'pe' => strike_obj['put']
      }
    end

    data.merge('oc' => oc_hash)
  end

  def filter_option_chain_data(data)
    oc = data['oc']
    return {} unless oc.is_a?(Hash)

    oc.select do |_strike, option_data|
      call_data = option_data['ce']
      put_data = option_data['pe']

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
    self.class.option_chain_adapter.fetch_expiry_list(
      underlying_scrip: security_id.to_i,
      underlying_seg: exchange_segment
    )
  end

  def option_chain(expiry: nil)
    fetch_option_chain(expiry)
  end

  # Get lot size from the nearest future expiry contract hanging off this
  # underlying. Returns the lot_size of the first contract with
  # expiry_date >= today.
  # @return [Integer, nil] Lot size from nearest future expiry contract, or nil if not found
  def lot_size_from_derivatives
    today = Time.zone.today
    # Read the consolidated contract rows (the legacy `derivatives` table is
    # frozen — the importer only upserts instruments now).
    nearest_derivative = derivative_contracts
                         .where(expiry_date: today..)
                         .where.not(lot_size: nil)
                         .order(expiry_date: :asc)
                         .first

    nearest_derivative&.lot_size&.to_i
  end
end
