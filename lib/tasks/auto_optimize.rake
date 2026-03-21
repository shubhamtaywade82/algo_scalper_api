# frozen_string_literal: true

namespace :trading do
  desc 'Automatically analyze, calibrate via local Ollama/Claude configurations, and apply profitable configurations'
  task auto_optimize: :environment do
    puts "================================================================="
    puts "🚀 STARTING AUTOMATED PROFITABILITY OPTIMIZATION LOOP 🚀"
    puts "================================================================="
    
    # 1. We optimize parameters for the major indices
    symbols = %w[NIFTY SENSEX BANKNIFTY]
    days = ENV.fetch('DAYS', '30').to_i

    symbols.each do |symbol|
      puts "\n[AutoOptimize] 📈 Analyzing #{symbol} over the last #{days} days..."
      
      begin
        # Ai::Calibration::Runner handles compiling the dataset, building the Claude-style
        # prompt, querying the local Ollama via ollama-client, and backtesting the result.
        run = Ai::Calibration::Runner.call(symbol: symbol, days: days)
        
        if run.nil?
          puts "[AutoOptimize] ⚠️  No profitable configuration found for #{symbol} (rejected by backtest or AI error)"
          next
        end

        puts "[AutoOptimize] ✅ Profitable configuration found! (Run ##{run.id})"
        puts "[AutoOptimize] 🛠️  Diagnosis: #{run.raw_stats.dig('diagnosis', 'primary_failure')}"
        
        # 2. Automatically apply the profitable configuration to algo.yml
        puts "[AutoOptimize] ⚡ Applying configuration automatically..."
        run.apply!(applied_by: 'auto_optimize_loop')
        
        puts "[AutoOptimize] 🎉 Configuration applied for #{symbol}. System is now optimized!"
        
      rescue Ai::Calibration::Runner::InsufficientDataError => e
        puts "[AutoOptimize] ⏸️  Not enough data to optimize #{symbol}: #{e.message}"
      rescue StandardError => e
        puts "[AutoOptimize] ❌ Failed to optimize #{symbol}: #{e.class} - #{e.message}"
      end
    end

    puts "\n================================================================="
    puts "🏁 AUTOMATED OPTIMIZATION LOOP COMPLETE 🏁"
    puts "================================================================="
  end
end
