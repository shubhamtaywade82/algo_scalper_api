# frozen_string_literal: true

class AlgoConfig
  # Seeds auxiliary config (tier presets, index registry) from YAML into settings.
  class AuxiliaryBootstrap
    TIER_PRESETS_PATH = 'config/signal_tier_presets.yml'
    REGISTRY_PATH = 'config/india_index_registry.yml'

    class << self
      def bootstrap!(force: false)
        results = {}
        results[:tier_presets] = bootstrap_tier_presets!(force: force)
        results[:registry] = bootstrap_registry!(force: force)
        results
      end

      def bootstrap_tier_presets!(force: false)
        key = AlgoConfig::TIER_PRESETS_SETTING_KEY
        return :skipped if Setting.find_by(key: key)&.value.present? && !force

        payload = YAML.load_file(Rails.root.join(TIER_PRESETS_PATH))
        Setting.put(key, payload.to_json)
        :written
      end

      def bootstrap_registry!(force: false)
        key = AlgoConfig::REGISTRY_SETTING_KEY
        return :skipped if Setting.find_by(key: key)&.value.present? && !force

        payload = YAML.load_file(Rails.root.join(REGISTRY_PATH))
        Setting.put(key, payload.to_json)
        IndiaIndexRegistry.reset!
        :written
      end
    end
  end
end
