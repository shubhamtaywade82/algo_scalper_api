#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require_relative 'ruby_prism_ast_analyzer'
require_relative 'ruby_reek_smell_detector'
require_relative 'rails_git_cochange'
require_relative 'ruby_pattern_advisor'
require_relative 'rails_project_profiler'

class RailsContextCompiler
  attr_reader :target_file, :repo_root

  def initialize(target_file, repo_root = nil)
    @target_file = target_file
    @repo_root = repo_root || find_repo_root(target_file)
  end

  def compile
    unless File.exist?(target_file)
      return { error: "Target file not found: #{target_file}" }
    end

    project_profile = RailsProjectProfiler.new(repo_root).profile
    ast_data = PrismAstAnalyzer.new(target_file).analyze
    smell_data = RubySmellDetector.new(target_file).run
    git_data = GitCochangeAnalyzer.new(target_file).analyze
    pattern_data = PatternAdvisor.new(target_file).evaluate
    test_file = find_test_file(target_file, project_profile[:testing][:framework])

    {
      task_context: {
        primary_file: target_file,
        project_profile: project_profile,
        classes: ast_data[:classes],
        metrics: ast_data[:metrics],
        smells: smell_data[:smells],
        files_to_touch_mapping: git_data[:cochange],
        associated_test_file: test_file,
        pattern_recommendation: pattern_data[:verdict],
        pattern_details: pattern_data[:candidates]
      }
    }
  end

  private

  def find_repo_root(file)
    dir = File.dirname(file)
    while dir != '/'
      return dir if File.exist?(File.join(dir, 'Gemfile')) || File.exist?(File.join(dir, 'AGENTS.md')) || File.directory?(File.join(dir, '.git'))
      dir = File.dirname(dir)
    end
    Dir.pwd
  end

  def find_test_file(file, preferred_framework)
    if file.start_with?(repo_root)
      rel = file.sub(/^#{Regexp.escape(repo_root)}\//, '')
    else
      rel = file
    end

    if preferred_framework == 'rspec'
      spec_path = File.join(repo_root, rel.sub(/^app\//, 'spec/').sub(/\.rb$/, '_spec.rb'))
      return spec_path if File.exist?(spec_path)
    else
      test_path = File.join(repo_root, rel.sub(/^app\//, 'test/').sub(/\.rb$/, '_test.rb'))
      return test_path if File.exist?(test_path)
    end
    nil
  end
end

if __FILE__ == $0
  if ARGV.empty?
    puts "Usage: rails_context_compiler.rb <target_file> [repo_root]"
    exit 1
  end

  compiler = RailsContextCompiler.new(ARGV[0], ARGV[1])
  puts JSON.pretty_generate(compiler.compile)
end
