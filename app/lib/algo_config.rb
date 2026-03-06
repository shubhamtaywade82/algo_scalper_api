# frozen_string_literal: true

class AlgoConfig
  CACHE_TTL = 30 # seconds

  class << self
    def fetch
      if @cached_config && @cache_expires_at && Time.current < @cache_expires_at
        return @cached_config
      end

      @cached_config = YAML.load_file(Rails.root.join('config/algo.yml')).deep_symbolize_keys
      @cache_expires_at = Time.current + CACHE_TTL
      @cached_config
    end

    def mode
      fetch[:mode]
    end

    def reset!
      @cached_config = nil
      @cache_expires_at = nil
    end
  end
end
