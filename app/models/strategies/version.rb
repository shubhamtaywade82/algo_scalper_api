# frozen_string_literal: true

module Strategies
  class Version < ApplicationRecord
    self.table_name = "strategy_versions"

    belongs_to :strategy_record, class_name: "Strategies::Record", foreign_key: :strategy_id,
                                 inverse_of: :versions
    has_many :runs, class_name: "Strategies::Run", foreign_key: :strategy_version_id,
                    dependent: :destroy, inverse_of: :strategy_version
    has_many :signals, class_name: "Strategies::Signal", foreign_key: :strategy_version_id,
                       dependent: :destroy, inverse_of: :strategy_version

    validates :version, presence: true,
                        uniqueness: { scope: :strategy_id },
                        numericality: { only_integer: true, greater_than: 0 }
    validates :file_path, presence: true
    validates :checksum, presence: true
    validates :manifest, presence: true

    def resolved_file_path
      return file_path if file_path.present? && File.exist?(file_path)

      if file_path.present?
        rel = file_path.sub(%r{\A.*?/(strategies/.+)\z}, '\1')
        candidate = Rails.root.join(rel).to_s
        return candidate if File.exist?(candidate)
      end

      file_path
    end
  end
end
