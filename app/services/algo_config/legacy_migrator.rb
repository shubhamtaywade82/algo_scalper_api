# frozen_string_literal: true

class AlgoConfig
  # One-time merge of legacy sparse overrides into the canonical DB document.
  class LegacyMigrator
    LEGACY_KEY = DocumentStore::LEGACY_OVERRIDES_KEY
    ARCHIVED_KEY = 'algo_config_overrides_archived'

    class << self
      def migrate!
        legacy_row = Setting.find_by(key: LEGACY_KEY)
        return :skipped_no_legacy if legacy_row&.value.blank?

        unless document_present?
          AlgoConfig::DocumentStore.force_bootstrap!
        end

        legacy = JSON.parse(legacy_row.value, symbolize_names: true)
        AlgoConfig::DocumentStore.apply_deep_merge_patch!(
          legacy,
          source: 'migrate_legacy_overrides',
          actor: 'rake',
          metadata: { archived_from: LEGACY_KEY }
        )

        Setting.put(ARCHIVED_KEY, legacy_row.value)
        legacy_row.destroy!
        Rails.cache.delete("setting:#{LEGACY_KEY}")

        :migrated
      rescue StandardError => e
        Rails.logger.error("[AlgoConfig::LegacyMigrator] #{e.class} - #{e.message}")
        raise
      end

      private

      def document_present?
        Setting.find_by(key: DocumentStore::DOCUMENT_KEY)&.value.present?
      end
    end
  end
end
