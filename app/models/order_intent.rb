# frozen_string_literal: true

# OrderIntent represents a strategy's desire to trade.
# It is the bridge between signal generation and order execution.
# Strategies produce intents; the execution layer decides paper vs live routing.
class OrderIntent < ApplicationRecord
  belongs_to :instrument

  SIDES = %w[BUY SELL].freeze
  ORDER_TYPES = %w[MARKET LIMIT SL SLM].freeze
  PRODUCT_TYPES = %w[INTRADAY CNC MARGIN].freeze
  VALIDITIES = %w[DAY IOC].freeze
  STATUSES = %w[created risk_pending risk_approved margin_pending approved
                submitted filled partially_filled cancelled rejected expired failed].freeze

  validates :strategy_name, presence: true
  validates :side, presence: true, inclusion: { in: SIDES }
  validates :quantity, presence: true, numericality: { greater_than: 0, only_integer: true }
  validates :order_type, inclusion: { in: ORDER_TYPES }
  validates :product_type, inclusion: { in: PRODUCT_TYPES }
  validates :validity, inclusion: { in: VALIDITIES }
  validates :status, inclusion: { in: STATUSES }
  validates :limit_price, numericality: { greater_than: 0 }, allow_nil: true
  validates :trigger_price, numericality: { greater_than: 0 }, allow_nil: true

  scope :pending, -> { where(status: %w[created risk_pending margin_pending]) }
  scope :approved, -> { where(status: 'approved') }
  scope :terminal, -> { where(status: %w[filled cancelled rejected expired failed]) }
  scope :active, -> { where.not(status: %w[filled cancelled rejected expired failed]) }
  scope :for_strategy, ->(name) { where(strategy_name: name) }
  scope :today, -> { where(created_at: Time.current.beginning_of_day..) }

  before_create :assign_correlation_id

  def buy? = side == 'BUY'
  def sell? = side == 'SELL'
  def market? = order_type == 'MARKET'
  def limit? = order_type == 'LIMIT'
  def terminal? = %w[filled cancelled rejected expired failed].include?(status)

  def approve_risk!
    update!(risk_approved: true, status: 'risk_approved')
  end

  def approve_margin!
    update!(margin_approved: true, status: 'approved')
  end

  def reject!(reason)
    update!(status: 'rejected', rejection_reason: reason)
  end

  def submit!
    update!(status: 'submitted')
  end

  def fill!
    update!(status: 'filled')
  end

  private

  def assign_correlation_id
    return if correlation_id.present?

    date_part = Time.current.strftime('%Y%m%d')
    seq = self.class.today.count + 1
    self.correlation_id = format('TRD-%<date_part>s-%<seq>06d', date_part: date_part, seq: seq)
  end
end
