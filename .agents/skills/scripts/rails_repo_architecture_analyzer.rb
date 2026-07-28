#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require_relative 'ruby_prism_ast_analyzer'
require_relative 'ruby_reek_smell_detector'
require_relative 'ruby_pattern_advisor'
require_relative 'rails_project_profiler'

class RailsRepoArchitectureAnalyzer
  attr_reader :repo_root, :target_dirs

  def initialize(repo_root = Dir.pwd)
    @repo_root = repo_root
    @target_dirs = %w[app lib].map { |d| File.join(repo_root, d) }.select { |d| File.directory?(d) }
  end

  def analyze
    project_profile = RailsProjectProfiler.new(repo_root).profile

    files = target_dirs.flat_map { |dir| Dir.glob(File.join(dir, '**/*.rb')) }.uniq
    files.reject! { |f| f.include?('/vendor/') || f.include?('/db/migrate/') || f.include?('/tmp/') }

    file_results = []
    all_smells = []
    pattern_candidates = []

    total_loc = 0
    total_methods = 0
    total_branches = 0

    files.each do |file|
      rel_file = file.sub(/^#{Regexp.escape(repo_root)}\//, '')

      # 1. AST Analysis
      ast_data = PrismAstAnalyzer.new(file).analyze
      metrics = ast_data[:metrics]

      total_loc += ast_data[:loc]
      total_methods += metrics[:method_count]
      total_branches += metrics[:branch_count]

      # 2. Smell Analysis
      smell_data = RubySmellDetector.new(file).run
      smell_list = smell_data[:smells] || []
      all_smells.concat(smell_list)

      # 3. Pattern Evaluation for complex files
      if metrics[:branch_count] > 5 || metrics[:max_method_loc] > 30 || smell_list.size > 2
        advisor_res = PatternAdvisor.new(file).evaluate
        if advisor_res[:candidates].any?
          pattern_candidates << {
            file: rel_file,
            verdict: advisor_res[:verdict],
            candidates: advisor_res[:candidates]
          }
        end
      end

      # Hotspot scoring
      hotspot_score = (ast_data[:loc] * 0.2) + (metrics[:branch_count] * 2.0) + (smell_list.size * 5.0)

      file_results << {
        file: rel_file,
        loc: ast_data[:loc],
        methods: metrics[:method_count],
        branches: metrics[:branch_count],
        max_method_loc: metrics[:max_method_loc],
        smell_count: smell_list.size,
        hotspot_score: hotspot_score.round(1)
      }
    end

    top_hotspots = file_results.sort_by { |f| -f[:hotspot_score] }.take(10)

    # Health Score Calculation (100 base, deducted by smell density and high complexity)
    smell_density = files.any? ? (all_smells.size.to_f / files.size).round(2) : 0.0
    health_score = [100 - (smell_density * 8.0) - (top_hotspots.size > 0 ? 5 : 0), 10.0].max.round(1)

    {
      repository: repo_root,
      project_profile: project_profile,
      summary: {
        total_files_scanned: files.size,
        total_loc: total_loc,
        total_methods: total_methods,
        total_branches: total_branches,
        total_smells_detected: all_smells.size,
        health_score: "#{health_score}/100"
      },
      top_refactoring_hotspots: top_hotspots,
      pattern_recommendations: pattern_candidates,
      smell_breakdown: aggregate_smells(all_smells)
    }
  end

  private

  def aggregate_smells(smells)
    counts = Hash.new(0)
    smells.each { |s| counts[s[:smell_type]] += 1 }
    counts.sort_by { |_k, v| -v }.to_h
  end
end

if __FILE__ == $0
  repo_root = ARGV[0] || Dir.pwd
  analyzer = RailsRepoArchitectureAnalyzer.new(repo_root)
  puts JSON.pretty_generate(analyzer.analyze)
end
