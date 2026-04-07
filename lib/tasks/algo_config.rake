# frozen_string_literal: true

namespace :algo_config do
  desc 'Rewrite settings.algo_config_document from config/algo.yml (optional merge legacy algo_config_overrides). ' \
       'Set FORCE=1 to replace an existing document.'
  task bootstrap_document: :environment do
    key = AlgoConfig::DocumentStore::DOCUMENT_KEY
    existing = Setting.find_by(key: key)&.value
    if existing.present? && ENV['FORCE'].to_s != '1'
      warn "[algo_config:bootstrap_document] #{key} already present; set FORCE=1 to overwrite"
      next
    end

    yaml_hash = YAML.load_file(Rails.root.join('config/algo.yml')).deep_symbolize_keys
    legacy_raw = Setting.find_by(key: AlgoConfig::DocumentStore::LEGACY_OVERRIDES_KEY)&.value
    doc =
      if legacy_raw.present?
        legacy = JSON.parse(legacy_raw, symbolize_names: true)
        AlgoConfig::MergeUtil.deep_merge_hashes_with_arrays(yaml_hash, legacy)
      else
        yaml_hash
      end

    Setting.put(key, doc.deep_stringify_keys.to_json)
    AlgoConfig.reset!
    AlgoConfigChangeLog.create!(
      source: 'rake_bootstrap_document',
      actor: 'rake',
      request_id: nil,
      patch: { rake_bootstrap: true },
      changed_paths: ['/__rake_bootstrap__'],
      metadata: {}
    )
    puts "[algo_config:bootstrap_document] wrote #{key} (#{doc.keys.size} top-level keys)"
  end
end
