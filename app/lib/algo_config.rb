# frozen_string_literal: true

class AlgoConfig
  CACHE_TTL = 30 # seconds

  class << self
    def fetch
      if @cached_config && @cache_expires_at && Time.current < @cache_expires_at
        return @cached_config
      end

      # 1. Canonical document from DB (seeded from config/algo.yml + legacy overrides on first use)
      base_config = AlgoConfig::DocumentStore.current_mutable_document

      @cached_config = base_config
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

    private

    def truthy_signal_flag?(val)
      val == true || val.to_s.strip.casecmp('true').zero?
    end

    def deep_merge_hashes_with_arrays(base, overrides)
      MergeUtil.deep_merge_hashes_with_arrays(base, overrides)
    end

    def merge_arrays(base_arr, override_arr)
      MergeUtil.merge_arrays(base_arr, override_arr)
    end
  end
end
