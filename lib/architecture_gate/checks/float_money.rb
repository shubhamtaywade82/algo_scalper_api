# frozen_string_literal: true

require_relative "base"

module ArchitectureGate
  module Checks
    class FloatMoney < Base
      MONEY_FIELDS = %w[price pnl margin amount cost fee premium strike].freeze

      def run(paths)
        forbidden_paths = @config.float_money_forbidden_in
        allowed_paths = @config.float_money_allowed_in

        forbidden_paths.each do |path_pattern|
          files = Dir.glob(path_pattern).select { |f| File.file?(f) }
          files.each do |file|
            rel_path = file.sub(%r{^(\./)+}, "")
            next if allowed_paths.any? { |a| matches_path?(rel_path, a) }

            check_file(file)
          end
        end
      end

      private

      def check_file(file)
        content = File.read(file)
        lines = content.lines

        lines.each_with_index do |line, idx|
          next if line.strip.start_with?("#")

          # Check for .to_f on money-related variables (excluding percentages/ratios/counts like pnl_percent, margin_per, etc.)
          MONEY_FIELDS.each do |field|
            pattern = /\b#{field}(?!(?:_per|_percent|_pct|_ratio|_rate|_count|_size))\b.*\.to_f/i
            next unless line.match?(pattern)
            @report.add_failure(
              check: "float_money",
              file: file,
              line: idx + 1,
              message: "Float conversion on money field '#{field}': #{line.strip}",
              severity: :error
            )
          end
        end
      end

      def matches_path?(file_path, pattern)
        clean_pattern = pattern.gsub("/**", "/*").gsub("**", "*")
        File.fnmatch(clean_pattern, file_path, File::FNM_PATHNAME | File::FNM_DOTMATCH) ||
          file_path.start_with?(pattern.gsub("/**", "").gsub("/*", ""))
      end
    end
  end
end
