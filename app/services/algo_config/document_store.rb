# frozen_string_literal: true

class AlgoConfig
  # Canonical algo config in DB (`settings.algo_config_document`), seeded from +config/algo.yml+.
  # Legacy `algo_config_overrides` is merged once at bootstrap when the document row is empty.
  class DocumentStore
    DOCUMENT_KEY = 'algo_config_document'
    LEGACY_OVERRIDES_KEY = 'algo_config_overrides'
    SENSITIVE_KEY_PATTERN = /token|secret|password|api_key|access_token|client_secret|master_key/

    class << self
      def current_mutable_document
        load_or_bootstrap!.deep_dup
      end

      # Replace entire subtree for each present top-level key (PATCH /api/settings/bulk).
      def apply_top_level_replacements!(replacements, source:, actor: nil, request_id: nil, metadata: {})
        raise ArgumentError, 'replacements must be a Hash' unless replacements.is_a?(Hash)

        return if replacements.blank?

        doc = load_or_bootstrap!.deep_dup
        paths = []
        patch_replace = {}

        replacements.each do |key, value|
          sym = key.to_sym
          normalized = deep_symbolize(value)
          doc[sym] = normalized
          paths << "/#{sym}"
          patch_replace[sym.to_s] = redact_for_audit(normalized)
        end

        persist!(
          doc,
          source: source,
          actor: actor,
          request_id: request_id,
          patch: { replace: patch_replace },
          changed_paths: paths,
          metadata: metadata
        )
      end

      # Re-seed from YAML + legacy overrides, replacing the existing document.
      # Used by rake task and deployment scripts.
      def force_bootstrap!(source: 'rake_bootstrap_document', actor: 'rake')
        merged = build_bootstrap_document
        persist!(
          merged,
          source: source,
          actor: actor,
          request_id: nil,
          patch: { forced_bootstrap: true, legacy_merged: legacy_overrides_present? },
          changed_paths: ['/__forced_bootstrap__'],
          metadata: {}
        )
        merged
      end

      # Deep-merge a partial patch (e.g. CalibrationRun#proposed_patch) into the document.
      def apply_deep_merge_patch!(patch, source:, actor: nil, request_id: nil, metadata: {})
        raise ArgumentError, 'patch must be a Hash' unless patch.is_a?(Hash)

        doc = load_or_bootstrap!.deep_dup
        sym_patch = deep_symbolize(patch)
        merged = MergeUtil.deep_merge_hashes_with_arrays(doc, sym_patch)

        paths = sym_patch.keys.map { |k| "/#{k}" }

        persist!(
          merged,
          source: source,
          actor: actor,
          request_id: request_id,
          patch: { deep_merge: redact_for_audit(sym_patch) },
          changed_paths: paths.presence || ['__deep_merge__'],
          metadata: metadata
        )
      end

      private

      def load_or_bootstrap!
        json = Setting.fetch(DOCUMENT_KEY, nil, ttl: AlgoConfig::CACHE_TTL)
        return parse_document!(json) if json.present?

        bootstrap_with_lock!
      rescue ActiveRecord::StatementInvalid => e
        Rails.logger.warn("[AlgoConfig::DocumentStore] DB not ready (#{e.class}); falling back to YAML seed")
        yaml_seed_hash
      end

      def parse_document!(json)
        parsed = JSON.parse(json, symbolize_names: true)
        return parsed if parsed.is_a?(Hash)

        Rails.logger.warn('[AlgoConfig::DocumentStore] algo_config_document not a Hash; re-bootstrapping')
        bootstrap_with_lock!
      end

      def bootstrap_with_lock!
        Setting.transaction do
          existing = Setting.find_by(key: DOCUMENT_KEY)&.value
          if existing.present?
            parsed = JSON.parse(existing, symbolize_names: true)
            return parsed if parsed.is_a?(Hash)
          end

          merged = build_bootstrap_document
          persist!(
            merged,
            source: 'bootstrap_cutover',
            actor: 'system',
            request_id: nil,
            patch: {
              bootstrap: true,
              legacy_algo_config_overrides_merged: legacy_overrides_present?
            },
            changed_paths: ['/__bootstrap__'],
            metadata: {}
          )
          merged
        end
      end

      def build_bootstrap_document
        yaml_hash = yaml_seed_hash
        legacy_raw = Setting.find_by(key: LEGACY_OVERRIDES_KEY)&.value
        return yaml_hash if legacy_raw.blank?

        legacy = JSON.parse(legacy_raw, symbolize_names: true)
        MergeUtil.deep_merge_hashes_with_arrays(yaml_hash, legacy)
      rescue StandardError => e
        Rails.logger.error("[AlgoConfig::DocumentStore] bootstrap build failed: #{e.class} - #{e.message}")
        yaml_seed_hash
      end

      def yaml_seed_hash
        YAML.load_file(Rails.root.join('config/algo.yml')).deep_symbolize_keys
      end

      def legacy_overrides_present?
        Setting.find_by(key: LEGACY_OVERRIDES_KEY)&.value.present?
      end

      def persist!(document, source:, patch:, changed_paths:, actor: nil, request_id: nil, metadata: {})
        AlgoConfig::Validator.validate!(document, changed_paths: changed_paths)
        Setting.put(DOCUMENT_KEY, document.deep_stringify_keys.to_json)
        AlgoConfigChangeLog.create!(
          source: source,
          actor: actor,
          request_id: request_id,
          patch: patch.deep_stringify_keys,
          changed_paths: Array(changed_paths),
          metadata: metadata.deep_stringify_keys
        )
        AlgoConfig.reset!
        Rails.logger.info(
          "[AlgoConfig::DocumentStore] persisted #{DOCUMENT_KEY} source=#{source} " \
          "paths=#{Array(changed_paths).join(',')}"
        )
      end

      def deep_symbolize(obj)
        case obj
        when Hash
          obj.transform_keys(&:to_sym).transform_values { |v| deep_symbolize(v) }
        when Array
          obj.map { |e| deep_symbolize(e) }
        else
          obj
        end
      end

      def redact_for_audit(obj)
        case obj
        when Hash
          obj.each_with_object({}) do |(k, v), h|
            key_str = k.to_s
            h[key_str] =
              if key_str.downcase.match?(SENSITIVE_KEY_PATTERN)
                '[REDACTED]'
              else
                redact_for_audit(v)
              end
          end
        when Array
          obj.map { |e| redact_for_audit(e) }
        else
          obj
        end
      end
    end
  end
end
