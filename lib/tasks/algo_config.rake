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

  desc 'Profitability Slice 2 — enable midday session blackout + selective signal tier (DB document)'
  task apply_slice2: :environment do
    AlgoConfig::ProfitabilitySlice2.apply!
    status = AlgoConfig::ProfitabilitySlice2.status
    puts '[algo_config:apply_slice2] applied'
    puts "  trading_time_restrictions.enabled=#{status[:trading_time_restrictions_enabled]}"
    puts "  avoid_periods=#{status[:avoid_periods].inspect}"
    puts "  signals.signal_tier=#{status[:signal_tier]}"
  end

  desc 'Rollback Profitability Slice 2 (disable blackout, restore exploratory tier)'
  task rollback_slice2: :environment do
    AlgoConfig::ProfitabilitySlice2.rollback!
    status = AlgoConfig::ProfitabilitySlice2.status
    puts '[algo_config:rollback_slice2] rolled back'
    puts "  trading_time_restrictions.enabled=#{status[:trading_time_restrictions_enabled]}"
    puts "  signals.signal_tier=#{status[:signal_tier]}"
  end

  desc 'Profitability Slice 3 — pause SENSEX (max_trades_per_day=0 in DB document)'
  task apply_slice3: :environment do
    AlgoConfig::ProfitabilitySlice3.apply!
    status = AlgoConfig::ProfitabilitySlice3.status
    puts '[algo_config:apply_slice3] applied'
    puts "  sensex_max_trades_per_day=#{status[:sensex_max_trades_per_day]}"
    puts "  sensex_paused=#{status[:sensex_paused]}"
  end

  desc 'Rollback Profitability Slice 3 (restore SENSEX max_trades_per_day=2)'
  task rollback_slice3: :environment do
    AlgoConfig::ProfitabilitySlice3.rollback!
    status = AlgoConfig::ProfitabilitySlice3.status
    puts '[algo_config:rollback_slice3] rolled back'
    puts "  sensex_max_trades_per_day=#{status[:sensex_max_trades_per_day]}"
    puts "  sensex_paused=#{status[:sensex_paused]}"
  end

  desc 'Profitability Slice 4 — tighten catastrophic exit (hard_stop -0.08, sl_pct 0.08)'
  task apply_slice4: :environment do
    AlgoConfig::ProfitabilitySlice4.apply!
    status = AlgoConfig::ProfitabilitySlice4.status
    puts '[algo_config:apply_slice4] applied'
    puts "  risk.sl_pct=#{status[:sl_pct]}"
    puts "  entry_guard.hard_stop=#{status[:entry_guard_hard_stop]}"
  end

  desc 'Rollback Profitability Slice 4 (restore hard_stop -0.30, sl_pct 0.10)'
  task rollback_slice4: :environment do
    AlgoConfig::ProfitabilitySlice4.rollback!
    status = AlgoConfig::ProfitabilitySlice4.status
    puts '[algo_config:rollback_slice4] rolled back'
    puts "  risk.sl_pct=#{status[:sl_pct]}"
    puts "  entry_guard.hard_stop=#{status[:entry_guard_hard_stop]}"
  end
end
