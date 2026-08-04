# frozen_string_literal: true

namespace :trading do
  desc "Run full autonomous Observe-Think-Act loop for one or all symbols"
  task autonomous_optimize: :environment do
    symbols = ENV['SYMBOL'] ? [ENV['SYMBOL'].upcase] : IndiaIndexRegistry.all_by_key.keys
    days = (ENV['DAYS'] || 30).to_i
    dry_run = ENV['DRY_RUN'] == 'true'

    puts "🤖 Starting Autonomous Optimization Engine (AIL) for #{symbols.join(', ')} (Dry Run: #{dry_run})"
    puts "-----------------------------------------------------------------------"

    symbols.each do |symbol|
      begin
        result = Ai::Autonomous::Orchestrator.call(symbol: symbol, days: days, dry_run: dry_run)

        if result[:status] == :success
          strategy = result[:strategy]
          puts "✅ [#{symbol}] Optimized successfully!"
          puts "   Strategy: #{strategy['selected_solver']}"
          puts "   Reasoning: #{strategy['reasoning']}"
          puts "   Expected Improvement: #{strategy['expected_outcome']}"
        elsif result[:status] == :skipped
          puts "⏭️ [#{symbol}] Skipped: #{result[:reason]}"
        else
          puts "❌ [#{symbol}] Failed: #{result[:reason] || result[:message]}"
        end
      rescue StandardError => e
        puts "💥 [#{symbol}] Critical Error: #{e.message}"
        Rails.logger.error("[AutonomousTask] Error for #{symbol}: #{e.message}")
      end
      puts "-----------------------------------------------------------------------"
    end

    puts "🚀 Autonomous optimization loop complete."
  end
end
