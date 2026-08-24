# frozen_string_literal: true

class LegGroup < ApplicationRecord
  belongs_to :instrument, optional: true
  has_many :position_trackers, dependent: :nullify

  STATUSES = %w[pending active partial closed cancelled failed].freeze

  validates :group_id, presence: true, uniqueness: true
  validates :strategy_type, presence: true
  validates :underlying_symbol, presence: true
  validates :expiry, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :active, -> { where(status: 'active') }
  scope :pending, -> { where(status: 'pending') }
  scope :closed, -> { where(status: 'closed') }

  def self.create_from_executor_result!(result, instrument:, strategy_type:, expiry:, quantity:)
    group_id = result[:group_id] || "LG_#{SecureRandom.hex(6).upcase}"

    transaction do
      group = create!(
        group_id: group_id,
        instrument: instrument,
        strategy_type: strategy_type,
        underlying_symbol: instrument&.underlying_symbol || instrument&.symbol_name || 'NIFTY',
        expiry: expiry,
        quantity: quantity,
        status: 'active',
        meta: {
          legs_count: result[:legs]&.size || 0,
          created_via: 'MultiLegExecutor'
        }
      )

      Array(result[:legs]).each_with_index do |filled_leg, idx|
        leg_data = filled_leg[:leg] || {}
        tracker = PositionTracker.find_by(client_order_id: filled_leg[:coid]) ||
                  PositionTracker.find_by(order_no: filled_leg[:coid])

        next unless tracker
        tracker.update!(
          leg_group_id: group.id,
          leg_index: idx,
          leg_role: leg_data[:type].to_s,
          premium_received: leg_data[:action] == 'sell' ? (filled_leg.dig(:result, :fill_price) || 0) : 0
        )
      end

      group
    end
  end

  def active?
    status == 'active'
  end

  def closed?
    status == 'closed'
  end

  def net_pnl_rupees
    position_trackers.sum { |t| t.current_pnl_rupees.to_f }
  end

  def close!(reason: 'strategy_exit')
    transaction do
      position_trackers.active.each do |t|
        t.update!(status: :exited, exit_reason: reason, exited_at: Time.current)
      end
      update!(status: 'closed', meta: meta.merge(closed_at: Time.current, close_reason: reason))
    end
  end
end
