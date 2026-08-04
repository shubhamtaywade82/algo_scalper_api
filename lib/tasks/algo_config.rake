# frozen_string_literal: true

namespace :algo_config do
  desc 'Audit DB-canonical algo config vs YAML seed (read-only)'
  task audit: :environment do
    report = AlgoConfig::Audit.run
    puts AlgoConfig::Audit.render(report)

    if Rails.env.production? && !report.ok_for_production?
      warn '[algo_config:audit] FAIL: algo_config_document missing in production'
      exit 1
    end
  end

  desc 'Verify DB-canonical config is present (tier presets, registry, no legacy overrides)'
  task verify_canonical: :environment do
    AlgoConfig::Audit.verify_canonical!
    puts '[algo_config:verify_canonical] OK — DB is canonical'
    puts 'To apply YAML changes: FORCE=1 bundle exec rake algo_config:bootstrap_document'
  rescue StandardError => e
    warn "[algo_config:verify_canonical] FAIL:\n#{e.message}"
    exit 1
  end

  desc 'Rewrite settings.algo_config_document from config/algo.yml (optional merge legacy algo_config_overrides). ' \
       'Set FORCE=1 to replace an existing document.'
  task bootstrap_document: :environment do
    key = AlgoConfig::DocumentStore::DOCUMENT_KEY
    existing = Setting.find_by(key: key)&.value
    if existing.present? && ENV['FORCE'].to_s != '1'
      warn "[algo_config:bootstrap_document] #{key} already present; set FORCE=1 to overwrite"
      next
    end

    doc = AlgoConfig::DocumentStore.force_bootstrap!
    puts "[algo_config:bootstrap_document] wrote #{key} (#{doc.keys.size} top-level keys)"
  end

  desc 'Merge legacy algo_config_overrides into document and archive the legacy key'
  task migrate_legacy_overrides: :environment do
    result = AlgoConfig::LegacyMigrator.migrate!
    case result
    when :migrated
      puts '[algo_config:migrate_legacy_overrides] merged legacy overrides into document and archived'
    when :skipped_no_legacy
      puts '[algo_config:migrate_legacy_overrides] no legacy overrides to migrate'
    end
  end

  desc 'Seed signal_tier_presets and india_index_registry from YAML into settings. Set FORCE=1 to overwrite.'
  task bootstrap_auxiliary: :environment do
    force = ENV['FORCE'].to_s == '1'
    results = AlgoConfig::AuxiliaryBootstrap.bootstrap!(force: force)
    puts "[algo_config:bootstrap_auxiliary] tier_presets=#{results[:tier_presets]} registry=#{results[:registry]}"
  end
end
