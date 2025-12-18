# frozen_string_literal: true

namespace :ai do
  desc 'Analyze trading day using AI'
  task analyze_day: :environment do
    date = ENV['DATE'] ? Date.parse(ENV['DATE']) : Time.zone.today

    puts '=' * 100
    puts "AI Trading Day Analysis: #{date.strftime('%Y-%m-%d')}"
    puts '=' * 100
    puts ''

    unless Services::Ai::OpenaiClient.instance.enabled?
      puts '❌ AI integration is not enabled or configured.'
      puts '   Set OPENAI_API_KEY or OPENAI_ACCESS_TOKEN environment variable'
      puts '   Enable AI in config/algo.yml: ai.enabled: true'
      exit 1
    end

    puts "Provider: #{Services::Ai::OpenaiClient.instance.provider}"
    puts ''

    result = Services::Ai::TradingAnalyzer.analyze_trading_day(date: date)

    if result
      puts '📊 AI Analysis Results:'
      puts '-' * 100
      puts result[:analysis]
      puts ''
      puts "Generated at: #{result[:generated_at]}"
      puts "Provider: #{result[:provider]}"
    else
      puts '❌ Failed to generate AI analysis'
    end
  end

  desc 'Get AI strategy improvement suggestions'
  task suggest_improvements: :environment do
    unless Services::Ai::OpenaiClient.instance.enabled?
      puts '❌ AI integration is not enabled or configured.'
      exit 1
    end

    today = Time.zone.today - 1
    stats = PositionTracker.paper_trading_stats_with_pct(date: today)

    performance_data = {
      win_rate: stats[:win_rate],
      realized_pnl: stats[:realized_pnl_rupees],
      total_trades: stats[:total_trades],
      winners: stats[:winners],
      losers: stats[:losers]
    }

    # Check if streaming is requested
    stream = %w[true 1].include?(ENV.fetch('STREAM', nil))

    if stream
      puts '💡 Strategy Improvement Suggestions (streaming):'
      puts '-' * 100
      puts ''
      result = Services::Ai::TradingAnalyzer.suggest_strategy_improvements(
        performance_data: performance_data,
        stream: true
      ) do |chunk|
        print chunk if chunk
        $stdout.flush
      end
      puts ''
      puts ''
      puts '-' * 100
      puts "Generated at: #{result[:generated_at]}" if result
    else
      result = Services::Ai::TradingAnalyzer.suggest_strategy_improvements(performance_data: performance_data)

      if result
        puts '💡 Strategy Improvement Suggestions:'
        puts '-' * 100
        puts result[:suggestions]
        puts ''
        puts "Generated at: #{result[:generated_at]}"
      else
        puts '❌ Failed to generate suggestions'
      end
    end
  end

  desc 'Test AI client connection'
  task test: :environment do
    puts 'Testing AI Client...'
    puts ''

    client = Services::Ai::OpenaiClient.instance

    unless client.enabled?
      puts '❌ AI client is not enabled'
      puts '   Set OPENAI_API_KEY or OPENAI_ACCESS_TOKEN environment variable'
      puts '   Or set OLLAMA_BASE_URL for Ollama'
      puts '   Enable AI in config/algo.yml: ai.enabled: true'
      exit 1
    end

    puts '✅ AI client enabled'
    puts "   Provider: #{client.provider}"

    # Show available models for Ollama
    if client.provider == :ollama
      if client.available_models&.any?
        puts "   Available models: #{client.available_models.join(', ')}"
        puts "   Selected model: #{client.selected_model || 'auto-selecting...'}"
      else
        puts '   Fetching available models...'
        models = client.fetch_available_models
        if models.any?
          puts "   Available models: #{models.join(', ')}"
          puts "   Selected model: #{client.selected_model || client.select_best_model}"
        else
          puts '   ⚠️  No models found. Pull a model: ollama pull llama3'
        end
      end
    end
    puts ''

    # Determine model to use
    test_model = if client.provider == :ollama
                   client.selected_model || client.select_best_model || ENV['OLLAMA_MODEL'] || 'llama3'
                 else
                   'gpt-4o'
                 end

    puts "Testing chat completion (model: #{test_model})..."
    response = client.chat(
      messages: [
        { role: 'user', content: 'Say "AI integration working" if you can read this.' }
      ],
      model: test_model,
      temperature: 0.7
    )

    if response
      puts '✅ Chat completion successful:'
      puts "   Response: #{response}"
    else
      puts '❌ Chat completion failed'
      exit 1
    end
  end

  desc 'List available Ollama models'
  task list_models: :environment do
    client = Services::Ai::OpenaiClient.instance

    unless client.enabled? && client.provider == :ollama
      puts '❌ Ollama is not configured or enabled'
      puts '   Set OLLAMA_BASE_URL environment variable'
      puts '   Enable AI in config/algo.yml: ai.enabled: true'
      exit 1
    end

    puts 'Fetching available Ollama models...'
    puts ''

    models = client.fetch_available_models

    if models.any?
      puts "Found #{models.count} model(s):"
      models.each_with_index do |model, idx|
        marker = model == client.selected_model ? '⭐ (selected)' : ''
        puts "  #{idx + 1}. #{model} #{marker}"
      end
      puts ''
      puts "Best model: #{client.selected_model || client.select_best_model}"
    else
      puts '❌ No models found'
      puts '   Pull a model: ollama pull llama3'
      puts '   Or: docker exec ollama ollama pull llama3'
    end
  end
end
