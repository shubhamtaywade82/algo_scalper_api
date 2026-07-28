#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'

class RailsProjectProfiler
  attr_reader :repo_root

  def initialize(repo_root = Dir.pwd)
    @repo_root = repo_root
  end

  def profile
    gemfile_lock_path = File.join(repo_root, 'Gemfile.lock')
    gemfile_lock_content = File.exist?(gemfile_lock_path) ? File.read(gemfile_lock_path) : ''

    {
      repository_root: repo_root,
      framework: detect_framework(gemfile_lock_content),
      testing: detect_testing_framework(gemfile_lock_content),
      background_jobs: detect_job_framework(gemfile_lock_content),
      cache_and_redis: detect_cache(gemfile_lock_content),
      database: detect_database(gemfile_lock_content),
      custom_project_rules: detect_project_rules,
      precedence_rule: [
        "1. User explicit instructions",
        "2. Project AGENTS.md / CLAUDE.md / .cursor rules",
        "3. Detected repository profile & existing architecture",
        "4. Team conventions",
        "5. External domain skills (Rails-AI / GoF patterns)"
      ]
    }
  end

  private

  def detect_framework(gemfile_lock)
    if gemfile_lock.include?('rails (')
      version = gemfile_lock.scan(/rails \((.*?)\)/).flatten.first || 'unknown'
      { name: 'rails', version: version, detected: true }
    else
      { name: 'ruby_standalone', detected: false }
    end
  end

  def detect_testing_framework(gemfile_lock)
    if gemfile_lock.include?('rspec-rails') || File.directory?(File.join(repo_root, 'spec')) || File.exist?(File.join(repo_root, '.rspec'))
      { framework: 'rspec', confidence: 0.99, minitest_override_required: true }
    elsif gemfile_lock.include?('minitest') || File.directory?(File.join(repo_root, 'test'))
      { framework: 'minitest', confidence: 0.90 }
    else
      { framework: 'unknown', confidence: 0.50 }
    end
  end

  def detect_job_framework(gemfile_lock)
    if gemfile_lock.include?('sidekiq')
      { framework: 'sidekiq', solid_queue_override_required: true }
    elsif gemfile_lock.include?('solid_queue')
      { framework: 'solid_queue' }
    elsif gemfile_lock.include?('delayed_job')
      { framework: 'delayed_job' }
    elsif gemfile_lock.include?('resque')
      { framework: 'resque' }
    else
      { framework: 'active_job_inline_or_default' }
    end
  end

  def detect_cache(gemfile_lock)
    has_redis = gemfile_lock.include?('redis')
    has_solid_cache = gemfile_lock.include?('solid_cache')
    { redis_present: has_redis, solid_cache_present: has_solid_cache }
  end

  def detect_database(gemfile_lock)
    if gemfile_lock.include?('pg')
      'postgresql'
    elsif gemfile_lock.include?('mysql2') || gemfile_lock.include?('trilogy')
      'mysql'
    elsif gemfile_lock.include?('sqlite3')
      'sqlite3'
    else
      'unknown'
    end
  end

  def detect_project_rules
    rules = []
    ['AGENTS.md', 'CLAUDE.md', '.cursor/rules', '.agents/rules'].each do |rule_path|
      full_path = File.join(repo_root, rule_path)
      rules << rule_path if File.exist?(full_path)
    end
    rules
  end
end

if __FILE__ == $0
  repo = ARGV[0] || Dir.pwd
  profiler = RailsProjectProfiler.new(repo)
  puts JSON.pretty_generate(profiler.profile)
end
