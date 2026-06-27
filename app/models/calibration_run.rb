# frozen_string_literal: true

class CalibrationRun < ApplicationRecord
  validates :symbol, presence: true

  scope :pending, -> { where(applied_at: nil) }
  scope :applied, -> { where.not(applied_at: nil) }

  def apply!(applied_by: 'api')
    raise 'already applied' if applied_at.present?

    AlgoConfig::DocumentStore.apply_deep_merge_patch!(
      proposed_patch.deep_symbolize_keys,
      source: 'calibration_run_apply',
      actor: applied_by,
      request_id: nil,
      metadata: { calibration_run_id: id, symbol: symbol }
    )
    update!(applied_at: Time.current, applied_by: applied_by)
  end

  def propose_config!
    return unless defined?(AlgoConfigVersion)

    AlgoConfigVersion.create!(
      name: "calibration-#{symbol.downcase}-#{created_at.strftime('%Y%m%d')}",
      overrides: proposed_patch,
      source: 'calibration',
      calibration_run_id: id
    )
  end
end
