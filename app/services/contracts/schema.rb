# frozen_string_literal: true

module Contracts
  # Validates payloads against the versioned JSON Schemas in contracts/schemas, the same files
  # options-trading-agent vendors, so both sides of a cross-service contract check one definition.
  module Schema
    DIR = Rails.root.join('contracts/schemas')

    # @return [Array<String>] human-readable validation errors; empty when the payload conforms
    def self.errors(name, payload)
      validator(name).validate(payload.as_json).pluck('error')
    end

    def self.validator(name)
      @validators ||= Concurrent::Map.new
      @validators.compute_if_absent(name) { JSONSchemer.schema(DIR.join("#{name}.schema.json")) }
    end
  end
end
