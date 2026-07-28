# frozen_string_literal: true

require 'yaml'

module ArchitectureGate
  class Config
    attr_reader :raw_data

    def self.load(path = "config/architecture_gate.yml")
      data = File.exist?(path) ? YAML.load_file(path) : {}
      new(data)
    end

    def initialize(raw_data)
      @raw_data = raw_data || {}
    end

    def complexity
      @raw_data["complexity"] || {}
    end

    def class_loc_max
      complexity["class_loc_max"] || 300
    end

    def method_loc_max
      complexity["method_loc_max"] || 40
    end

    def method_branches_max
      complexity["method_branches_max"] || 8
    end

    def layers
      @raw_data.dig("layers", "rules") || {}
    end

    def domain_purity_forbidden
      @raw_data.dig("domain_purity", "forbidden_patterns") || []
    end

    def max_callback_chain_depth
      @raw_data.dig("callbacks", "max_callback_chain_depth") || 4
    end

    def forbid_external_in_callbacks
      @raw_data.dig("callbacks", "forbid_external_in_callbacks") || false
    end

    def float_money_forbidden_in
      @raw_data.dig("money", "forbidden_in") || []
    end

    def float_money_allowed_in
      @raw_data.dig("money", "allowed_in") || []
    end

    def regression_rules
      @raw_data.dig("regression", "no_increase") || []
    end
  end
end
