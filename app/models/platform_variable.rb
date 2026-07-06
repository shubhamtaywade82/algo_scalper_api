# frozen_string_literal: true

class PlatformVariable < ApplicationRecord
  self.table_name = "platform_variables"

  VALUE_TYPES = %w[string decimal boolean json].freeze

  validates :key, presence: true, uniqueness: true
  validates :value_type, presence: true, inclusion: { in: VALUE_TYPES }

  def value
    case value_type
    when "string"  then string_value
    when "decimal" then decimal_value
    when "boolean" then boolean_value
    when "json"    then json_value
    end
  end
end
