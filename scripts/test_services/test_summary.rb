#!/usr/bin/env ruby
# frozen_string_literal: true

# Test Summary Generator
# Analyzes test results and provides a summary of passing/failing services

require_relative 'base'
ServiceTestHelper.setup_rails

ServiceTestHelper.print_header('Service Test Summary Report')

# Test results storage
test_results = {
  passed: [],
  failed: [],
  warnings: []
}

# List of all test scripts
test_scripts = Dir[File.join(__dir__, 'test_*.rb')].sort.map { |f| File.basename(f) }

ServiceTestHelper.print_section('Running Tests...')

test_scripts.each do |script|
  script_name = script.sub('test_', '').sub('.rb', '')
  ServiceTestHelper.print_info("Testing: #{script_name}...")

  # Run test and capture output
  output = `ruby #{File.join(__dir__, script)} 2>&1`
  exit_code = $?.exitstatus

  # Analyze output
  if exit_code == 0
    if output.include?('✅') && !output.include?('❌')
      test_results[:passed] << script_name
      ServiceTestHelper.print_success("#{script_name}: PASSED")
    elsif output.include?('⚠️') && !output.include?('❌')
      test_results[:warnings] << script_name
      ServiceTestHelper.print_warning("#{script_name}: WARNINGS")
    else
      test_results[:failed] << script_name
      ServiceTestHelper.print_error("#{script_name}: FAILED")
    end
  else
    test_results[:failed] << script_name
    ServiceTestHelper.print_error("#{script_name}: FAILED (exit code: #{exit_code})")

    # Extract error message
    error_line = output.lines.find { |l| l.include?('Error') || l.include?('undefined method') || l.include?('NoMethodError') }
    if error_line
      ServiceTestHelper.print_info("  Error: #{error_line.strip}")
    end
  end
end

# Print summary
ServiceTestHelper.print_section('Summary')

total = test_results[:passed].size + test_results[:failed].size + test_results[:warnings].size
ServiceTestHelper.print_info("Total tests: #{total}")
ServiceTestHelper.print_success("Passed: #{test_results[:passed].size}")
ServiceTestHelper.print_warning("Warnings: #{test_results[:warnings].size}")
ServiceTestHelper.print_error("Failed: #{test_results[:failed].size}")

if test_results[:passed].any?
  ServiceTestHelper.print_section('✅ Passing Services')
  test_results[:passed].each do |service|
    ServiceTestHelper.print_success("  - #{service}")
  end
end

if test_results[:warnings].any?
  ServiceTestHelper.print_section('⚠️  Services with Warnings')
  test_results[:warnings].each do |service|
    ServiceTestHelper.print_warning("  - #{service}")
  end
end

if test_results[:failed].any?
  ServiceTestHelper.print_section('❌ Failing Services')
  test_results[:failed].each do |service|
    ServiceTestHelper.print_error("  - #{service}")
  end
  ServiceTestHelper.print_info("\nRun individual tests for details:")
  test_results[:failed].each do |service|
    ServiceTestHelper.print_info("  ruby scripts/test_services/test_#{service}.rb")
  end
  exit 1
else
  ServiceTestHelper.print_success("\n✅ All services are working correctly!")
  exit 0
end

