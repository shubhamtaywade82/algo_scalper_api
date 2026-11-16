# frozen_string_literal: true

module Api
  # Masked serialization shared by the variables and strategies APIs.
  # Secret values must never leave the process unmasked.
  module VariableSerialization
    def serialize_variable(variable)
      {
        id: variable.id,
        key: variable.key,
        value: variable.secret ? '•••' : variable.value,
        value_type: variable.value_type,
        secret: variable.secret
      }
    end
  end
end
