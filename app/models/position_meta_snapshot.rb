# frozen_string_literal: true

class PositionMetaSnapshot < ApplicationRecord
  belongs_to :position_tracker

  validates :config_version_hash, presence: true
  validates :config_snapshot, presence: true
  validates :position_tracker_id, uniqueness: true
end
