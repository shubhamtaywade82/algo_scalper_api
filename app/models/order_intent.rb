# frozen_string_literal: true

require "aasm"

# OrderIntent represents a strategy's desire to trade.
# It is the bridge between signal generation and order execution.
# Strategies produce intents; the execution layer decides paper vs live routing.
class OrderIntent < ApplicationRecord
  include AASM

  belongs_to :instrument

  SIDES = %w[BUY SELL].freeze
  ORDER_TYPES = %w[MARKET LIMIT SL SLM].freeze
  PRODUCT_TYPES = %w[INTRADAY CNC MARGIN].freeze
  VALIDITIES = %w[DAY IOC].freeze
  STATUSES = %w[created risk_pending risk_approved margin_pending approved
                submitted acknowledged partially_filled filled cancel_pending
                cancelled rejected expired failed].freeze

  validates :strategy_name, presence: true
  validates :side, presence: true, inclusion: { in: SIDES }
  validates :quantity, presence: true, numericality: { greater_than: 0, only_integer: true }
  validates :order_type, inclusion: { in: ORDER_TYPES }
  validates :product_type, inclusion: { in: PRODUCT_TYPES }
  validates :validity, inclusion: { in: VALIDITIES }
  validates :limit_price, numericality: { greater_than: 0 }, allow_nil: true
  validates :trigger_price, numericality: { greater_than: 0 }, allow_nil: true

  scope :pending, -> { where(status: %w[created risk_pending margin_pending]) }
  scope :approved, -> { where(status: "approved") }
  scope :terminal, -> { where(status: %w[filled cancelled rejected expired failed]) }
  scope :active, -> { where.not(status: %w[filled cancelled rejected expired failed]) }
  scope :for_strategy, ->(name) { where(strategy_name: name) }
  scope :today, -> { where(created_at: Time.current.beginning_of_day..) }

  before_create :assign_correlation_id

  aasm column: :aasm_state do
    state :created, initial: true
    state :risk_pending
    state :risk_approved
    state :margin_pending
    state :approved
    state :submitted
    state :acknowledged
    state :partially_filled
    state :filled
    state :cancel_pending
    state :cancelled
    state :rejected
    state :expired
    state :failed

    event :submit_for_risk do
      transitions from: :created, to: :risk_pending
      after { sync_status! }
    end

    event :aasm_approve_risk do
      transitions from: %i[created risk_pending], to: :risk_approved
      after do
        update_column(:risk_approved, true)
        sync_status!
      end
    end

    event :require_margin do
      transitions from: :risk_approved, to: :margin_pending
      after { sync_status! }
    end

    event :aasm_approve_margin do
      transitions from: %i[risk_approved margin_pending], to: :approved
      after do
        update_column(:margin_approved, true)
        sync_status!
      end
    end

    event :skip_risk do
      transitions from: :created, to: :approved
      after { sync_status! }
    end

    event :aasm_submit do
      transitions from: :approved, to: :submitted
      after { sync_status! }
    end

    event :acknowledge do
      transitions from: :submitted, to: :acknowledged
      after { sync_status! }
    end

    event :aasm_fill do
      transitions from: %i[submitted acknowledged partially_filled], to: :filled
      after { sync_status! }
    end

    event :partial_fill do
      transitions from: %i[submitted acknowledged], to: :partially_filled
      after { sync_status! }
    end

    event :request_cancel do
      transitions from: %i[submitted acknowledged partially_filled], to: :cancel_pending
      after { sync_status! }
    end

    event :aasm_cancel do
      transitions from: %i[submitted acknowledged partially_filled cancel_pending], to: :cancelled
      after { sync_status! }
    end

    event :aasm_reject do
      transitions from: %i[created risk_pending submitted acknowledged], to: :rejected
      after { sync_status! }
    end

    event :expire do
      transitions from: %i[submitted acknowledged], to: :expired
      after { sync_status! }
    end

    event :fail do
      transitions from: %i[created submitted acknowledged], to: :failed
      after { sync_status! }
    end
  end

  def buy? = side == "BUY"
  def sell? = side == "SELL"
  def market? = order_type == "MARKET"
  def limit? = order_type == "LIMIT"
  def terminal? = aasm_state.in?(%w[filled cancelled rejected expired failed])

  # Legacy convenience methods that ensure both aasm_state and status are updated.
  # These handle the case where the AASM event may not be available from the current state.
  def approve_risk!
    aasm_approve_risk!
  rescue AASM::InvalidTransition
    update!(risk_approved: true, status: "risk_approved", aasm_state: "risk_approved")
  end

  def approve_margin!
    aasm_approve_margin!
  rescue AASM::InvalidTransition
    update!(margin_approved: true, status: "approved", aasm_state: "approved")
  end

  def reject!(reason)
    update!(rejection_reason: reason)
    aasm_reject!
  rescue AASM::InvalidTransition
    update!(status: "rejected", aasm_state: "rejected", rejection_reason: reason)
  end

  def fill!
    aasm_fill!
  rescue AASM::InvalidTransition
    update!(status: "filled", aasm_state: "filled")
  end

  def submit!
    aasm_submit!
  rescue AASM::InvalidTransition
    update!(status: "submitted", aasm_state: "submitted")
  end

  private

  def sync_status!
    update_column(:status, aasm_state) if status != aasm_state
  end

  def assign_correlation_id
    return if correlation_id.present?

    date_part = Time.current.strftime('%Y%m%d')
    seq = self.class.today.count + 1
    self.correlation_id = format('TRD-%<date_part>s-%<seq>06d', date_part: date_part, seq: seq)
  end
end
