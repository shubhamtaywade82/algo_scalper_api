# frozen_string_literal: true

require 'redis'

module Dev
  # Development-only full reset: Redis, PostgreSQL, seeds, recurring jobs, ledger, instruments.
  # rubocop:disable Rails/Output
  class FreshStart
    class Error < StandardError; end

    def self.call(import_instruments: true, flush_redis: true, seed_ledger: true)
      new(import_instruments: import_instruments, flush_redis: flush_redis, seed_ledger: seed_ledger).call
    end

    def initialize(import_instruments: true, flush_redis: true, seed_ledger: true)
      @import_instruments = import_instruments
      @flush_redis = flush_redis
      @seed_ledger = seed_ledger
    end

    def call
      assert_development!

      step('Flushing Redis') { flush_redis! } if @flush_redis
      step('Recreating database') { recreate_database! }
      step('Seeding database') { invoke_task('db:seed') }
      reset_config_caches!
      step('Loading Solid Queue recurring tasks') { invoke_task('solid_queue:load_recurring') }
      step('Seeding ledger') { invoke_task('ledger:seed') } if @seed_ledger
      step('Importing instruments') { import_instruments! } if @import_instruments
      step('Warming analysis cache') { warm_analysis! } if @import_instruments && ENV['SKIP_ANALYSIS'].blank?
      print_summary
      true
    end

    private

    def assert_development!
      return if Rails.env.development?

      raise Error, 'dev:fresh is only allowed in development (set ALLOW_FRESH_START=1 in test to override)'
    end

    def step(label)
      puts "\n==> #{label}"
      yield
    end

    def flush_redis!
      redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379/0'))
      redis.flushdb
      puts 'Redis flushed.'
    rescue StandardError => e
      Rails.logger.warn("[Dev::FreshStart] Redis flush failed: #{e.class} - #{e.message}")
      puts "Redis flush skipped: #{e.message}"
    end

    def recreate_database!
      config = ActiveRecord::Base.connection_db_config
      db_name = config.database

      with_postgres_connection do |conn|
        terminate_backends(conn, db_name)
        quoted = quote_db_name(conn, db_name)
        conn.execute("DROP DATABASE IF EXISTS #{quoted}")
        conn.execute("CREATE DATABASE #{quoted}")
      end

      reconnect_primary!(config)
      load_schema!(config)
      puts "Database #{db_name} recreated and schema loaded."
    end

    def with_postgres_connection
      admin_hash = ActiveRecord::Base.connection_db_config.configuration_hash.merge(database: 'postgres')
      ActiveRecord::Base.connection_handler.clear_all_connections!
      ActiveRecord::Base.establish_connection(admin_hash)
      yield ActiveRecord::Base.connection
    ensure
      ActiveRecord::Base.connection_handler.clear_all_connections!
    end

    def terminate_backends(conn, db_name)
      quoted_name = conn.quote(db_name)
      conn.execute(<<~SQL.squish)
        SELECT pg_terminate_backend(pid)
        FROM pg_stat_activity
        WHERE datname = #{quoted_name}
          AND pid <> pg_backend_pid()
      SQL

      quoted_db = quote_db_name(conn, db_name)
      conn.execute("ALTER DATABASE #{quoted_db} WITH ALLOW_CONNECTIONS false")
      conn.execute(<<~SQL.squish)
        SELECT pg_terminate_backend(pid)
        FROM pg_stat_activity
        WHERE datname = #{quoted_name}
      SQL
    rescue ActiveRecord::StatementInvalid => e
      Rails.logger.debug("[Dev::FreshStart] terminate_backends: #{e.message}")
    end

    def quote_db_name(conn, db_name)
      conn.quote_table_name(db_name)
    end

    def reconnect_primary!(config)
      ActiveRecord::Base.connection_handler.clear_all_connections!
      ActiveRecord::Base.establish_connection(config)
    end

    def load_schema!(config)
      reconnect_primary!(config)
      schema_format = ActiveRecord.schema_format
      schema_path = ENV['SCHEMA'] || Rails.root.join('db/schema.rb')
      ActiveRecord::Tasks::DatabaseTasks.load_schema(config, schema_format, schema_path)
    end

    def invoke_task(name)
      task = Rake::Task[name]
      task.reenable
      task.invoke
    end

    def reset_config_caches!
      AlgoConfig.reset!
      Signal::FastEntryMode.reset! if defined?(Signal::FastEntryMode)
    end

    def import_instruments!
      result = InstrumentsImporter.import_from_url
      duration = result[:duration]
      instrument_total = result[:instrument_total].to_i
      derivative_total = result[:derivative_total].to_i
      puts "Import completed in #{duration&.round(2) || 'n/a'}s — " \
           "instruments=#{instrument_total}, derivatives=#{derivative_total}"

      if instrument_total.zero?
        raise Error,
              'Instrument import returned 0 rows — check DHAN credentials and network, or re-run without SKIP_INSTRUMENTS'
      end

      verify_index_instruments!
      DbSeeds.seed_default_index_watchlist
      puts "Watchlist items: #{WatchlistItem.count}"
    end

    def verify_index_instruments!
      missing = IndexConfigLoader.load_indices.filter_map do |cfg|
        key = cfg[:key].to_s.upcase
        next if Instrument.find_by_sid_and_segment(security_id: cfg[:sid], segment_code: cfg[:segment])

        key
      end
      return if missing.empty?

      raise Error, "Index instruments missing after import: #{missing.join(', ')}"
    end

    def warm_analysis!
      IndexConfigLoader.load_indices.each do |cfg|
        AnalysisJob.perform_later(cfg[:key].to_s.upcase, force: true)
      end
      puts 'Enqueued AnalysisJob for each configured index (runs via bin/jobs or async adapter).'
    end

    def print_summary
      puts "\n==> Fresh start complete"
      puts "  position_trackers: #{PositionTracker.count} (active: #{PositionTracker.active.count})"
      puts "  instruments: #{Instrument.count}"
      puts "  derivatives: #{Derivative.count}"
      puts "  watchlist_items: #{WatchlistItem.count}"
      puts "  ledger_accounts: #{LedgerAccount.count}" if defined?(LedgerAccount)
      puts "  solid_queue recurring tasks: #{SolidQueue::RecurringTask.count}"
      puts "\nRestart ./bin/dev before trading."
    end
  end
  # rubocop:enable Rails/Output
end
