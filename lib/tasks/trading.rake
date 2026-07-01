# frozen_string_literal: true

namespace :trading do
  desc 'Start trading system daemon (separate process)'
  task daemon: :environment do
    TradingSystem::Daemon.start
  end

  desc 'Start interactive trading agent REPL'
  task agent: :environment do
    model = ENV['TRADING_AGENT_MODEL']
    saved = File.read(Rails.root.join('tmp', '.last_model')).strip rescue nil
    effective_model = model || saved || 'gpt-oss:20b-cloud'

    puts 'Starting Trading Agent REPL...'
    puts "Model: #{effective_model}"
    puts

    Ai::TradingAgent::Repl.new(model: effective_model).start
  end

  desc 'Start automated trading bot'
  task bot: :environment do
    mode = ENV.fetch('TRADING_BOT_MODE', 'paper')
    symbols = (ENV['TRADING_BOT_SYMBOLS'] || 'NIFTY,BANKNIFTY').split(',').map(&:strip)

    puts "Starting Trading Bot (#{mode.upcase} mode)..."
    puts "Symbols: #{symbols.join(', ')}"
    puts

    config = Ai::TradingBot::Config.load(
      mode: mode,
      symbols: symbols,
      model: ENV['TRADING_AGENT_MODEL'] || ENV['OLLAMA_MODEL']
    )

    Ai::TradingBot::Engine.new(config).run
  end
end

