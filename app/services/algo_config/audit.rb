# frozen_string_literal: true

class AlgoConfig
  # Read-only audit of DB-canonical config vs YAML seed and legacy settings.
  class Audit
    LEGACY_OVERRIDES_KEY = DocumentStore::LEGACY_OVERRIDES_KEY
    LEGACY_ARCHIVED_KEY = 'algo_config_overrides_archived'
    TIER_PRESETS_KEY = AlgoConfig::TIER_PRESETS_SETTING_KEY
    REGISTRY_KEY = AlgoConfig::REGISTRY_SETTING_KEY

    Report = Struct.new(
      :document_present,
      :document_byte_size,
      :document_top_level_keys,
      :yaml_top_level_keys,
      :missing_in_document,
      :extra_in_document,
      :latest_change_log_id,
      :legacy_overrides_present,
      :legacy_archived_present,
      :tier_presets_in_db,
      :registry_in_db,
      :yaml_mtime,
      :last_change_log_at,
      :yaml_newer_than_last_change,
      keyword_init: true
    ) do
      def ok_for_production?
        document_present
      end
    end

    class << self
      def run
        doc_raw = Setting.find_by(key: DocumentStore::DOCUMENT_KEY)&.value
        doc = parse_json_hash(doc_raw)
        yaml_keys = yaml_seed_keys
        doc_keys = doc&.keys&.map(&:to_sym) || []

        legacy = Setting.find_by(key: LEGACY_OVERRIDES_KEY)&.value
        archived = Setting.find_by(key: LEGACY_ARCHIVED_KEY)&.value
        latest_log = AlgoConfigChangeLog.order(id: :desc).first

        yaml_path = Rails.root.join('config/algo.yml')
        yaml_mtime = File.exist?(yaml_path) ? File.mtime(yaml_path) : nil
        last_change_at = latest_log&.created_at

        Report.new(
          document_present: doc.present?,
          document_byte_size: doc_raw&.bytesize || 0,
          document_top_level_keys: doc_keys.sort,
          yaml_top_level_keys: yaml_keys.sort,
          missing_in_document: (yaml_keys - doc_keys).sort,
          extra_in_document: (doc_keys - yaml_keys).sort,
          latest_change_log_id: latest_log&.id,
          legacy_overrides_present: legacy.present?,
          legacy_archived_present: archived.present?,
          tier_presets_in_db: Setting.find_by(key: TIER_PRESETS_KEY)&.value.present?,
          registry_in_db: Setting.find_by(key: REGISTRY_KEY)&.value.present?,
          yaml_mtime: yaml_mtime,
          last_change_log_at: last_change_at,
          yaml_newer_than_last_change: yaml_newer_than_change?(yaml_mtime, last_change_at)
        )
      end

      def render(report = run)
        lines = []
        lines << 'ALGO CONFIG AUDIT'
        lines << ('-' * 80)
        lines << "Document present: #{report.document_present}"
        lines << "Document size: #{report.document_byte_size} bytes"
        lines << "Document top-level keys (#{report.document_top_level_keys.size}): " \
                 "#{report.document_top_level_keys.join(', ')}"
        lines << "YAML top-level keys (#{report.yaml_top_level_keys.size}): " \
                 "#{report.yaml_top_level_keys.join(', ')}"
        lines << "Missing in document: #{report.missing_in_document.presence || '(none)'}"
        lines << "Extra in document: #{report.extra_in_document.presence || '(none)'}"
        lines << "Latest change log id: #{report.latest_change_log_id || '(none)'}"
        lines << "Legacy algo_config_overrides present: #{report.legacy_overrides_present}"
        lines << "Legacy archived present: #{report.legacy_archived_present}"
        lines << "Tier presets in DB: #{report.tier_presets_in_db}"
        lines << "Index registry in DB: #{report.registry_in_db}"
        if report.yaml_mtime
          lines << "config/algo.yml mtime: #{report.yaml_mtime.iso8601}"
        end
        if report.last_change_log_at
          lines << "Last config change: #{report.last_change_log_at.iso8601}"
        end
        if report.yaml_newer_than_last_change
          lines << 'WARNING: YAML is newer than last DB change — run algo_config:bootstrap_document if intentional'
        end
        lines.join("\n")
      end

      def verify_canonical!(report = run)
        errors = []
        errors << 'algo_config_document missing — run FORCE=1 bundle exec rake algo_config:bootstrap_document' unless report.document_present
        errors << 'signal_tier_presets missing in DB — run bundle exec rake algo_config:bootstrap_auxiliary' unless report.tier_presets_in_db
        errors << 'india_index_registry missing in DB — run bundle exec rake algo_config:bootstrap_auxiliary' unless report.registry_in_db
        errors << 'legacy algo_config_overrides still present — run bundle exec rake algo_config:migrate_legacy_overrides' if report.legacy_overrides_present

        if errors.any?
          raise StandardError, errors.join("\n")
        end

        warn render(report) if report.yaml_newer_than_last_change
        true
      end

      private

      def yaml_seed_keys
        YAML.load_file(Rails.root.join('config/algo.yml')).keys.map(&:to_sym)
      rescue StandardError
        []
      end

      def parse_json_hash(raw)
        return nil if raw.blank?

        parsed = JSON.parse(raw, symbolize_names: true)
        parsed.is_a?(Hash) ? parsed : nil
      rescue StandardError
        nil
      end

      def yaml_newer_than_change?(yaml_mtime, last_change_at)
        return false unless yaml_mtime && last_change_at

        yaml_mtime > last_change_at
      end
    end
  end
end
