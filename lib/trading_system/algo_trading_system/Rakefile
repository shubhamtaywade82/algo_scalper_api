# frozen_string_literal: true

require 'rspec/core/rake_task'

desc 'Run all tests'
RSpec::Core::RakeTask.new(:spec)

def run_script(script_name)
  # Extract arguments after the task name
  # Example: rake trade -- -s rsi_macd
  # ARGV will be ["trade", "--", "-s", "rsi_macd"]
  task_idx = ARGV.find_index(script_name)
  return unless task_idx

  args = ARGV[(task_idx + 1)..-1]
  # Remove the leading '--' if present (standard way to pass args to rake)
  args.shift if args.first == '--'
  
  sh "bundle exec ruby bin/#{script_name} #{args.join(' ')}"
  
  # Crucial: Clear ARGV so Rake doesn't try to process arguments as tasks
  ARGV.replace([])
end

desc 'Run a backtest'
task :backtest do
  run_script('backtest')
end

desc 'Compare all strategies'
task 'backtest:compare' do
  sh 'bundle exec ruby examples/strategy_comparison.rb'
end

desc 'Run live trading (paper mode default)'
task :trade do
  run_script('trade')
end

desc 'Run code quality checks'
task :quality do
  sh 'bundle exec ruby_mastery analyze src/ || echo "ruby_mastery not available"'
end

# Load custom tasks from lib/tasks
Dir.glob('lib/tasks/*.rake').each { |r| load r }

task default: :spec
