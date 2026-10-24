# frozen_string_literal: true

require_relative "base"

module ArchitectureGate
  module Checks
    class DomainPurity < Base
      def run(paths)
        domain_files = Dir.glob("app/domain/**/*.rb")

        domain_files.each do |file|
          content = File.read(file)
          lines = content.lines

          @config.domain_purity_forbidden.each do |pattern|
            regex = Regexp.new(pattern)
            lines.each_with_index do |line, idx|
              next if line.strip.start_with?("#")

              next unless line.match?(regex)
              @report.add_failure(
                check: "domain_purity",
                file: file,
                line: idx + 1,
                message: "Domain layer contains forbidden pattern '#{pattern}': #{line.strip}",
                severity: :error
              )
            end
          end
        end
      end
    end
  end
end
