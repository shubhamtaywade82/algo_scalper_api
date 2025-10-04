# frozen_string_literal: true

class Derivative < ApplicationRecord
  belongs_to :instrument

  CALL = "CE"
  PUT = "PE"

  scope :calls, -> { where(option_type: CALL) }
  scope :puts, -> { where(option_type: PUT) }
  scope :expiring_on, ->(date) { where(expiry_date: date) }
  scope :upcoming, -> { where("expiry_date >= ?", Date.current).order(:expiry_date) }

  validates :security_id, presence: true, uniqueness: true
  validates :strike_price, presence: true, numericality: { greater_than: 0 }
  validates :expiry_date, presence: true
  validates :option_type, presence: true, inclusion: { in: [ CALL, PUT ] }
  validates :lot_size, numericality: { greater_than: 0 }
  validates :exchange_segment, presence: true

  def call?
    option_type == CALL
  end

  def put?
    option_type == PUT
  end
end
