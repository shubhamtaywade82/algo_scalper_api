# frozen_string_literal: true

namespace :ai do
  namespace :agents do
    desc 'Run one advisory pass across all Ai::Agents (market/strategy/risk/execution/post-trade/calibration). ' \
         'Advisor-only — no order placement, no config changes. Usage: rake ai:agents:run_cycle[NIFTY|BANKNIFTY]'
    task :run_cycle, [:index_keys] => :environment do |_, args|
      index_keys = args[:index_keys]&.split('|')&.map(&:upcase)
      index_keys ||= Ai::Agents::Orchestrator::DEFAULT_INDEX_KEYS

      puts "[Ai::Agents::Orchestrator] Running advisory cycle for: #{index_keys.join(', ')}"
      puts '=' * 60

      results = Ai::Agents::Orchestrator.run_cycle(index_keys: index_keys)

      results.each do |key, result|
        status = result[:error] ? "ERROR: #{result[:error]}" : (result[:output] || {}).to_json
        puts "[#{key}] #{status}"
      end

      puts "\n[Ai::Agents::Orchestrator] Done. See AgentDecisionLog for full detail, " \
           'Ai::Agents::AgentSupervisor.instance.status for a rollup.'
    end

    desc 'Print Ai::Agents::AgentSupervisor status (authority levels, recent decisions per agent)'
    task status: :environment do
      status = Ai::Agents::AgentSupervisor.instance.status
      puts JSON.pretty_generate(status.transform_values { |v| v.transform_values(&:to_s) })
    end
  end
end
