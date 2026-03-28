# frozen_string_literal: true

require "csv"

module AutoExp
  class ResultsStore
    # Use experiments/results.tsv relative to Rails root
    FILE = Rails.root.join("experiments/results.tsv")

    def self.log(commit:, metrics:, status:, description:)
      # Ensure experiments directory exists
      FileUtils.mkdir_p(File.dirname(FILE))

      # Write header if file doesn't exist
      unless File.exist?(FILE)
        File.open(FILE, "w") do |f|
          f.puts(%w[commit profit_factor drawdown win_rate status description timestamp].join("\t"))
        end
      end

      line = [
        commit,
        metrics[:profit_factor],
        metrics[:drawdown],
        metrics[:win_rate],
        status,
        description,
        Time.current.strftime("%Y-%m-%d %H:%M:%S")
      ].join("\t")

      File.open(FILE, "a") { |f| f.puts(line) }
    end

    def self.load_recent(limit = 10)
      return [] unless File.exist?(FILE)

      lines = File.readlines(FILE).last(limit)
      lines.filter_map do |line|
        parts = line.chomp.split("\t")
        next if parts[0] == "commit" # Skip header if it was in the last 10 lines

        {
          commit: parts[0],
          profit_factor: parts[1].to_f,
          drawdown: parts[2].to_f,
          win_rate: parts[3].to_f,
          status: parts[4],
          description: parts[5]
        }
      end
    end
  end
end
