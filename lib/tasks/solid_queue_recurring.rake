# frozen_string_literal: true

namespace :solid_queue do
  desc 'Load recurring tasks from config/recurring.yml'
  task load_recurring: :environment do
    require 'yaml'

    config_path = Rails.root.join('config/recurring.yml')
    unless File.exist?(config_path)
      puts "❌ Config file not found: #{config_path}"
      exit 1
    end

    config = YAML.load_file(config_path)
    env = Rails.env
    tasks = config[env] || {}

    if tasks.empty?
      puts "⚠️  No recurring tasks defined for #{env} environment"
      exit 0
    end

    puts "📋 Loading #{tasks.count} recurring tasks for #{env} environment..."

    tasks.each do |key, attrs|
      task = SolidQueue::RecurringTask.find_or_initialize_by(key: key)

      # Handle both 'class' and 'class_name' keys
      class_name = attrs['class'] || attrs['class_name']
      command = attrs['command']

      # Prepare arguments - SolidQueue handles serialization, so pass array directly
      args = attrs['args'] || attrs['arguments'] || []
      arguments = if args.is_a?(String)
                    # If it's a JSON string, parse it to array
                    JSON.parse(args)
                  elsif args.is_a?(Array)
                    # Use array directly - SolidQueue will serialize it
                    args
                  else
                    # Convert to array
                    [args]
                  end

      task.assign_attributes(
        schedule: attrs['schedule'],
        class_name: class_name,
        command: command,
        arguments: arguments,
        queue_name: attrs['queue_name'] || attrs['queue'],
        priority: attrs['priority'] || 0,
        description: attrs['description'],
        static: true
      )

      if task.save
        puts "  ✅ #{key}: #{attrs['schedule']}"
      else
        puts "  ❌ #{key}: #{task.errors.full_messages.join(', ')}"
      end
    end

    puts "\n✅ Done! #{SolidQueue::RecurringTask.count} recurring tasks loaded."
    puts '   Restart bin/jobs for the dispatcher to pick them up.'
  end
end
