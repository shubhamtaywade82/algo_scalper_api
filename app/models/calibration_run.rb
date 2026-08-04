# frozen_string_literal: true

class CalibrationRun < ApplicationRecord
  validates :symbol, presence: true

  scope :pending, -> { where(applied_at: nil) }
  scope :applied, -> { where.not(applied_at: nil) }

  # Deep-merges proposed_patch into +settings.algo_config_document+ via
  # +AlgoConfig::DocumentStore+ (Solid Cache bust via +Setting.put+, in-process cache via +AlgoConfig.reset!+).
  # Raises if already applied (idempotency guard).
  # Uses with_lock to prevent race conditions when multiple requests apply concurrently.
  def apply!(applied_by: 'api')
    raise 'already applied' if applied_at.present?

      AlgoConfig::DocumentStore.apply_deep_merge_patch!(
        proposed_patch,
        source: 'calibration_apply',
        actor: applied_by,
        request_id: nil,
        metadata: { calibration_run_id: id }
      )
      update!(applied_at: Time.current, applied_by: applied_by)
    end
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
