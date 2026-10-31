# frozen_string_literal: true

# == Schema Information
#
# Table name: investment_policy_sleeves
#
#  id                   :bigint           not null, primary key
#  investment_policy_id :bigint           not null
#  sleeve_key           :string(64)       not null
#  group_key            :string(64)       not null
#  target_pct           :decimal(7, 4)    not null
#  instrument_filter    :jsonb            not null
#  position             :integer          default(0), not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#
# One allocation target row per policy version (TDD §3.3 D2). Sleeve keys are
# an open vocabulary (mandates evolve); the canonical balanced set is defined
# in config/investing.yml and compiled into rows at install time.
class InvestmentPolicySleeve < ApplicationRecord
  validates :sleeve_key,
            presence: true,
            uniqueness: { scope: :investment_policy_id },
            format: { with: /\A[a-z0-9_]+\z/,
                      message: :invalid_sleeve_key },
            length: { maximum: 64 }
  validates :group_key,
            presence: true,
            format: { with: /\A[a-z0-9_]+\z/,
                      message: :invalid_group_key },
            length: { maximum: 64 }
  validates :target_pct,
            numericality: { greater_than: 0,
                            less_than_or_equal_to: 100 }

  belongs_to :investment_policy, inverse_of: :sleeves

  scope :in_display_order, -> { order(:position, :id) }
end
