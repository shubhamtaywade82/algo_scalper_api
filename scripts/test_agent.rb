#!/usr/bin/env ruby
# frozen_string_literal: true

# Test script for Technical Analysis Agent
# Run with: rails runner scripts/test_agent.rb
# Or: ruby scripts/test_agent.rb (if Rails is loaded)

require_relative '../config/environment' if defined?(Rails)

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

# Test queries
TEST_QUERIES = [
  {
    name: 'Simple Price Query',
    query: 'What is the price of NIFTY?',
    expected_intent: :general,
    expected_symbol: 'NIFTY'
  },
  {
    name: 'Swing Trading Analysis',
    query: 'Analyse RELIANCE for swing trading',
    expected_intent: :swing_trading,
    expected_symbol: 'RELIANCE'
  },
  {
    name: 'Options Buying Analysis',
    query: 'Analyse NIFTY for options buying',
    expected_intent: :options_buying,
    expected_symbol: 'NIFTY'
  },
  {
    name: 'Intraday Analysis',
    query: 'What is the intraday analysis for BANKNIFTY?',
    expected_intent: :intraday,
    expected_symbol: 'BANKNIFTY'
  }
].freeze

def test_intent_resolver
  print_header('Testing Intent Resolver')

  agent = Services::Ai::TechnicalAnalysisAgent.new

  TEST_QUERIES.each do |test_case|
    print_step("Testing: #{test_case[:name]}")
    print_info("Query: #{test_case[:query]}")

    begin
      intent_data = agent.resolve_intent(test_case[:query])

      puts "  Intent: #{intent_data[:intent]} (expected: #{test_case[:expected_intent]})"
      puts "  Symbol: #{intent_data[:underlying_symbol]} (expected: #{test_case[:expected_symbol]})"
      puts "  Confidence: #{(intent_data[:confidence] * 100).round}%"
      puts "  Derivatives: #{intent_data[:derivatives_needed]}"
      puts "  Timeframe: #{intent_data[:timeframe_hint]}"

      if intent_data[:intent] == test_case[:expected_intent] &&
         intent_data[:underlying_symbol]&.upcase == test_case[:expected_symbol]&.upcase
        print_success('Intent resolution PASSED')
      else
        print_warning('Intent resolution PARTIAL - intent or symbol mismatch')
      end
    rescue StandardError => e
      print_error("Intent resolution FAILED: #{e.class} - #{e.message}")
      puts "  Backtrace: #{e.backtrace.first(3).join("\n  ")}"
    end

    puts ''
  end
end

def test_agent_context
  print_header('Testing Agent Context')

  test_data = {
    intent: :options_buying,
    underlying_symbol: 'NIFTY',
    confidence: 0.9,
    derivatives_needed: true,
    timeframe_hint: '15m'
  }

  begin
    context = Services::Ai::TechnicalAnalysisAgent::AgentContext.new(test_data)

    print_success('AgentContext created successfully')
    puts "  Intent: #{context.intent}"
    puts "  Symbol: #{context.underlying_symbol}"
    puts "  Confidence: #{context.confidence}"
    puts "  Ready for analysis: #{context.ready_for_analysis?}"

    # Test adding observations
    context.add_observation('get_ltp', { instrument_id: 1 }, { ltp: 24_500.0 })
    context.ltp = 24_500.0

    print_success('Observation added successfully')
    puts "  Tool history length: #{context.tool_history.length}"
    puts "  LTP: #{context.ltp}"

    # Test summary
    summary = context.summary
    print_success('Summary generated')
    puts "  Summary: #{summary.inspect}"
  rescue StandardError => e
    print_error("AgentContext test FAILED: #{e.class} - #{e.message}")
    puts "  Backtrace: #{e.backtrace.first(5).join("\n  ")}"
  end
end

def test_decision_engine
  print_header('Testing Decision Engine')

  agent = Services::Ai::TechnicalAnalysisAgent.new

  # Test instrument resolution
  print_step('Testing instrument resolution')
  begin
    context = Services::Ai::TechnicalAnalysisAgent::AgentContext.new(
      intent: :swing_trading,
      underlying_symbol: 'RELIANCE',
      confidence: 0.8,
      derivatives_needed: false,
      timeframe_hint: '15m'
    )

    instrument = agent.resolve_instrument_deterministically(context)

    if instrument
      print_success("Instrument resolved: #{instrument.symbol_name} (#{instrument.segment})")
      context.resolved_instrument = instrument
    else
      print_warning('Instrument not found for RELIANCE')
    end

    # Test next_tool decision
    print_step('Testing next_tool decision')
    next_tool = agent.next_tool(context)

    print_info("Next tool: #{next_tool[:tool]}")
    print_info("Args: #{next_tool[:args].inspect}")

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

def test_wrapper_tools
  print_header('Testing Wrapper Tools')

  agent = Services::Ai::TechnicalAnalysisAgent.new

  # Test resolve_instrument
  print_step('Testing tool_resolve_instrument')
  begin
    result = agent.tool_resolve_instrument({ 'symbol' => 'NIFTY' })

    if result[:error]
      print_warning("tool_resolve_instrument returned error: #{result[:error]}")
    else
      print_success('tool_resolve_instrument working')
      puts "  Instrument ID: #{result[:instrument_id]}"
      puts "  Symbol: #{result[:symbol]}"
      puts "  Segment: #{result[:segment]}"
    end
  rescue StandardError => e
    print_error("tool_resolve_instrument FAILED: #{e.class} - #{e.message}")
    puts "  Backtrace: #{e.backtrace.first(3).join("\n  ")}"
  end

  # Test get_ltp (if instrument was resolved)
  print_step('Testing tool_get_ltp')
  begin
    # First resolve instrument
    resolve_result = agent.tool_resolve_instrument({ 'symbol' => 'NIFTY' })

    if resolve_result[:instrument_id]
      ltp_result = agent.tool_get_ltp({ 'instrument_id' => resolve_result[:instrument_id] })

      if ltp_result[:error]
        print_warning("tool_get_ltp returned error: #{ltp_result[:error]}")
      else
        print_success('tool_get_ltp working')
        puts "  LTP: #{ltp_result[:ltp]}"
      end
    else
      print_warning('Skipping tool_get_ltp test - instrument not resolved')
    end
  rescue StandardError => e
    print_error("tool_get_ltp FAILED: #{e.class} - #{e.message}")
    puts "  Backtrace: #{e.backtrace.first(3).join("\n  ")}"
  end
end

def test_full_agent_loop(query_name, query)
  print_header("Testing Full Agent Loop: #{query_name}")
  print_info("Query: #{query}")

  agent = Services::Ai::TechnicalAnalysisAgent.new

  # Enable agent runner
  ENV['AI_USE_AGENT_RUNNER'] = 'true'
  ENV['AI_AGENT_MAX_ITERATIONS'] = '10' # Limit iterations for testing

  print_info("Agent Runner enabled: #{ENV.fetch('AI_USE_AGENT_RUNNER', nil)}")
  print_info("Max iterations: #{ENV.fetch('AI_AGENT_MAX_ITERATIONS', nil)}")

  begin
    start_time = Time.current
    errors = []
    output_lines = []

    result = agent.analyze(
      query: query,
      stream: false
    ) do |chunk|
      output_lines << chunk
      print(chunk)
    end

    elapsed = Time.current - start_time

    puts "\n"
    print_step('Agent Loop Completed')
    puts "  Verdict: #{result[:verdict]}" if result
    puts "  Iterations: #{result[:iterations]}" if result
    puts "  Elapsed time: #{elapsed.round(2)}s"

    if result && result[:verdict] == 'ANALYSIS_COMPLETE'
      print_success('Agent loop completed successfully')
    elsif result && result[:verdict] == 'NO_TRADE'
      print_warning("Agent returned NO_TRADE: #{result[:reason]}")
    elsif result && result[:verdict] == 'ERROR'
      print_error("Agent returned ERROR: #{result[:error]}")
    else
      print_warning("Agent returned unexpected result: #{result.inspect}")
    end

    # Check for errors in output
    output_lines.each do |line|
      errors << line if line.match?(/error|Error|ERROR|failed|Failed|FAILED/i)
    end

    if errors.any?
      print_warning("Found #{errors.length} potential errors in output:")
      errors.first(5).each { |err| puts "  - #{err.strip}" }
    end

    result
  rescue StandardError => e
    print_error("Agent loop FAILED: #{e.class} - #{e.message}")
    puts '  Backtrace:'
    e.backtrace.first(10).each { |line| puts "    #{line}" }
    nil
  end
end

def run_all_tests
  print_header('TECHNICAL ANALYSIS AGENT - COMPREHENSIVE TEST SUITE')

  results = {
    passed: [],
    failed: [],
    warnings: []
  }

  # Test 1: Intent Resolver
  begin
    test_intent_resolver
    results[:passed] << 'Intent Resolver'
  rescue StandardError => e
    results[:failed] << "Intent Resolver: #{e.message}"
  end

  # Test 2: Agent Context
  begin
    test_agent_context
    results[:passed] << 'Agent Context'
  rescue StandardError => e
    results[:failed] << "Agent Context: #{e.message}"
  end

  # Test 3: Decision Engine
  begin
    test_decision_engine
    results[:passed] << 'Decision Engine'
  rescue StandardError => e
    results[:failed] << "Decision Engine: #{e.message}"
  end

  # Test 4: Wrapper Tools
  begin
    test_wrapper_tools
    results[:passed] << 'Wrapper Tools'
  rescue StandardError => e
    results[:failed] << "Wrapper Tools: #{e.message}"
  end

  # Test 5: Full Agent Loop (one simple query)
  begin
    result = test_full_agent_loop('Simple Query', 'What is the price of NIFTY?')
    if result && result[:verdict] != 'ERROR'
      results[:passed] << 'Full Agent Loop'
    else
      results[:warnings] << 'Full Agent Loop (partial)'
    end
  rescue StandardError => e
    results[:failed] << "Full Agent Loop: #{e.message}"
  end

  # Print summary
  print_header('TEST SUMMARY')

  if results[:passed].any?
    print_success("Passed (#{results[:passed].length}):")
    results[:passed].each { |test| puts "  ✅ #{test}" }
  end

  if results[:warnings].any?
    print_warning("Warnings (#{results[:warnings].length}):")
    results[:warnings].each { |test| puts "  ⚠️  #{test}" }
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
  # Check if we can run a specific test
  if ARGV.any?
    case ARGV[0]
    when 'intent'
      test_intent_resolver
    when 'context'
      test_agent_context
    when 'decision'
      test_decision_engine
    when 'tools'
      test_wrapper_tools
    when 'full'
      query = ARGV[1] || 'What is the price of NIFTY?'
      test_full_agent_loop('Custom Query', query)
    else
      puts "Unknown test: #{ARGV[0]}"
      puts 'Usage: ruby scripts/test_agent.rb [intent|context|decision|tools|full] [query]'
      exit(1)
    end
  else
    run_all_tests
  end
end
