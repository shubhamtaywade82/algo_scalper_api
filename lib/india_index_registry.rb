# frozen_string_literal: true

# Loads index registry from DB (settings.india_index_registry), seeded from
# config/india_index_registry.yml at bootstrap. Merges canonical identity into algo indices.
class IndiaIndexRegistry
  REGISTRY_PATH = 'config/india_index_registry.yml'
  REGISTRY_SETTING_KEY = AlgoConfig::REGISTRY_SETTING_KEY

  class << self
    def merge_into(index_cfg)
      overlay = deep_symbolize(index_cfg)
      key = overlay[:key].to_s.upcase
      return overlay if key.blank?

      base = for_key(key)
      return overlay unless base

      merged = deep_merge(base, overlay)
      apply_canonical_identity!(merged, base)
      merged
    end

    def merge_indices!(indices)
      Array(indices).map { |entry| merge_into(entry) }
    end

    def for_key(key)
      all_by_key[key.to_s.upcase]
    end

    def all_by_key
      load_registry[:indices] || {}
    end

    def reset!
      @registry = nil
    end

    private

    def apply_canonical_identity!(merged, base)
      merged[:key] = base[:key]
      merged[:segment] = base[:segment]
      merged[:sid] = base[:sid].to_s
      merged[:exchange] = base[:exchange] if base[:exchange]
      merged[:fno_segment] = base[:fno_segment] if base[:fno_segment]
      merged[:lot] ||= base[:lot]
      merged[:strike_step] ||= base[:strike_step]
    end

    def load_registry
      return @registry if @registry

      db_raw = Setting.fetch(REGISTRY_SETTING_KEY, nil, ttl: AlgoConfig::CACHE_TTL)
      if db_raw.present?
        raw = JSON.parse(db_raw, symbolize_names: true)
        @registry = normalize_registry(raw)
        return @registry
      end

      path = Rails.root.join(REGISTRY_PATH)
      unless File.exist?(path)
        Rails.logger.warn("[IndiaIndexRegistry] Missing #{REGISTRY_PATH}; skipping registry merge")
        @registry = { indices: {} }
        return @registry
      end

      raw = YAML.load_file(path).deep_symbolize_keys
      @registry = normalize_registry(raw)
    rescue StandardError => e
      Rails.logger.error("[IndiaIndexRegistry] Failed to load registry: #{e.class} - #{e.message}")
      @registry = { indices: {} }
    end

    def normalize_registry(raw)
      indices = Array(raw[:indices].values).index_by { |entry| entry[:key].to_s.upcase }
      { indices: indices }
    end

    def deep_symbolize(value)
      case value
      when Hash
        value.deep_symbolize_keys
      else
        value
      end
    end

    def deep_merge(base, overlay)
      base.merge(overlay) do |_key, base_val, overlay_val|
        if base_val.is_a?(Hash) && overlay_val.is_a?(Hash)
          deep_merge(base_val, overlay_val)
        else
          overlay_val.nil? ? base_val : overlay_val
        end
      end
    end
  end
end
