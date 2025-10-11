# frozen_string_literal: true

class AlgoConfig
  class << self
    def fetch
      @cfg ||= YAML.load_file(Rails.root.join("config/algo.yml")).deep_symbolize_keys
    end

    def mode
      fetch[:mode]
    end
  end
end
