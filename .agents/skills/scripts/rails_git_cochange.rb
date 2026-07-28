#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'open3'

class GitCochangeAnalyzer
  attr_reader :file_path, :max_commits

  def initialize(file_path, max_commits = 100)
    @file_path = file_path
    @max_commits = max_commits
  end

  def analyze
    unless system('git rev-parse --is-inside-work-tree > /dev/null 2>&1')
      return { file: file_path, error: 'Not inside a git repository', cochange: [] }
    end

    rel_path = file_path.sub(%r{^#{Regexp.escape(Dir.pwd)}/}, '')

    # Get commits touching target file
    commits_cmd = "git log --follow -n #{max_commits} --format='%H' -- #{Shellwords.escape(rel_path)}"
    commits = `#{commits_cmd}`.split("\n").map(&:strip).reject(&:empty?)

    return { file: rel_path, commit_count: 0, cochange: [] } if commits.empty?

    cochange_counts = Hash.new(0)
    total_commits = commits.size

    commits.each do |commit|
      files_cmd = "git show --stat --name-only --format='' #{commit}"
      changed_files = `#{files_cmd}`.split("\n").map(&:strip).reject(&:empty?)

      changed_files.each do |other_file|
        next if other_file == rel_path
        cochange_counts[other_file] += 1
      end
    end

    ranked = cochange_counts.map do |other_file, count|
      score = (count.to_f / total_commits).round(2)
      {
        file: other_file,
        cochange_count: count,
        cochange_frequency: score,
        relevance: score > 0.5 ? 'HIGH' : (score > 0.2 ? 'MEDIUM' : 'LOW')
      }
    end.sort_by { |item| -item[:cochange_frequency] }

    {
      file: rel_path,
      commit_count: total_commits,
      cochange: ranked.take(15)
    }
  end
end

require 'shellwords'

if __FILE__ == $0
  if ARGV.empty?
    puts "Usage: rails_git_cochange.rb <file_path> [max_commits]"
    exit 1
  end

  file_path = ARGV[0]
  max_commits = (ARGV[1] || 100).to_i
  analyzer = GitCochangeAnalyzer.new(file_path, max_commits)
  puts JSON.pretty_generate(analyzer.analyze)
end
