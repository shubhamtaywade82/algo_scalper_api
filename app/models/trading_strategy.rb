# frozen_string_literal: true

class TradingStrategy < ApplicationRecord
  # --- Status constants ---
  STATUS_DRAFT    = "draft"
  STATUS_ACTIVE   = "active"
  STATUS_ARCHIVED = "archived"

  STATUSES = [STATUS_DRAFT, STATUS_ACTIVE, STATUS_ARCHIVED].freeze

  belongs_to :strategy_record, class_name: "Strategies::Record", optional: true

  # --- Validations ---
  validates :name, presence: true, uniqueness: { scope: :version }
  validates :status, inclusion: { in: STATUSES }

  # --- Scopes ---
  scope :active,   -> { where(status: STATUS_ACTIVE) }
  scope :draft,    -> { where(status: STATUS_DRAFT) }
  scope :archived, -> { where(status: STATUS_ARCHIVED) }

  def slugify
    name.to_s.parameterize.presence || "strategy-#{id || 'new'}"
  end

  def deployed?
    strategy_record_id.present?
  end

  # Runs real syntax/security/backtest checks and persists results.
  def run_checks!
    result = Strategies::AdHocBacktester.new(self).run
    self.checks = result[:checks]
    self.backtest_results = result[:backtest_results]
    save!
    result
  end
end
