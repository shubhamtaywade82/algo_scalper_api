# frozen_string_literal: true

require_relative "config"
require_relative "report"
require_relative "checks/layer_violations"
require_relative "checks/domain_purity"
require_relative "checks/float_money"

module ArchitectureGate
  class Runner
    CHECKS = [
      Checks::LayerViolations,
      Checks::DomainPurity,
      Checks::FloatMoney
    ].freeze

    def initialize(config_path: "config/architecture_gate.yml", baseline: nil)
      @config = Config.load(config_path)
      @baseline = baseline
      @report = Report.new
    end

    def run(paths: nil)
      target_paths = paths || default_paths

      CHECKS.each do |check_class|
        check = check_class.new(@config, @report)
        check.run(target_paths)
      end

      @report
    end

    def run!(paths: nil)
      report = run(paths: paths)
      Rails.logger.debug report

      if report.failures.any?
        Rails.logger.debug "\n❌ ARCHITECTURE GATE FAILED (#{report.failures.size} violations)"
        exit 1
      else
        Rails.logger.debug "\n✅ ARCHITECTURE GATE PASSED"
        exit 0
      end
    end

    private

    def default_paths
      %w[app/domain app/services app/gateways app/controllers app/models app/strategies app/jobs lib]
        .select { |p| Dir.exist?(p) }
    end
  end
end
