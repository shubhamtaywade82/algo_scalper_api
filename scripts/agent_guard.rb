# frozen_string_literal: true

FORBIDDEN_PATHS = [
  "app/services/orders",
  "app/services/positions",
  "app/services/exit",
  "app/services/live",
  "app/services/capital"
].freeze

changed_files = `git diff --name-only origin/main`.split("\n")

violations = changed_files.select do |file|
  FORBIDDEN_PATHS.any? { |path| file.start_with?(path) }
end

if violations.any?
  puts "Agent Guard Violation: Attempt to modify locked layers"
  violations.each { |v| puts " - #{v}" }
  exit 1
end

puts "Agent Guard Passed"
