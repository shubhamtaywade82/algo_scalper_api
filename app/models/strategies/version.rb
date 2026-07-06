# frozen_string_literal: true

module Strategies
  class Version < ApplicationRecord
    self.table_name = "strategy_versions"

    belongs_to :strategy, class_name: "Strategies::Record"
    has_many :runs, class_name: "Strategies::Run", dependent: :destroy
    has_many :signals, class_name: "Strategies::Signal", dependent: :destroy

    validates :version, presence: true,
                        uniqueness: { scope: :strategy_id },
                        numericality: { only_integer: true, greater_than: 0 }
    validates :file_path, presence: true
    validates :checksum, presence: true
    validates :manifest, presence: true
  end
end
