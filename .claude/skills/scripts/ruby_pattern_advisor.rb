#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require_relative 'ruby_reek_smell_detector'

class PatternAdvisor
  attr_reader :file_or_dir

  def initialize(file_or_dir)
    @file_or_dir = file_or_dir
  end

  def evaluate
    smell_result = RubySmellDetector.new(file_or_dir).run
    smells = smell_result[:smells]

    candidates = []

    smell_types = smells.map { |s| s[:smell_type] }

    # Strategy Pattern Candidate
    if smell_types.include?('SwitchStatements') || smell_types.include?('RepeatedConditional')
      candidates << {
        pattern: 'Strategy',
        confidence: 0.88,
        smell_trigger: 'SwitchStatements / RepeatedConditional',
        justification: 'Interchangeable algorithms selected dynamically via branching.',
        rails_idiom: 'PORO strategy classes or callable objects',
        rspec_contract: 'Verify strategy interface delegation contract'
      }
    end

    # Adapter Pattern Candidate
    if smell_types.include?('ExternalServiceCoupling') || file_or_dir.include?('/clients/') || file_or_dir.include?('/api/')
      candidates << {
        pattern: 'Adapter',
        confidence: 0.91,
        smell_trigger: 'External API / Client Coupling',
        justification: 'Incompatible external API interface wrapped in domain adapter.',
        rails_idiom: 'Gateway/Client PORO adapters (e.g. DhanGateway, StripeAdapter)',
        rspec_contract: 'Contract specs for provider request/response mapping'
      }
    end

    # Command Pattern Candidate
    if smell_types.include?('FatController') || smell_types.include?('LongMethod')
      candidates << {
        pattern: 'Command',
        confidence: 0.86,
        smell_trigger: 'FatController / LongMethod',
        justification: 'Complex application workflow encapsulated into an executable operation.',
        rails_idiom: 'Application Service Object (e.g. Orders::Place.call)',
        rspec_contract: 'Isolated unit test for command input/output & side-effects'
      }
    end

    # Facade Pattern Candidate
    if smell_types.include?('GodModel') || smell_types.include?('HighFanOut')
      candidates << {
        pattern: 'Facade',
        confidence: 0.82,
        smell_trigger: 'GodModel / HighFanOut',
        justification: 'Complex multi-component subsystem unified under a simplified interface.',
        rails_idiom: 'Subsystem Facade / Domain Service',
        rspec_contract: 'Subsystem integration spec'
      }
    end

    # Decorator Pattern Candidate
    if smell_types.include?('PresenterNeeded') || file_or_dir.include?('/views/') || file_or_dir.include?('/serializers/')
      candidates << {
        pattern: 'Decorator',
        confidence: 0.84,
        smell_trigger: 'View/Serialization Logic Leak',
        justification: 'Add dynamic presentation behavior without polluting domain model.',
        rails_idiom: 'SimpleDelegator / Presenter / ViewComponent',
        rspec_contract: 'Presenter delegation & formatting unit test'
      }
    end

    # Filter by confidence threshold (> 0.70)
    candidates.select! { |c| c[:confidence] >= 0.70 }

    if candidates.empty?
      {
        target: file_or_dir,
        verdict: 'NO_PATTERN',
        reasoning: 'No structural smell threshold exceeded. Standard Ruby composition/PORO is sufficient.',
        candidates: []
      }
    else
      {
        target: file_or_dir,
        verdict: candidates.map { |c| c[:pattern] }.join(' + '),
        candidates: candidates
      }
    end
  end
end

if __FILE__ == $0
  if ARGV.empty?
    puts "Usage: ruby_pattern_advisor.rb <file_or_dir_path>"
    exit 1
  end

  advisor = PatternAdvisor.new(ARGV[0])
  puts JSON.pretty_generate(advisor.evaluate)
end
