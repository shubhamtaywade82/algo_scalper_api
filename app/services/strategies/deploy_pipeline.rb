# frozen_string_literal: true

module Strategies
  # Deploy pipeline: validate → scan → snapshot → register → (re)load.
  #
  # Usage:
  #   Strategies::DeployPipeline.call("supertrend_v1")
  #
  # Returns a hash with `:version` (Strategies::Version), `:scan_report`, and `:errors`.
  class DeployPipeline
    STRATEGIES_ROOT = Rails.root.join("strategies")

    def self.call(slug)
      new(slug).call
    end

    def initialize(slug)
      @slug = slug
      @dir = STRATEGIES_ROOT.join(slug)
      @errors = []
    end

    def call
      validate
      return error_result("validate") if @errors.any?

      scan_report = scan
      if scan_report[:blocked_count].positive?
        return error_result("scan", scan_report)
      end

      checksum = snapshot
      version = register(checksum, scan_report)
      reload(version)

      { version: version, scan_report: scan_report, errors: [], ok: true }
    end

    private

    def validate
      manifest_path = @dir.join("manifest.yml")
      strategy_path = @dir.join("strategy.rb")

      unless manifest_path.exist?
        @errors << "manifest.yml not found at #{manifest_path}"
        return
      end

      unless strategy_path.exist?
        @errors << "strategy.rb not found at #{strategy_path}"
        return
      end

      manifest = YAML.safe_load_file(manifest_path)
      unless manifest.is_a?(Hash) && manifest["slug"] == @slug
        @errors << "manifest slug mismatch: expected #{@slug}"
        return
      end

      unless manifest["class_name"] && manifest["params"].is_a?(Hash)
        @errors << "manifest missing class_name or params"
        return
      end

      begin
        RubyVM::AbstractSyntaxTree.parse(strategy_path.read)
      rescue SyntaxError => e
        @errors << "Ruby syntax error: #{e.message}"
      end
    end

    def scan
      content = @dir.join("strategy.rb").read
      SecurityScanner.new(content).scan
    end

    def snapshot
      strategy_path = @dir.join("strategy.rb")

      strategy_record = ensure_strategy_record!

      next_version = (strategy_record.versions.maximum(:version) || 0) + 1
      release_dir = @dir.join("releases", "v#{next_version}")
      release_dir.mkpath

      dest = release_dir.join("strategy.rb")
      FileUtils.cp(strategy_path, dest)
      Digest::SHA256.hexdigest(dest.read)

    end

    def register(checksum, scan_report)
      manifest = YAML.safe_load_file(@dir.join("manifest.yml"))
      strategy_record = ensure_strategy_record!

      next_version = (strategy_record.versions.maximum(:version) || 0) + 1
      release_path = @dir.join("releases", "v#{next_version}", "strategy.rb").to_s

      version = strategy_record.versions.create!(
        version: next_version,
        file_path: release_path,
        checksum: checksum,
        manifest: manifest,
        scan_report: scan_report,
        deployed_at: Time.current
      )

      strategy_record.update!(current_version: version)
      version
    end

    def reload(version)
      strategy_record = version.strategy_record
      if strategy_record.runs.where(stopped_at: nil).exists?
        strategy_record.update!(desired_status: "deployed")
      else
        strategy_record.update!(status: "deployed")
      end
    end

    def ensure_strategy_record!
      manifest = YAML.safe_load_file(@dir.join("manifest.yml"))
      Strategies::Record.find_or_create_by!(slug: @slug) do |r|
        r.name = manifest["name"] || @slug
        r.status = "draft"
      end

    end

    def error_result(phase, scan_report = nil)
      result = { version: nil, scan_report: scan_report, errors: @errors, ok: false }
      Rails.logger.warn("[DeployPipeline] #{phase} failed for #{@slug}: #{@errors.join('; ')}")
      result
    end
  end
end
