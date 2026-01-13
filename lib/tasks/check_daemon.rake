# frozen_string_literal: true

namespace :trading do
  desc 'Check if trading daemon is running and services are started'
  task check_daemon: :environment do
    puts '=' * 80
    puts 'TRADING DAEMON STATUS CHECK'
    puts '=' * 80
    puts ''

    # Check if daemon process is running
    puts '1. Checking for daemon process...'
    daemon_running = `ps aux | grep -E "trading:daemon|rake trading" | grep -v grep`.strip
    if daemon_running.empty?
      puts '   ❌ Daemon process NOT FOUND'
      puts ''
      puts '   To start the daemon, run:'
      puts '     ./bin/dev'
      puts '   or'
      puts '     ENABLE_TRADING_SERVICES=true bundle exec rake trading:daemon'
      puts ''
    else
      puts '   ✅ Daemon process FOUND'
      puts "   Process: #{daemon_running.split("\n").first}"
      puts ''
    end

    # Check environment variable
    puts '2. Checking environment...'
    puts "   ENABLE_TRADING_SERVICES: #{ENV['ENABLE_TRADING_SERVICES']}"
    puts "   Market closed: #{TradingSession::Service.market_closed?}"
    puts ''

    # Check supervisor in current process (web server)
    puts '3. Checking web server supervisor (register-only, services not started)...'
    supervisor = Rails.application.config.x.trading_supervisor
    if supervisor
      scheduler = supervisor[:signal_scheduler]
      if scheduler
        puts "   Signal Scheduler running: #{scheduler.running?}"
        puts '   ⚠️  NOTE: This is the web server process supervisor.'
        puts '      Services should be running in the daemon process, not here.'
      else
        puts '   ❌ Signal Scheduler not found in supervisor'
      end
    else
      puts '   ❌ Supervisor not initialized'
    end
    puts ''

    # Check recent logs for daemon activity
    puts '4. Checking recent logs for daemon activity...'
    log_file = Rails.root.join('log', "#{Rails.env}.log")
    if File.exist?(log_file)
      recent_logs = `tail -200 #{log_file} | grep -E "(TradingDaemon|Supervisor.*started signal_scheduler)" | tail -5`.strip
      if recent_logs.empty?
        puts '   ⚠️  No recent daemon activity in logs'
        puts '      This suggests the daemon may not have started or logged yet'
      else
        puts '   ✅ Recent daemon activity found:'
        recent_logs.split("\n").each do |line|
          puts "      #{line}"
        end
      end
    else
      puts "   ⚠️  Log file not found: #{log_file}"
    end
    puts ''

    # Instructions
    puts '=' * 80
    puts 'INSTRUCTIONS'
    puts '=' * 80
    puts ''
    puts 'To start the trading daemon:'
    puts '  1. Stop any running ./bin/dev process (Ctrl+C)'
    puts '  2. Restart: ./bin/dev'
    puts '  3. You should see two processes start:'
    puts '     - web: bin/rails server -p 3000'
    puts '     - trading: ENABLE_TRADING_SERVICES=true bundle exec rake trading:daemon'
    puts ''
    puts 'Look for these log messages when daemon starts:'
    puts '  [TradingDaemon] Started'
    puts '  [Supervisor] started signal_scheduler'
    puts '  [Supervisor] started market_feed'
    puts '  [Supervisor] started risk_manager'
    puts '  ... (and other services)'
    puts ''
    puts 'To verify signal scheduler is running in daemon:'
    puts '  Watch the logs for: [SignalScheduler] Starting analysis for...'
    puts '  (This should appear every 30 seconds when market is open)'
    puts ''
  end
end
