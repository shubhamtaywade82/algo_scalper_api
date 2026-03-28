# frozen_string_literal: true

namespace :spec do
  desc 'Generate empty spec files for all uncovered application files'
  task generate_missing: :environment do
    app_files = Dir.glob('app/**/*.rb')
    generated_count = 0
    skipped_count = 0

    app_files.each do |app_file|
      # Skip application_*.rb, concerns, and other boilerplate
      next if app_file.match?(/application_/)
      next if app_file.include?('/concerns/')

      spec_file = app_file.sub('app/', 'spec/').sub('.rb', '_spec.rb')

      if File.exist?(spec_file)
        skipped_count += 1
        next
      end

      # Determine the class name from file path
      parts = app_file.sub('app/', '').sub('.rb', '').split('/')
      class_name = parts.map(&:camelize).join('::')

      # Basic spec template
      template = <<~RUBY
        # frozen_string_literal: true

        require 'rails_helper'

        RSpec.describe #{class_name} do
          pending "add some examples to (or delete) \#{__FILE__}"
        end
      RUBY

      FileUtils.mkdir_p(File.dirname(spec_file))
      File.write(spec_file, template)
      generated_count += 1
      puts "Generated: #{spec_file}"
    end

    puts "\nSummary:"
    puts "  Generated: \#{generated_count} spec files"
    puts "  Skipped:   \#{skipped_count} existing spec files"
  end
end
