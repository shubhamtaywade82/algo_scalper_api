# frozen_string_literal: true

require "sqlite3"
require "json"
require "fileutils"

module Agent
  # Bridges Rails bots with the central SQLite FTS5 memory and self-healing engine.
  class MemoryService
    DB_PATH = ENV.fetch(
      "AGENT_DB_PATH",
      File.expand_path("../../../../../../local-agent-stack/db/shared-agent-memory.db", __dir__)
    )

    def self.db
      @db ||= begin
        FileUtils.mkdir_p(File.dirname(DB_PATH))
        SQLite3::Database.new(DB_PATH).tap do |db|
          db.results_as_hash = true
          db.execute("PRAGMA journal_mode = WAL;")
          db.execute("PRAGMA synchronous = NORMAL;")
          db.execute("PRAGMA busy_timeout = 5000;")
        end
      end
    end

    def self.search(query, limit: 5)
      words = query.to_s.gsub(/[^\w\s]/, " ").strip.split(/\s+/).reject(&:empty?)
      return [] if words.empty?

      fts_query = words.map { |w| "#{w}*" }.join(" OR ")
      stmt = db.prepare(
        "SELECT m.id, m.topic, m.fact, m.source, m.created_at " \
        "FROM memories_fts fts " \
        "JOIN memories m ON fts.rowid = m.id " \
        "WHERE memories_fts MATCH ? " \
        "ORDER BY rank LIMIT ?"
      )
      stmt.execute(fts_query, limit).to_a
    end

    def self.save_memory(topic, fact, source: "algo_scalper_api")
      stmt = db.prepare("INSERT INTO memories (topic, fact, source) VALUES (?, ?, ?)")
      stmt.execute(topic, fact, source)
    end

    def self.active_rules
      db.execute("SELECT id, rule, pattern, hit_count FROM system_rules ORDER BY id ASC")
    end

    def self.log_error(session_id, error_message, metadata = {})
      payload = { error: error_message, bot: "algo_scalper_api", **metadata }.to_json
      stmt = db.prepare("INSERT INTO audit_logs (session_id, event_type, payload) VALUES (?, 'error', ?)")
      stmt.execute(session_id.to_s, payload)
    end
  end
end
