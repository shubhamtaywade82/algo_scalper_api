# frozen_string_literal: true

# DEPRECATED — read-only legacy facade over the frozen `derivatives` table.
#
# The derivative master was consolidated into `instruments` (see
# ConsolidateDerivativesIntoInstruments, 2026-09). This class exists so that
# historical data and any straggler references keep resolving:
#
#   * The table is never written anymore (InstrumentsImporter targets
#     instruments only).
#   * Lookups delegate to the consolidated Instrument where possible.
#   * Trading methods route through the consolidated Instrument so no new
#     Derivative-polymorphic records are created.
#
# Do NOT add features here — add them to Instrument.
class Derivative < ApplicationRecord
  include InstrumentHelpers

  belongs_to :instrument, optional: false, inverse_of: :derivatives
  has_many :watchlist_items, as: :watchable, dependent: :nullify, inverse_of: :watchable
  has_one  :watchlist_item,  lambda {
    where(active: true)
  }, as: :watchable, class_name: 'WatchlistItem', dependent: :nullify, inverse_of: :watchable
  has_many :position_trackers, as: :watchable, dependent: :destroy, inverse_of: :watchable

  validates :security_id, presence: true, uniqueness: { scope: %i[symbol_name exchange segment] }
  validates :option_type, inclusion: { in: %w[CE PE], allow_blank: true }

  scope :options, -> { where.not(option_type: [nil, '']) }
  scope :futures, -> { where(option_type: [nil, '']) }
  scope :ce, -> { where(option_type: 'CE') }
  scope :pe, -> { where(option_type: 'PE') }
  scope :current_expiry, -> { where(expiry_date: Date.current) }

  class << self
    # Delegates to the consolidated master. Kept for backward compatibility
    # with the legacy call shape.
    # @return [Instrument, nil]
    def find_by_params(underlying_symbol:, strike_price:, expiry_date:, option_type:)
      Instrument.find_derivative_by_params(
        underlying_symbol: underlying_symbol,
        strike_price: strike_price,
        expiry_date: expiry_date,
        option_type: option_type
      )
    end

    # @return [String, nil] Security ID or nil
    def find_security_id(underlying_symbol:, strike_price:, expiry_date:, option_type:)
      Instrument.find_security_id_by_params(
        underlying_symbol: underlying_symbol,
        strike_price: strike_price,
        expiry_date: expiry_date,
        option_type: option_type
      )
    end
  end

  # The consolidated master row for this legacy record (same broker identity).
  # @return [Instrument, nil]
  def consolidated_instrument
    Instrument.find_by(exchange: exchange, segment: segment, security_id: security_id)
  end

  # Trading routes through the consolidated Instrument so trackers/watchables
  # are created against instruments, not legacy derivatives.
  #
  # Error contract (error-handling review 2026-09): a legacy record with no
  # consolidated mirror used to log + return nil — callers then inferred
  # success/failure from side effects. It now raises; a missing mirror is a
  # data-integrity problem, not a tradeable state.
  #
  # @raise [Errors::InstrumentNotFound] when no consolidated Instrument exists
  def buy_option!(**args)
    consolidated_instrument!
      .buy_option!(**args)
  end

  # @raise [Errors::InstrumentNotFound] when no consolidated Instrument exists
  def sell_option!(**args)
    consolidated_instrument!
      .sell_option!(**args)
  end

  private

  # @return [Instrument]
  # @raise [Errors::InstrumentNotFound]
  def consolidated_instrument!
    consolidated_instrument || raise(
      Errors::InstrumentNotFound.new(
        { legacy_derivative_id: id, security_id: security_id, symbol_name: symbol_name },
        "legacy Derivative #{id} (#{symbol_name}) has no consolidated Instrument — run the consolidation migration"
      )
    )
  end
end
