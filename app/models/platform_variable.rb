# frozen_string_literal: true

class PlatformVariable < ApplicationRecord
  self.table_name = "platform_variables"

  VALUE_TYPES = %w[string decimal boolean json].freeze

  validates :key, presence: true, uniqueness: { scope: %i[scope strategy_id] }
  validates :value_type, presence: true, inclusion: { in: VALUE_TYPES }
  validates :scope, presence: true, inclusion: { in: %w[global strategy] }

  scope :global, -> { where(scope: "global", strategy_id: nil) }
  scope :for_strategy, ->(strategy_id) { where(scope: "strategy", strategy_id: strategy_id) }

  def value
    case value_type
    when "string"  then string_value
    when "decimal" then decimal_value
    when "boolean" then boolean_value
    when "json"    then json_value
    end
  end
end
