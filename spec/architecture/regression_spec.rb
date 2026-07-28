# frozen_string_literal: true

require "rails_helper"
require_relative "../../lib/architecture_gate/runner"

RSpec.describe "Architecture Regression Gate" do
  let(:runner) { ArchitectureGate::Runner.new(config_path: "config/architecture_gate.yml") }
  let(:report) { runner.run }

  it "has no layer violations" do
    violations = report.findings.select { |f| f.check == "layer_violation" }
    expect(violations).to be_empty,
      "Layer violations found:\n#{violations.map(&:message).join("\n")}"
  end

  it "maintains domain purity" do
    violations = report.findings.select { |f| f.check == "domain_purity" }
    expect(violations).to be_empty,
      "Domain purity violations:\n#{violations.map { |f| "#{f.file}:#{f.line} #{f.message}" }.join("\n")}"
  end

  it "has no float money in domain/services" do
    violations = report.findings.select { |f| f.check == "float_money" }
    expect(violations).to be_empty,
      "Float money violations:\n#{violations.map(&:message).join("\n")}"
  end
end
