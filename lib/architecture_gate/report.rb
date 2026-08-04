# frozen_string_literal: true

require 'json'
require 'time'

module ArchitectureGate
  class Report
    Finding = Struct.new(:check, :file, :line, :message, :severity, keyword_init: true)

    attr_reader :findings

    def initialize
      @findings = []
    end

    def add_failure(check:, message:, file: nil, line: nil, severity: :error)
      @findings << Finding.new(
        check: check.to_s,
        file: file,
        line: line,
        message: message,
        severity: severity
      )
    end

    def failures
      @findings.select { |f| f.severity == :error }
    end

    def warnings
      @findings.select { |f| f.severity == :warning }
    end

    def passed?
      failures.empty?
    end

    def to_s
      output = []
      output << "=" * 60
      output << "ARCHITECTURE GATE REPORT"
      output << "=" * 60
      output << ""

      if findings.empty?
        output << "✅ No architecture violations detected."
        return output.join("\n")
      end

      findings.group_by(&:check).each do |check, check_findings|
        output << "── #{check.upcase} #{'─' * (50 - check.length)}"
        check_findings.each do |f|
          location = f.file ? "#{f.file}#{f.line ? ":#{f.line}" : ""}" : "(global)"
          icon = f.severity == :error ? "❌" : "⚠️"
          output << "  #{icon} #{location}"
          output << "     #{f.message}"
        end
        output << ""
      end

      output << "─" * 60
      output << "Errors: #{failures.size}  Warnings: #{warnings.size}"
      output << "─" * 60

      output.join("\n")
    end

    def to_json(*_args)
      {
        passed: passed?,
        errors: failures.size,
        warnings: warnings.size,
        findings: findings.map(&:to_h),
        timestamp: Time.now.iso8601
      }.to_json
    end
  end
end
