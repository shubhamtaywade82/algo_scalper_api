# frozen_string_literal: true

module Strategies
  # Discovers strategy plugins from the repo root `strategies/` directory and
  # reconciles them into the platform tables. For each plugin with a valid
  # `manifest.yml` + `strategy.rb`, this ensures:
  # - a `Strategies::Record` exists
  # - a v1 release file exists under `releases/v1/strategy.rb`
  # - a `Strategies::Version` exists pointing at that release
  # - checksum/scan_report are up to date
  #
  # This is called automatically from `Manager#reconcile` for plugins that
  # are desired-runnable but not yet deployed, so the runtime never has to
  # hardcode strategy names.
  class Discovery
    STRATEGIES_ROOT = Rails.root.join("strategies").freeze
    MANIFEST_NAME = "manifest.yml"
    STRATEGY_FILE = "strategy.rb"
    RELEASE_PATH = "releases/v1/strategy.rb"

    class PluginError < StandardError; end

    def self.sync!
      new.sync!
    end

    def sync!
      return [] unless STRATEGIES_ROOT.exist?

      plugins.each_with_object([]) do |plugin, results|
        results << reconcile_plugin!(plugin)
      rescue PluginError => e
        Rails.logger.warn("[Strategies::Discovery] #{plugin[:slug]} skipped: #{e.class} - #{e.message}")
        []
      end.compact
    end

    private

    def plugins
      @plugins ||= Dir.glob("#{STRATEGIES_ROOT}/*/#{MANIFEST_NAME}")
                      .filter_map { |manifest| plugin_from_manifest(Pathname.new(manifest)) }
                      .sort_by { |plugin| plugin[:slug] }
    end

    def plugin_from_manifest(manifest_path)
      dir = manifest_path.dirname
      strategy_path = dir.join(STRATEGY_FILE)
      return nil unless manifest_path.exist? && strategy_path.exist?

      manifest = YAML.safe_load_file(manifest_path.to_s, aliases: true) || {}
      slug = manifest["slug"].presence || dir.basename.to_s
      class_name = manifest["class_name"].presence
      return nil unless manifest["params"].is_a?(Hash)
      return nil unless strategy_path.read.start_with?("# frozen_string_literal: true")
      validate_plugin!(slug, strategy_path)
      rubyvm_parse!(slug, strategy_path)

      {
        slug:,
        class_name:,
        name: manifest["name"].presence || slug,
        timeframes: Array(manifest["timeframes"]),
        instruments: Array(manifest["instruments"]),
        params: manifest["params"],
        dir:,
        manifest_path: manifest_path.to_s,
        strategy_path: strategy_path.to_s
      }
    end

    def reconcile_plugin!(plugin)
      # This runs on the 2-second strategy control-loop tick, so it genuinely
      # races concurrent API deploys / parallel syncs: two callers can both miss
      # the find and both attempt an INSERT on the unique `strategies.slug`
      # index. `create_or_find_by!` would be the idiomatic fix, BUT it only
      # rescues ActiveRecord::RecordNotUnique — the Strategies::Record model
      # also declares `validates :slug, uniqueness: true`, whose app-level
      # validator raises ActiveRecord::RecordInvalid *before* the DB constraint
      # fires, and create_or_find_by! does NOT catch RecordInvalid (see
      # https://api.rubyonrails.org/classes/ActiveRecord/Relation.html#method-i-create_or_find_by-21).
      # So we rescue both uniqueness errors and retry the find.
      strategy_record = find_or_create_strategy_record!(plugin)

      release_path = plugin[:dir].join(RELEASE_PATH)
      release_path.dirname.mkpath
      source = File.read(plugin[:strategy_path])
      unless File.exist?(release_path) && File.read(release_path) == source
        File.write(release_path, source)
      end
      checksum = Digest::SHA256.hexdigest(release_path.read)

      strategy_record.update!(name: plugin[:name]) if strategy_record.name != plugin[:name]

      # Only create a new version when the release file or manifest actually changed,
      # otherwise return the existing version. Version bumping on every sync (2s
      # control-loop tick) previously produced 200k+ phantom versions.
      current = strategy_record.current_version
      manifest = {
        "name" => plugin[:name],
        "slug" => plugin[:slug],
        "class_name" => plugin[:class_name],
        "timeframes" => plugin[:timeframes],
        "instruments" => plugin[:instruments],
        "params" => plugin[:params]
      }
      release_path_str = release_path.to_s
      if current && current.checksum == checksum && current.manifest == manifest
        current.update!(file_path: release_path_str) if current.file_path != release_path_str
        return current
      end

      scan_report = SecurityScanner.new(File.read(release_path)).scan
      raise PluginError, "security scan blocked" unless scan_report[:pass]

      next_version = (strategy_record.versions.maximum(:version) || 0) + 1

      version = strategy_record.versions.create!(
        version: next_version,
        file_path: release_path_str,
        checksum: checksum,
        manifest: manifest,
        scan_report: scan_report,
        deployed_at: Time.current
      )

      strategy_record.update!(current_version: version)
      version
    rescue ActiveRecord::RecordInvalid => e
      raise PluginError, e.message
    end

    # Race-safe find-or-create for the Strategies::Record slug. Unlike
    # create_or_find_by! (which only rescues RecordNotUnique), this also catches
    # RecordInvalid from the model's `validates :slug, uniqueness: true` — that
    # validator raises *before* the DB unique constraint, so create_or_find_by!
    # would still crash on the second concurrent caller.
    def find_or_create_strategy_record!(plugin)
      Strategies::Record.find_or_create_by!(slug: plugin[:slug]) do |record|
        record.name = plugin[:name]
        record.status = "draft"
      end
    rescue ActiveRecord::RecordNotUnique
      # DB-level unique constraint on strategies.slug fired: another caller won
      # the race. The record now exists — find it.
      retry_strategy_record_find(plugin)
    rescue ActiveRecord::RecordInvalid => e
      # App-level `validates :slug, uniqueness: true` can fire before the DB
      # constraint. Only treat the slug-uniqueness case as a race; any other
      # validation failure must propagate (it indicates a bad plugin manifest).
      raise e unless slug_uniqueness_error?(e)

      retry_strategy_record_find(plugin)
    end

    def slug_uniqueness_error?(error)
      # e.record.errors reflects which attribute failed. We only swallow the
      # race when the *slug* specifically is the duplicate.
      error.record&.errors&.where(:slug, :taken)&.any? ||
        error.message.to_s.match?(/Slug.*has already been taken/i)
    end

    def retry_strategy_record_find(plugin)
      Rails.logger.warn(
        "[Strategies::Discovery] slug race for #{plugin[:slug]}; retrying find"
      )
      Strategies::Record.find_by!(slug: plugin[:slug])
    end

    def validate_plugin!(slug, strategy_path)
      require "digest"
      require "fileutils"

      content = strategy_path.read
      raise PluginError, "strategy file is empty" if content.strip.empty?

      keys = %w[slug class_name name timeframes instruments params]
      manifest = YAML.safe_load_file(strategy_path.dirname.join(MANIFEST_NAME).to_s, aliases: true) || {}
      missing = keys.reject { |key| manifest[key].present? }
      raise PluginError, "manifest missing #{missing.join(', ')}" if missing.any?

      unless manifest["class_name"].to_s.match?(/\A[A-Z]\w*\z/)
        raise PluginError, "invalid manifest class_name: #{manifest['class_name']}"
      end

      unless manifest["params"].is_a?(Hash)
        raise PluginError, "manifest params must be a hash"
      end
    end

    def rubyvm_parse!(slug, strategy_path)
      RubyVM::AbstractSyntaxTree.parse(strategy_path.read)
    rescue SyntaxError => e
      raise PluginError, "syntax error in #{strategy_path.basename}: #{e.message}"
    end
  end
end
