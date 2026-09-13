# frozen_string_literal: true

# First-class execution (fill) record.
#
# Both execution paths converge here so downstream consumers (positions,
# ledger, analytics) see ONE event shape:
#
#   Live Gateway  ──┐
#                   ├──> Execution ──> Position ──> Ledger
#   Paper Simulator ┘
#
# Paper fills carry the simulated bid/ask + slippage from Orders::GatewayPaper;
# live fills start as `pending` and are stamped `filled` when the broker
# order-update arrives (fill price lands in fill_price then).
class Execution < ApplicationRecord
  belongs_to :instrument, optional: false
  belongs_to :position_tracker, optional: true

  enum :side, { buy: 'buy', sell: 'sell' }, prefix: true
  enum :purpose, { entry: 'entry', exit: 'exit' }
  enum :source, { paper: 'paper', live: 'live' }
  enum :status, { pending: 'pending', filled: 'filled', rejected: 'rejected' }

  validates :order_no, :quantity, presence: true
  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
  validates :fill_price, numericality: { greater_than: 0 }, allow_nil: true
  validate :filled_requires_fill_price

  scope :recent_first, -> { order(filled_at: :desc, id: :desc) }
  scope :confirmed, -> { where(status: :filled) }

  class << self
    # Records an execution from a gateway order response.
    #
    # @param order [Object, Hash] Gateway response. Paper responses are hashes
    #   carrying fill_price/bid/ask; live responses are broker order objects.
    # @param instrument [Instrument] The traded instrument.
    # @param side [Symbol, String] :buy / :sell
    # @param quantity [Integer]
    # @param purpose [Symbol, String] :entry / :exit
    # @param position_tracker [PositionTracker, nil]
    # @param requested_price [Numeric, nil] LTP/limit the strategy acted on.
    # @param filled_at [Time, nil]
    # @return [Execution, nil] nil only if the order carries no order id —
    #   recording failures are logged loudly, never raised into the trading
    #   hot path (the ledger, not telemetry, owns money correctness).
    def record_from_order!(order:, instrument:, side:, quantity:, purpose: :entry,
                           position_tracker: nil, requested_price: nil, filled_at: nil)
      order_no = Ledger::OrderResponse.extract_order_id(order)
      if order_no.blank?
        Rails.logger.warn(
          "[Execution] no order id on gateway response for #{instrument.broker_identity_key} side=#{side} — not recorded"
        )
        return nil
      end

      payload = order_payload(order)
      fill_price = decimal(payload[:fill_price] || payload['fill_price'])
      bid = decimal(payload[:bid] || payload['bid'])
      ask = decimal(payload[:ask] || payload['ask'])
      paper = Ledger::OrderResponse.paper?(order) || payload[:paper] == true || payload['paper'] == true
      status = fill_price.present? ? :filled : :pending
      slippage = compute_slippage(side: side, fill_price: fill_price, bid: bid, ask: ask)

      create!(
        instrument: instrument,
        position_tracker: position_tracker,
        order_no: order_no.to_s,
        client_order_id: (payload[:client_order_id] || payload['client_order_id']).to_s.presence,
        side: side,
        purpose: purpose,
        source: paper ? :paper : :live,
        status: status,
        quantity: quantity.to_i,
        requested_price: decimal(requested_price),
        fill_price: fill_price,
        bid: bid,
        ask: ask,
        slippage: slippage,
        filled_at: filled_at || (status == :filled ? Time.current : nil),
        meta: {
          gateway_response_keys: payload.keys.map(&:to_s).first(12)
        }
      )
    rescue StandardError => e
      Rails.logger.error(
        "[Execution] failed to record order=#{order_no} instrument=#{instrument&.broker_identity_key}: #{e.class} - #{e.message}"
      )
      nil
    end

    private

    def order_payload(order)
      return {} if order.nil?

      if order.is_a?(Hash)
        order
      elsif order.respond_to?(:to_h)
        order.to_h
      else
        {}
      end
    end

    def decimal(value)
      return nil if value.blank?

      BigDecimal(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    # Buy fills cross the ask, sell fills cross the bid — slippage beyond the
    # touch is what the simulator (or the market) added on top.
    def compute_slippage(side:, fill_price:, bid:, ask:)
      return nil if fill_price.blank?

      reference = side.to_s.casecmp('buy').zero? ? ask : bid
      return nil if reference.blank?

      (fill_price - reference).round(4)
    end
  end

  def paper?
    source == 'paper'
  end

  def live?
    source == 'live'
  end

  def confirmed?
    status == 'filled'
  end

  # Marks a pending live execution as filled once the broker reports the fill.
  def confirm!(fill_price:, fees: nil, filled_at: Time.current)
    update!(
      fill_price: BigDecimal(fill_price.to_s),
      fees: fees ? BigDecimal(fees.to_s) : self.fees,
      status: :filled,
      filled_at: filled_at
    )
  end

  private

  def filled_requires_fill_price
    return if status != 'filled' || fill_price.present?

    errors.add(:fill_price, 'must be present for a filled execution')
  end
end
