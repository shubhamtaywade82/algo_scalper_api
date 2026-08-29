# frozen_string_literal: true

namespace :agent do
  desc "Run central self-healing cycle across trading error logs"
  task heal: :environment do
    service_path = ENV.fetch(
      "AGENT_HEALING_SERVICE_PATH",
      File.expand_path("../../../../../local-agent-stack/rails-orchestrator/self_healing_service.rb", __dir__)
    )
    require service_path

    model = ENV.fetch("HEALING_MODEL", "gpt-oss:120b")
    puts "[Agent] Running self-healing cycle using #{model}..."

    service = SelfHealingService.new(model: model, min_occurrences: 2)
    results = service.run_healing_cycle

    puts "[Agent] Scanned: #{results[:scanned_patterns]} error pattern(s)"
    puts "[Agent] Promoted: #{results[:promoted_rules]} permanent rule(s)"
  end
end
