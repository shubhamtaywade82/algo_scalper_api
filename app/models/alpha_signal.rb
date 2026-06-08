# frozen_string_literal: true

class AlphaSignal < ApplicationRecord
  validates :index_key, presence: true
  validates :direction, presence: true
  validates :alpha_source, presence: true
  validates :status, inclusion: { in: %w[pending executed rejected expired failed] }

  scope :pending, -> { where(status: 'pending') }
  scope :executed, -> { where(status: 'executed') }
  scope :recent, -> { order(created_at: :desc) }

  def executed?
    status == 'executed'
  end

  def pending?
    status == 'pending'
  end
end
