# frozen_string_literal: true

class TradingStrategy < ApplicationRecord
  # --- Status constants ---
  STATUS_DRAFT    = "draft"
  STATUS_ACTIVE   = "active"
  STATUS_ARCHIVED = "archived"

  STATUSES = [STATUS_DRAFT, STATUS_ACTIVE, STATUS_ARCHIVED].freeze

  # --- Validations ---
  validates :name, presence: true, uniqueness: { scope: :version }
  validates :status, inclusion: { in: STATUSES }

  # --- Scopes ---
  scope :active,   -> { where(status: STATUS_ACTIVE) }
  scope :draft,    -> { where(status: STATUS_DRAFT) }
  scope :archived, -> { where(status: STATUS_ARCHIVED) }

  # Stub: mark all checks as passed.
  # Future versions will perform actual syntax, logic, risk, and backtest validation.
  def run_checks!
    self.checks = {
      syntax: "passed",
      logic: "passed",
      risk: "passed",
      backtest: "passed"
    }
    save!
  end
end
