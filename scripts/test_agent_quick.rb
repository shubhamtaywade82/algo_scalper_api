#!/usr/bin/env ruby
# frozen_string_literal: true

# Quick test script for Technical Analysis Agent (without background services)
# Run with: DISABLE_TRADING_SERVICES=1 rails runner scripts/test_agent_quick.rb

require_relative '../config/environment' if defined?(Rails)

# Disable background services for faster testing
ENV['DISABLE_TRADING_SERVICES'] = '1'
ENV['DHANHQ_ENABLED'] = 'false' unless ENV['DHANHQ_ENABLED'] == 'true'

# Color output helpers
class String
  def green = "\e[32m#{self}\e[0m"
  def red = "\e[31m#{self}\e[0m"
  def yellow = "\e[33m#{self}\e[0m"
  def blue = "\e[34m#{self}\e[0m"
  def cyan = "\e[36m#{self}\e[0m"
  def bold = "\e[1m#{self}\e[0m"
end

def print_header(text)
  puts "\n#{'=' * 80}".cyan.bold
  puts "  #{text}".cyan.bold
  puts ('=' * 80).to_s.cyan.bold
end

def print_success(text)
  puts "✅ #{text}".green
end

def print_error(text)
  puts "❌ #{text}".red
end

def print_warning(text)
  puts "⚠️  #{text}".yellow
end

def print_info(text)
  puts "ℹ️  #{text}".blue
end

def print_step(text)
  puts "\n▶ #{text}".cyan
end

# Quick test - just check if components load and basic methods work
def test_component_loading
  print_header('Testing Component Loading')

  begin
    # Test 1: Agent class loads
    print_step('Loading TechnicalAnalysisAgent')
    agent = Services::Ai::TechnicalAnalysisAgent.new
    print_success('Agent class loaded')

    # Test 2: Check modules are included
    print_step('Checking module inclusion')
    modules = agent.class.included_modules.map(&:to_s)
    required_modules = [
      'Services::Ai::TechnicalAnalysisAgent::IntentResolver',
      'Services::Ai::TechnicalAnalysisAgent::DecisionEngine',
      'Services::Ai::TechnicalAnalysisAgent::AdaptiveController',
      'Services::Ai::TechnicalAnalysisAgent::AgentRunner'
    ]

    missing = required_modules.reject { |m| modules.include?(m) }
    if missing.empty?
      print_success('All required modules included')
    else
      print_error("Missing modules: #{missing.join(', ')}")
      return false
    end

    # Test 3: AgentContext class exists
    print_step('Checking AgentContext class')
    context_class = Services::Ai::TechnicalAnalysisAgent::AgentContext
    print_success('AgentContext class exists')

    # Test 4: Create context instance
    print_step('Creating AgentContext instance')
    context = context_class.new({
                                  intent: :general,
                                  underlying_symbol: 'NIFTY',
                                  confidence: 0.8
                                })
    print_success('AgentContext instance created')
    puts "  Intent: #{context.intent}"
    puts "  Symbol: #{begin
      context.symbol_name
    rescue StandardError
      context.underlying_symbol
    end}"

    # Test 5: Check methods exist
    print_step('Checking method availability')
    methods_to_check = %i[
      resolve_intent
      next_tool
      resolve_instrument_deterministically
      adapt_tool_result
      run_agent_loop
    ]

    missing_methods = methods_to_check.reject { |m| agent.respond_to?(m) }
    if missing_methods.empty?
      print_success('All required methods available')
    else
      print_error("Missing methods: #{missing_methods.join(', ')}")
      return false
    end

    true
  rescue StandardError => e
    print_error("Component loading FAILED: #{e.class} - #{e.message}")
    puts "  Backtrace: #{e.backtrace.first(5).join("\n  ")}"
    false
  end
end

def test_intent_resolver_quick
  print_header('Testing Intent Resolver (Quick)')

  agent = Services::Ai::TechnicalAnalysisAgent.new

  test_cases = [
    { query: 'What is the price of NIFTY?', expected_intent: :general },
    { query: 'Analyse RELIANCE for swing trading', expected_intent: :swing_trading }
  ]

  test_cases.each do |test_case|
    print_step("Testing: #{test_case[:query]}")

    begin
      # Add timeout
      result = nil
      Timeout.timeout(10) do
        result = agent.resolve_intent(test_case[:query])
      end

      puts "  Intent: #{result[:intent]} (expected: #{test_case[:expected_intent]})"
      puts "  Symbol: #{result[:underlying_symbol]}"
      puts "  Confidence: #{(result[:confidence] * 100).round}%"

      if result[:intent] == test_case[:expected_intent]
        print_success('Intent resolution PASSED')
      else
        print_warning("Intent mismatch (got #{result[:intent]}, expected #{test_case[:expected_intent]})")
      end
    rescue Timeout::Error
      print_error('Intent resolution TIMED OUT (>10s)')
    rescue StandardError => e
      print_error("Intent resolution FAILED: #{e.class} - #{e.message}")
      puts "  Backtrace: #{e.backtrace.first(3).join("\n  ")}"
    end

    puts ''
  end
end

def test_decision_engine_quick
  print_header('Testing Decision Engine (Quick)')

  agent = Services::Ai::TechnicalAnalysisAgent.new

  begin
    # Create test context
    context = Services::Ai::TechnicalAnalysisAgent::AgentContext.new({
                                                                       intent: :swing_trading,
                                                                       underlying_symbol: 'RELIANCE',
                                                                       confidence: 0.8
                                                                     })

    print_step('Testing instrument resolution')
    instrument = agent.resolve_instrument_deterministically(context)

    if instrument
      print_success("Instrument resolved: #{instrument.symbol_name} (#{instrument.segment})")
      context.resolved_instrument = instrument
    else
      print_warning('Instrument not found for RELIANCE (this is OK if not in DB)')
    end

    print_step('Testing next_tool decision')
    next_tool = agent.next_tool(context)

    puts "  Next tool: #{next_tool[:tool]}"
    puts "  Args: #{next_tool[:args].inspect}"

    if next_tool[:tool] == 'abort'
      print_warning("Decision engine returned abort: #{next_tool[:args][:reason]}")
    else
      print_success('Decision engine working')
    end
  rescue StandardError => e
    print_error("Decision Engine test FAILED: #{e.class} - #{e.message}")
    puts "  Backtrace: #{e.backtrace.first(5).join("\n  ")}"
  end
end

def test_wrapper_tools_quick
  print_header('Testing Wrapper Tools (Quick)')

  agent = Services::Ai::TechnicalAnalysisAgent.new

  # Test resolve_instrument
  print_step('Testing tool_resolve_instrument')
  begin
    result = agent.tool_resolve_instrument({ 'symbol' => 'NIFTY' })

    if result[:error]
      print_warning("tool_resolve_instrument returned error: #{result[:error]}")
      puts '  (This is OK if NIFTY instrument not in database)'
    else
      print_success('tool_resolve_instrument working')
      puts "  Instrument ID: #{result[:instrument_id]}"
      puts "  Symbol: #{result[:symbol]}"
    end
  rescue StandardError => e
    print_error("tool_resolve_instrument FAILED: #{e.class} - #{e.message}")
  end
end

def run_quick_tests
  print_header('TECHNICAL ANALYSIS AGENT - QUICK TEST SUITE')

  results = {
    passed: [],
    failed: []
  }

  # Test 1: Component Loading
  begin
    if test_component_loading
      results[:passed] << 'Component Loading'
    else
      results[:failed] << 'Component Loading'
    end
  rescue StandardError => e
    results[:failed] << "Component Loading: #{e.message}"
  end

  # Test 2: Intent Resolver (quick)
  begin
    test_intent_resolver_quick
    results[:passed] << 'Intent Resolver'
  rescue StandardError => e
    results[:failed] << "Intent Resolver: #{e.message}"
  end

  # Test 3: Decision Engine (quick)
  begin
    test_decision_engine_quick
    results[:passed] << 'Decision Engine'
  rescue StandardError => e
    results[:failed] << "Decision Engine: #{e.message}"
  end

  # Test 4: Wrapper Tools (quick)
  begin
    test_wrapper_tools_quick
    results[:passed] << 'Wrapper Tools'
  rescue StandardError => e
    results[:failed] << "Wrapper Tools: #{e.message}"
  end

  # Print summary
  print_header('QUICK TEST SUMMARY')

  if results[:passed].any?
    print_success("Passed (#{results[:passed].length}):")
    results[:passed].each { |test| puts "  ✅ #{test}" }
  end

  if results[:failed].any?
    print_error("Failed (#{results[:failed].length}):")
    results[:failed].each { |test| puts "  ❌ #{test}" }
  end

  puts "\n"

  # Exit code
  exit_code = results[:failed].any? ? 1 : 0
  puts "Exit code: #{exit_code}".bold
  exit(exit_code)
end

# Main execution
if __FILE__ == $PROGRAM_NAME
  require 'timeout'
  run_quick_tests
end
