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

    doc = AlgoConfig::DocumentStore.force_bootstrap!
    puts "[algo_config:bootstrap_document] wrote #{key} (#{doc.keys.size} top-level keys)"
  end
end
