# frozen_string_literal: true

# == Schema Information
#
# Table name: calibration_runs
#
#  id              :integer   not null, primary key
#  symbol          :string    not null
#  weeks_analyzed  :integer   not null, default: 52
#  strike_mode     :string    not null, default: "atm_plus_minus"
#  raw_stats       :jsonb     not null, default: {}
#  proposed_patch  :jsonb     not null, default: {}
#  is_regime_shift :boolean   not null, default: false
#  regime_reason   :string
#  applied_at      :datetime
#  applied_by      :string
#  created_at      :datetime  not null
#  updated_at      :datetime  not null
#

class CalibrationRun < ApplicationRecord
  validates :symbol, presence: true

  scope :pending,  -> { where(applied_at: nil) }
  scope :applied,  -> { where.not(applied_at: nil) }

  # Merges proposed_patch into algo_config_overrides and busts both caches.
  # Uses Setting.put (not upsert) so Solid Cache entry for
  # "setting:algo_config_overrides" is busted immediately.
  # Calls AlgoConfig.reset! to bust the 30-second in-process config cache.
  # Raises if already applied (idempotency guard).
  # Uses with_lock to prevent race conditions when multiple requests apply concurrently.
  def apply!(applied_by: 'api')
    with_lock do
      reload
      raise 'already applied' if applied_at.present?

      current = JSON.parse(Setting.find_by(key: 'algo_config_overrides')&.value || '{}')
      # proposed_patch from JSONB is already string-keyed; deep_merge is safe
      # (CalibrationConfigPatchBuilder never emits array-valued keys)
      merged = current.deep_merge(proposed_patch)
      Setting.put('algo_config_overrides', merged.to_json)
      AlgoConfig.reset!
      update!(applied_at: Time.current, applied_by: applied_by)
    end
  end

  # No-op pre-versioning. When AlgoConfigVersion lands, creates a version record.
  # No controller or job changes needed at that point.
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
