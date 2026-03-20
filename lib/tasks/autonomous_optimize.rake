# frozen_string_literal: true

namespace :trading do
  desc "Run full autonomous Observe-Think-Act loop for one or all symbols"
  task autonomous_optimize: :environment do
    symbols = ENV['SYMBOL'] ? [ENV['SYMBOL'].upcase] : IndexInstrumentCache::INDEX_KEYS
    days = (ENV['DAYS'] || 30).to_i

    puts "🤖 Starting Autonomous Optimization Engine (AIL) for #{symbols.join(', ')}"
    puts "-----------------------------------------------------------------------"

    symbols.each do |symbol|
      begin
        result = Ai::Autonomous::Orchestrator.call(symbol: symbol, days: days)

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
