#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'open3'
require_relative 'ruby_prism_ast_analyzer'

class RubySmellDetector
  attr_reader :target_path

  def initialize(target_path)
    @target_path = target_path
  end

  def run
    smells = []

    # 1. Run Reek if available
    reek_smells = run_reek
    smells.concat(reek_smells)

    # 2. Run AST/Rails heuristics
    ast_smells = run_ast_heuristics
    smells.concat(ast_smells)

    {
      target: target_path,
      total_smells: smells.size,
      smells: smells
    }
  end

  private

  def run_reek
    return [] unless system('which reek > /dev/null 2>&1')

    stdout, _stderr, _status = Open3.capture3("reek --format json #{target_path}")
    return [] if stdout.empty?

    begin
      parsed = JSON.parse(stdout)
      parsed.map do |smell|
        {
          source: 'reek',
          smell_type: smell['smell_type'] || smell['type'],
          class_or_module: smell['context'],
          lines: smell['lines'],
          message: smell['message'],
          confidence: 0.90
        }
      end
    rescue JSON::ParserError
      []
    end
  end

  def run_ast_heuristics
    files = File.directory?(target_path) ? Dir.glob(File.join(target_path, '**/*.rb')) : [target_path]
    smells = []

    files.each do |file|
      next unless File.exist?(file)

      analyzer = PrismAstAnalyzer.new(file)
      data = analyzer.analyze
      metrics = data[:metrics]

      # Smell: Long Method (> 30 lines)
      data[:methods].each do |m|
        if m[:loc] > 30
          smells << {
            source: 'ast_heuristics',
            smell_type: 'LongMethod',
            class_or_module: data[:classes].first || data[:modules].first || file,
            lines: [m[:start_line], m[:end_line]],
            message: "Method '#{m[:name]}' has #{m[:loc]} lines (threshold: 30)",
            confidence: 0.95
          }
        end
      end

      # Smell: Switch Statements / Heavy Conditionals
      if metrics[:branch_count] > 5
        smells << {
          source: 'ast_heuristics',
          smell_type: 'SwitchStatements',
          class_or_module: data[:classes].first || data[:modules].first || file,
          lines: [1],
          message: "File has #{metrics[:branch_count]} branches (conditional density: #{metrics[:conditional_density]})",
          confidence: 0.88
        }
      end

      # Smell: Fat Controller (Rails heuristic)
      if file.include?('/controllers/') && data[:loc] > 100
        smells << {
          source: 'rails_heuristics',
          smell_type: 'FatController',
          class_or_module: data[:classes].first || file,
          lines: [1],
          message: "Controller file has #{data[:loc]} LOC (threshold: 100). Consider extracting Service/Command objects.",
          confidence: 0.92
        }
      end

      # Smell: Callback Chain Heavy Model
      if file.include?('/models/') && (data[:loc] > 150 || metrics[:class_fan_out] > 10)
        smells << {
          source: 'rails_heuristics',
          smell_type: 'GodModel',
          class_or_module: data[:classes].first || file,
          lines: [1],
          message: "Model file has #{data[:loc]} LOC and fan-out #{metrics[:class_fan_out]}. Consider Domain Services / POROs.",
          confidence: 0.89
        }
      end
    end

    smells
  end
end

if __FILE__ == $0
  if ARGV.empty?
    puts "Usage: ruby_reek_smell_detector.rb <file_or_dir_path>"
    exit 1
  end

  detector = RubySmellDetector.new(ARGV[0])
  puts JSON.pretty_generate(detector.run)
end
