# frozen_string_literal: true

require_relative '../src/auto_exp/experiment_runner'

# Set up environment variables if needed
# ENV['OLLAMA_HOST'] ||= 'http://localhost:11434'

runner = AutoExp::ExperimentRunner.new
runner.run(max_iterations: 20) # Limit iterations for initial test
