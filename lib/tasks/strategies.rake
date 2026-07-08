# frozen_string_literal: true

namespace :strategies do
  desc "Scaffold a new strategy plugin from the basic template"
  task :generate, [:slug] => :environment do |_t, args|
    slug = args[:slug] || ENV.fetch("SLUG", nil)
    abort "Usage: rake strategies:generate[my_strategy]" unless slug

    class_name = slug.camelize
    dir = Rails.root.join("strategies", slug)
    templates = Rails.root.join("strategies/_templates/basic")

    abort "Strategy #{slug} already exists at #{dir}" if dir.exist?

    require "erb"

    dir.mkpath

    %w[strategy.rb manifest.yml].each do |file|
      template = templates.join("#{file}.tt")
      content = ERB.new(template.read, trim_mode: "-").result(binding)
      dest = dir.join(file)
      dest.write(content)
      puts "  create  #{dest.relative_path_from(Rails.root)}"
    end

    puts ""
    puts "Strategy #{slug} scaffolded at #{dir.relative_path_from(Rails.root)}"
    puts "Next: edit #{dir.join('strategy.rb').relative_path_from(Rails.root)}"
  end
end
