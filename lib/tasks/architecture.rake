# frozen_string_literal: true

namespace :architecture do
  desc "Run architecture regression gate"
  task check: :environment do
    require_relative "../architecture_gate/runner"

    paths = ENV["PATHS"]&.split(",")
    runner = ArchitectureGate::Runner.new(config_path: "config/architecture_gate.yml")
    runner.run!(paths: paths)
  end

  desc "Run architecture gate (JSON output for CI)"
  task check_json: :environment do
    require_relative "../architecture_gate/runner"

    runner = ArchitectureGate::Runner.new(config_path: "config/architecture_gate.yml")
    report = runner.run
    puts report.to_json
    exit(report.passed? ? 0 : 1)
  end
end
