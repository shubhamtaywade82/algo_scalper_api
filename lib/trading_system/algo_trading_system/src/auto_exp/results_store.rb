# frozen_string_literal: true

require 'csv'

module AutoExp
  class ResultsStore
    FILE = File.join(Dir.pwd, 'experiments', 'results.tsv')

    def self.log(commit:, metrics:, status:, description:)
      # Write header if doesn't exist
      unless File.exist?(FILE)
        File.open(FILE, 'w') do |f|
          f.puts(%w[commit profit_factor drawdown status description].join("\t"))
        end
      end

      line = [
        commit,
        metrics[:profit_factor],
        metrics[:drawdown],
        status,
        description
      ].join("\t")

      File.open(FILE, 'a') { |f| f.puts(line) }
    end
  end
end
