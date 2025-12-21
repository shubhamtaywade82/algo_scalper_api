#!/usr/bin/env ruby
# frozen_string_literal: true

# Interactive monitoring script for Technical Analysis Agent
# Run with: rails runner scripts/monitor_agent.rb
# Or: ruby scripts/monitor_agent.rb

require_relative '../config/environment' if defined?(Rails)

class AgentMonitor
  def initialize
    @agent = Services::Ai::TechnicalAnalysisAgent.new
    @errors = []
    @warnings = []
    @success_count = 0
  end

  def monitor_query(query, stream: false)
    puts "\n" + ('=' * 80)
    puts "QUERY: #{query}".bold
    puts '=' * 80
    puts "Time: #{Time.current}"
    puts "Stream mode: #{stream}"
    puts "\n"

    start_time = Time.current
    result = nil
    output = []

    begin
      result = @agent.analyze(query: query, stream: stream) do |chunk|
        output << chunk
        print chunk
      end

      elapsed = Time.current - start_time

      puts "\n" + ('-' * 80)
      puts 'RESULT SUMMARY'.bold
      puts '-' * 80
      puts "Elapsed time: #{elapsed.round(2)}s"

      if result
        puts "Verdict: #{result[:verdict]}"
        puts "Iterations: #{result[:iterations]}" if result[:iterations]
        puts "Context: #{result[:context].inspect}" if result[:context]

        if result[:error]
          puts "Error: #{result[:error]}".red
          @errors << { query: query, error: result[:error], time: Time.current }
        end

        if result[:verdict] == 'ANALYSIS_COMPLETE'
          @success_count += 1
          puts 'Status: SUCCESS'.green
        elsif result[:verdict] == 'NO_TRADE'
          @warnings << { query: query, reason: result[:reason], time: Time.current }
          puts "Status: NO_TRADE - #{result[:reason]}".yellow
        else
          @errors << { query: query, error: "Unexpected verdict: #{result[:verdict]}", time: Time.current }
          puts 'Status: UNEXPECTED'.red
        end
      else
        @errors << { query: query, error: 'No result returned', time: Time.current }
        puts 'Status: NO RESULT'.red
      end

      # Check output for errors
      output.each do |line|
        if line.match?(/error|Error|ERROR|failed|Failed|FAILED/i) && !line.match?(/NO_TRADE/)
          puts "⚠️  Warning in output: #{line.strip}".yellow
        end
      end
    rescue StandardError => e
      elapsed = Time.current - start_time
      puts "\n" + ('-' * 80)
      puts 'EXCEPTION CAUGHT'.bold.red
      puts '-' * 80
      puts "Error: #{e.class} - #{e.message}".red
      puts "Elapsed time: #{elapsed.round(2)}s"
      puts "\nBacktrace:"
      e.backtrace.first(10).each { |line| puts "  #{line}" }

      @errors << { query: query, error: "#{e.class}: #{e.message}", time: Time.current, backtrace: e.backtrace.first(5) }
    end

    result
  end

  def print_summary
    puts "\n" + ('=' * 80)
    puts 'MONITORING SESSION SUMMARY'.bold
    puts '=' * 80
    puts "Successes: #{@success_count}".green
    puts "Warnings: #{@warnings.length}".yellow
    puts "Errors: #{@errors.length}".red

    if @warnings.any?
      puts "\nWARNINGS:".yellow
      @warnings.each do |w|
        puts "  - #{w[:query]}: #{w[:reason]}"
      end
    end

    return unless @errors.any?

    puts "\nERRORS:".red
    @errors.each do |e|
      puts "  - #{e[:query]}: #{e[:error]}"
      if e[:backtrace]
        puts '    Backtrace:'
        e[:backtrace].each { |line| puts "      #{line}" }
      end
    end
  end
end

# Color helpers
class String
  def green = "\e[32m#{self}\e[0m"
  def red = "\e[31m#{self}\e[0m"
  def yellow = "\e[33m#{self}\e[0m"
  def blue = "\e[34m#{self}\e[0m"
  def cyan = "\e[36m#{self}\e[0m"
  def bold = "\e[1m#{self}\e[0m"
end

# Interactive mode
if __FILE__ == $PROGRAM_NAME
  monitor = AgentMonitor.new

  if ARGV.any?
    # Run specific query
    query = ARGV.join(' ')
    stream = ARGV.include?('--stream')
    monitor.monitor_query(query, stream: stream)
  else
    # Interactive mode
    puts '=' * 80
    puts 'AGENT MONITOR - Interactive Mode'.bold
    puts '=' * 80
    puts "Enter queries to test the agent. Type 'exit' to quit, 'summary' for summary."
    puts ''

    loop do
      print 'Query> '
      query = gets.chomp

      break if query.downcase == 'exit'

      if query.downcase == 'summary'
        monitor.print_summary
        next
      end

      next if query.empty?

      stream = query.include?('--stream')
      query = query.gsub('--stream', '').strip

      monitor.monitor_query(query, stream: stream)
    end

    monitor.print_summary
  end
end
