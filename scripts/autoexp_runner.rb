# frozen_string_literal: true

require_relative "../config/environment"

# Run the experiment iterations
iterations = (ARGV[0] || 5).to_i
AutoExp::ExperimentRunner.new.run(iterations: iterations)
