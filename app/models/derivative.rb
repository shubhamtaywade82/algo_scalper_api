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

  # No inverse_of: the Instrument side's `derivatives` association now points
  # at consolidated Instrument rows (self-referential), not at this class.
  belongs_to :instrument, optional: false
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
  def buy_option!(**args)
    target = consolidated_instrument
    if target.nil?
      Rails.logger.error(
        "[Derivative] DEPRECATED buy_option! on legacy derivative #{id} with no consolidated instrument"
      )
      return nil
    end

    target.buy_option!(**args)
  end

  def sell_option!(**args)
    target = consolidated_instrument
    if target.nil?
      Rails.logger.error(
        "[Derivative] DEPRECATED sell_option! on legacy derivative #{id} with no consolidated instrument"
      )
      return nil
    end

    target.sell_option!(**args)
  end
end
