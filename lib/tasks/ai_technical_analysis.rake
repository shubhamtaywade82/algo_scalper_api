# frozen_string_literal: true

require_relative '../telegram_notifier'

namespace :ai do
  desc 'Show example prompts and capabilities of the technical analysis agent'
  task examples: :environment do
    puts '=' * 100
    puts 'Technical Analysis Agent - Example Prompts & Capabilities'
    puts '=' * 100
    puts ''

    # Static examples organized by category
    static_examples = [
      {
        category: '📊 Market Data Queries',
        prompts: [
          'What is the current price of NIFTY?',
          'Get the LTP for BANKNIFTY and SENSEX',
          'What is the OHLC data for NIFTY?',
          'Show me historical price data for NIFTY for the last 7 days'
        ]
      },
      {
        category: '📈 Technical Indicators',
        prompts: [
          'What is the current RSI for NIFTY?',
          'Calculate MACD for BANKNIFTY on 5-minute timeframe',
          'What is the ADX value for SENSEX?',
          'Show me Supertrend signal for NIFTY',
          'Calculate ATR for BANKNIFTY',
          'What is the Bollinger Bands for NIFTY?'
        ]
      },
      {
        category: '🔬 Advanced Indicators',
        prompts: [
          'Calculate HolyGrail indicator for NIFTY',
          'What is the TrendDuration for BANKNIFTY?',
          'Analyze NIFTY using HolyGrail indicator to determine bias and momentum',
          'Check trend duration and confidence for SENSEX'
        ]
      },
      {
        category: '📉 Option Chain Analysis',
        prompts: [
          'Analyze NIFTY option chain for bullish trades',
          'Find the best bearish option candidates for BANKNIFTY',
          'What are the top 5 bullish options for SENSEX?',
          'Show me option chain analysis for NIFTY with bullish direction'
        ]
      },
      {
        category: '💰 Trading Statistics',
        prompts: [
          'What are my current trading statistics?',
          'Show me win rate and PnL for today',
          'What is my realized PnL for today?',
          'Get trading stats for a specific date (YYYY-MM-DD)'
        ]
      },
      {
        category: '📋 Position Management',
        prompts: [
          'What are my current active positions?',
          'Show me all active positions with their PnL',
          'What is the current PnL for my positions?'
        ]
      },
      {
        category: '🧪 Backtesting',
        prompts: [
          'Run a backtest for NIFTY for the last 90 days',
          'Backtest BANKNIFTY with 5-minute interval',
          'Test SENSEX strategy with custom Supertrend settings',
          'Run backtest for NIFTY with ADX minimum strength of 20'
        ]
      },
      {
        category: '⚙️ Optimization',
        prompts: [
          'Optimize indicator parameters for NIFTY',
          'Find best indicator settings for BANKNIFTY using 45 days of data',
          'Optimize parameters for SENSEX in test mode',
          'What are the optimal indicator parameters for NIFTY?'
        ]
      },
      {
        category: '🔍 Complex Analysis',
        prompts: [
          'Analyze NIFTY: get RSI, MACD, and option chain for bullish trades',
          'Compare BANKNIFTY and SENSEX: show RSI, ADX, and current prices',
          'Full analysis for NIFTY: indicators, option chain, and backtest results',
          'What is the market condition for NIFTY? Check indicators and option chain'
        ]
      }
    ]

    # Display static examples
    static_examples.each_with_index do |example, idx|
      puts "#{idx + 1}. #{example[:category]}"
      puts '-' * 100
      example[:prompts].each do |prompt|
        puts "   • #{prompt}"
      end
      puts ''
    end

    # Try to get AI-generated examples if AI is enabled
    if Services::Ai::OpenaiClient.instance.enabled?
      puts '=' * 100
      puts '🤖 AI-Generated Example Prompts'
      puts '=' * 100
      puts ''
      puts 'Generating additional examples based on available tools...'
      puts ''

      begin
        ai_query = <<~QUERY
          Based on the available tools (get_index_ltp, get_instrument_ltp, get_ohlc, calculate_indicator,
          calculate_advanced_indicator, get_historical_data, analyze_option_chain, get_trading_stats,
          get_active_positions, run_backtest, optimize_indicator), generate 5 creative and practical
          example prompts that a user might ask. Make them diverse and cover different use cases.
          Return only the prompts, one per line, without numbering or explanations.
        QUERY

        result = Services::Ai::TechnicalAnalysisAgent.analyze(query: ai_query)
        if result && result[:analysis]
          puts 'AI Suggestions:'
          puts '-' * 100
          # Extract prompts from AI response (split by lines, filter empty)
          prompts = result[:analysis].split("\n").map(&:strip).reject(&:empty?)
          prompts.each do |prompt|
            # Clean up common prefixes like "- ", "• ", numbers, etc.
            cleaned = prompt.gsub(/^[-•\d.\s]+/, '').strip
            puts "   • #{cleaned}" if cleaned.length > 10
          end
          puts ''
        end
      rescue StandardError => e
        Rails.logger.debug { "[AI Examples] Failed to generate AI examples: #{e.class} - #{e.message}" }
        puts '   (AI example generation skipped - using static examples only)'
        puts ''
      end
    end

    puts '=' * 100
    puts 'Usage:'
    puts '=' * 100
    puts ''
    puts '  bundle exec rake ai:technical_analysis["your question here"]'
    puts ''
    puts '  # With streaming:'
    puts '  STREAM=true bundle exec rake ai:technical_analysis["your question"]'
    puts ''
    puts 'Available Tools (11):'
    puts '  📊 Market Data:'
    puts '    • get_index_ltp - Get LTP for indices (NIFTY, BANKNIFTY, SENSEX)'
    puts '    • get_instrument_ltp - Get LTP for specific instruments'
    puts '    • get_ohlc - Get OHLC data'
    puts '    • get_historical_data - Get historical candles'
    puts ''
    puts '  📈 Technical Analysis:'
    puts '    • calculate_indicator - Calculate RSI, MACD, ADX, Supertrend, ATR, BollingerBands'
    puts '    • calculate_advanced_indicator - Calculate HolyGrail, TrendDuration'
    puts '    • analyze_option_chain - Analyze option chains and find candidates'
    puts ''
    puts '  💰 Trading & Positions:'
    puts '    • get_trading_stats - Get trading statistics (win rate, PnL)'
    puts '    • get_active_positions - Get active positions'
    puts ''
    puts '  🧪 Backtesting & Optimization:'
    puts '    • run_backtest - Run backtests on historical data'
    puts '    • optimize_indicator - Optimize indicator parameters'
    puts ''
  end

  desc 'Technical analysis agent - Ask questions about markets, indicators, positions'
  task :technical_analysis, [:query] => :environment do |_t, args|
    query = args[:query] || ENV.fetch('QUERY', nil)

    if query.blank?
      puts 'Usage: bundle exec rake ai:technical_analysis["your question"]'
      puts '   Or: QUERY="your question" bundle exec rake ai:technical_analysis'
      puts ''
      puts 'For example prompts and capabilities, run:'
      puts '  bundle exec rake ai:examples'
      puts ''
      puts 'Quick examples:'
      puts '  bundle exec rake ai:technical_analysis["What is the current RSI for NIFTY?"]'
      puts '  bundle exec rake ai:technical_analysis["Analyze BANKNIFTY option chain for bullish trades"]'
      puts '  bundle exec rake ai:technical_analysis["What are my current positions and their PnL?"]'
      exit 1
    end

    unless Services::Ai::OpenaiClient.instance.enabled?
      puts '❌ AI integration is not enabled or configured.'
      puts '   Set OPENAI_API_KEY or OLLAMA_BASE_URL environment variable'
      puts '   Enable AI in config/algo.yml: ai.enabled: true'
      exit 1
    end

    puts '=' * 100
    puts 'Technical Analysis Agent'
    puts '=' * 100
    puts ''
    puts "Query: #{query}"
    puts ''
    puts "Provider: #{Services::Ai::OpenaiClient.instance.provider}"
    puts ''

    # Check if streaming is requested
    stream = %w[true 1].include?(ENV.fetch('STREAM', nil))

    # Check if Telegram is enabled
    telegram_enabled = TelegramNotifier.enabled?

    if stream
      puts '📊 Analysis (streaming):'
      puts '-' * 100
      puts ''

      # Send typing indicator to Telegram if enabled
      TelegramNotifier.send_chat_action(action: 'typing') if telegram_enabled

      # Accumulate analysis-only chunks for Telegram (filtered - no verbose logs)
      telegram_analysis_buffer = +'' # Create mutable string (frozen_string_literal is enabled)
      # Escape HTML special characters in query only (keep header tags intact)
      escaped_query = query.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')

      result = Services::Ai::TechnicalAnalysisAgent.analyze(query: query, stream: true) do |chunk|
        if chunk
          print chunk
          $stdout.flush

          # Filter out verbose logs for Telegram - only keep actual analysis content
          if telegram_enabled
            # Skip verbose agent logs (intent, symbol, tool calls, agent status)
            # Match patterns at start of line or anywhere in chunk
            if chunk.to_s.match?(/🔍 \[Intent\]|📊 \[Symbol\]|🔧 \[Tool\]|✅ \[Tool\]|⚠️  \[Agent\]|📝 \[Agent\]|💭 \[Agent\]|📋 \[Tool\]|⚙️  \[Tool\]|⏹️  \[Agent\]/)
              next
            end

            # Only accumulate actual analysis content (not verbose logs)
            telegram_analysis_buffer << chunk
          end
        end
      end

      puts ''
      puts ''
      puts '-' * 100
      puts "Generated at: #{result[:generated_at]}" if result

      # Send complete message to Telegram (cleaned)
      if telegram_enabled && telegram_analysis_buffer.present?
        # Clean up the buffer - remove any remaining verbose logs
        cleaned_buffer = telegram_analysis_buffer.dup
        # Remove all verbose log patterns (comprehensive cleanup)
        cleaned_buffer.gsub!(/🔍 \[Intent\][^\n]*\n?/, '')
        cleaned_buffer.gsub!(/📊 \[Symbol\][^\n]*\n?/, '')
        cleaned_buffer.gsub!(/🔧 \[Tool\][^\n]*\n?/, '')
        cleaned_buffer.gsub!(/✅ \[Tool\][^\n]*\n?/, '')
        cleaned_buffer.gsub!(/⚠️  \[Agent\][^\n]*\n?/, '')
        cleaned_buffer.gsub!(/📝 \[Agent\][^\n]*\n?/, '')
        cleaned_buffer.gsub!(/💭 \[Agent\][^\n]*\n?/, '')
        cleaned_buffer.gsub!(/⚙️  \[Tool\][^\n]*\n?/, '')
        cleaned_buffer.gsub!(/⏹️  \[Agent\][^\n]*\n?/, '')
        cleaned_buffer.gsub!(/📋 \[Tool\] Result:[^\n]*\n?/, '')
        cleaned_buffer.gsub!(/📋 \[Tool\] Result:\s*\n/, '')
        # Remove JSON tool call results
        cleaned_buffer.gsub!(/\{"tool"[^}]*\}[^\n]*\n?/, '')
        cleaned_buffer.gsub!(/\{"name"[^}]*\}[^\n]*\n?/, '')
        cleaned_buffer.gsub!(/\n{3,}/, "\n\n") # Remove excessive newlines
        cleaned_buffer.strip!

        # Only send if there's actual analysis content
        if cleaned_buffer.strip.length > 20
          telegram_message = +"📊 <b>Technical Analysis: \"#{escaped_query}\"</b>\n\n"
          # Escape only analysis text (not HTML tags)
          escaped_analysis = cleaned_buffer.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')
          telegram_message << escaped_analysis
          telegram_message << "\n\n⏰ Generated at: #{result[:generated_at]}" if result&.dig(:generated_at)
          telegram_message << "\n🤖 Provider: #{result[:provider]}" if result&.dig(:provider)

          begin
            TelegramNotifier.send_message(telegram_message, parse_mode: 'HTML')
            puts "\n✅ Analysis sent to Telegram"
          rescue StandardError => e
            Rails.logger.error("[AI Technical Analysis] Failed to send to Telegram: #{e.class} - #{e.message}")
            puts "\n⚠️  Failed to send to Telegram: #{e.message}"
          end
        else
          puts "\n⚠️  Skipped Telegram send: no meaningful analysis content generated"
        end
      end
    else
      result = Services::Ai::TechnicalAnalysisAgent.analyze(query: query)

      if result
        puts '📊 Analysis:'
        puts '-' * 100
        puts result[:analysis]
        puts ''
        puts "Generated at: #{result[:generated_at]}"
        puts "Provider: #{result[:provider]}"

        # Send to Telegram if enabled
        if telegram_enabled && result[:analysis].present?
          # Escape HTML special characters in query
          escaped_query = query.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')
          telegram_message = "📊 <b>Technical Analysis: #{escaped_query}</b>\n\n" # Create mutable string
          # Escape HTML in analysis content
          escaped_analysis = result[:analysis].to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')
          telegram_message << escaped_analysis
          telegram_message << "\n\n⏰ Generated at: #{result[:generated_at]}" if result[:generated_at]
          telegram_message << "\n🤖 Provider: #{result[:provider]}" if result[:provider]

          begin
            TelegramNotifier.send_message(telegram_message, parse_mode: 'HTML')
            puts "\n✅ Analysis sent to Telegram"
          rescue StandardError => e
            Rails.logger.error("[AI Technical Analysis] Failed to send to Telegram: #{e.class} - #{e.message}")
            puts "\n⚠️  Failed to send to Telegram: #{e.message}"
          end
        end
      else
        puts '❌ Failed to generate analysis'
        exit 1
      end
    end
  end
end
