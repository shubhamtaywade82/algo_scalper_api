# frozen_string_literal: true

# == Schema Information
#
# Table name: algo_config_change_logs
#
#  id            :bigint           not null, primary key
#  source        :string           not null
#  actor         :string
#  request_id    :string
#  patch         :jsonb            not null
#  changed_paths :string           is an Array
#  metadata      :jsonb            not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#

class AlgoConfigChangeLog < ApplicationRecord
  validates :source, presence: true

  scope :recent_first, -> { order(created_at: :desc) }
end
