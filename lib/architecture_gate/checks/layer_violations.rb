# frozen_string_literal: true

require_relative "base"

module ArchitectureGate
  module Checks
    class LayerViolations < Base
      def run(paths)
        @config.layers.each do |layer_name, rules|
          layer_path = rules["path"]
          next unless layer_path

          files = Dir.glob(layer_path).select { |f| File.file?(f) }
          files.each do |file|
            content = File.read(file)
            requires = extract_requires(content)

            (rules["must_not_require"] || []).each do |forbidden|
              violations = requires.select { |r| matches_pattern?(r, forbidden) }
              violations.each do |v|
                @report.add_failure(
                  check: "layer_violation",
                  file: file,
                  message: "#{layer_name} layer must not require '#{v}' (forbidden pattern: #{forbidden})",
                  severity: :error
                )
              end
            end
          end
        end
      end

      private

      def extract_requires(content)
        content.scan(/require\s+["']([^"']+)["']/).flatten +
          content.scan(/require_relative\s+["']([^"']+)["']/).flatten
      end

      def matches_pattern?(require_path, pattern)
        regex = Regexp.new(Regexp.escape(pattern).gsub("\\*\\*", ".*").gsub("\\*", "[^/]*"))
        require_path.match?(regex) || require_path.include?(pattern.gsub("/**", "").gsub("*", ""))
      end
    end
  end
end
