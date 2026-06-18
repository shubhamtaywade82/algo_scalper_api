# frozen_string_literal: true

# rubocop:disable Rails/Output
namespace :dev do
  desc 'Development only: flush Redis, recreate DB, seed, recurring jobs, ledger seed, instruments import. ' \
       'SKIP_REDIS=1 SKIP_LEDGER=1 SKIP_INSTRUMENTS=1 SKIP_ANALYSIS=1 to skip steps. Stop ./bin/dev first.'
  task fresh: :environment do
    unless Rails.env.development?
      abort 'dev:fresh is only allowed in development'
    end

    puts 'WARNING: dev:fresh wipes the development database and Redis.'
    puts 'Stop ./bin/dev (foreman) before running to avoid PG connection errors.'

    Dev::FreshStart.call(
      import_instruments: ENV['SKIP_INSTRUMENTS'].blank?,
      flush_redis: ENV['SKIP_REDIS'].blank?,
      seed_ledger: ENV['SKIP_LEDGER'].blank?
    )
  end
end
# rubocop:enable Rails/Output
