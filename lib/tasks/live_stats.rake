# frozen_string_literal: true

namespace :trading do
  desc 'Display live paper trading statistics (updates in place)'
  task live_stats: :environment do
    require 'io/console'

    # Ensure stdout is not buffered
    $stdout.sync = true
    $stderr.sync = true

    # Check if we're in a TTY (interactive terminal)
    is_tty = $stdout.tty?

    # Print header once
    puts '📊 Live Paper Trading Statistics'
    puts 'Press Ctrl+C to stop'
    puts '-' * 80

    begin
      loop do
        stats = PositionTracker.paper_trading_stats_with_pct

        # Format the output nicely
        output = format(
          "Trades: %d | Active: %d | Total PnL: ₹%.2f (%.2f%%) | " \
          "Realized: ₹%.2f (%.2f%%) | Unrealized: ₹%.2f (%.2f%%) | " \
          "Win Rate: %.2f%% | Winners: %d | Losers: %d",
          stats[:total_trades],
          stats[:active_positions],
          stats[:total_pnl_rupees],
          stats[:total_pnl_pct],
          stats[:realized_pnl_rupees],
          stats[:realized_pnl_pct],
          stats[:unrealized_pnl_rupees],
          stats[:unrealized_pnl_pct],
          stats[:win_rate],
          stats[:winners],
          stats[:losers]
        )

        if is_tty
          # Move cursor to beginning of line, clear to end, print output
          # \r = carriage return (move to start), \033[K = clear to end of line
          print "\r\033[K#{output}"
        else
          # Fallback: just print with newline if not a TTY
          puts output
        end

        $stdout.flush

        sleep 2 # Update every 2 seconds
      end
    rescue Interrupt
      puts "\n\n✅ Stopped"
    end
  end

  desc 'Display live paper trading statistics (full hash format, updates in place)'
  task live_stats_hash: :environment do
    # Ensure stdout is not buffered
    $stdout.sync = true
    $stderr.sync = true

    # Check if we're in a TTY (interactive terminal)
    is_tty = $stdout.tty?

    # Print header once
    puts '📊 Live Paper Trading Statistics (Hash Format)'
    puts 'Press Ctrl+C to stop'
    puts '-' * 80

    begin
      loop do
        stats = PositionTracker.paper_trading_stats_with_pct
        hash_output = stats.inspect

        if is_tty
          # Move cursor to beginning of line, clear to end, print hash
          # \r = carriage return (move to start), \033[K = clear to end of line
          print "\r\033[K#{hash_output}"
        else
          # Fallback: just print with newline if not a TTY
          puts hash_output
        end

        $stdout.flush

        sleep 2 # Update every 2 seconds
      end
    rescue Interrupt
      puts "\n\n✅ Stopped"
    end
  end

  desc 'Display live paper trading statistics (formatted table, updates in place)'
  task live_stats_table: :environment do
    require 'io/console'

    puts '📊 Live Paper Trading Statistics'
    puts 'Press Ctrl+C to stop'
    puts '=' * 80

    begin
      loop do
        stats = PositionTracker.paper_trading_stats_with_pct

        # Move cursor up to clear previous output (assuming ~15 lines)
        print "\e[15A" # Move up 15 lines
        print "\e[J"   # Clear from cursor to end of screen

        # Print formatted table
        puts '=' * 80
        puts format('%-30s | %15s | %15s', 'Metric', 'Rupees (₹)', 'Percentage (%)')
        puts '-' * 80
        puts format('%-30s | %15s | %15s', 'Total Trades', stats[:total_trades].to_s, '-')
        puts format('%-30s | %15s | %15s', 'Active Positions', stats[:active_positions].to_s, '-')
        puts format('%-30s | %15.2f | %15.2f', 'Total PnL', stats[:total_pnl_rupees], stats[:total_pnl_pct])
        puts format('%-30s | %15.2f | %15.2f', 'Realized PnL', stats[:realized_pnl_rupees], stats[:realized_pnl_pct])
        puts format('%-30s | %15.2f | %15.2f', 'Unrealized PnL', stats[:unrealized_pnl_rupees], stats[:unrealized_pnl_pct])
        puts format('%-30s | %15s | %15.2f', 'Win Rate', '-', stats[:win_rate])
        puts format('%-30s | %15s | %15.2f', 'Avg Realized PnL %', '-', stats[:avg_realized_pnl_pct])
        puts format('%-30s | %15s | %15.2f', 'Avg Unrealized PnL %', '-', stats[:avg_unrealized_pnl_pct])
        puts format('%-30s | %15s | %15s', 'Winners', stats[:winners].to_s, '-')
        puts format('%-30s | %15s | %15s', 'Losers', stats[:losers].to_s, '-')
        puts '=' * 80
        puts format('Last Updated: %s', Time.current.strftime('%Y-%m-%d %H:%M:%S'))
        puts 'Press Ctrl+C to stop'

        $stdout.flush

        sleep 2 # Update every 2 seconds
      end
    rescue Interrupt
      puts "\n\n✅ Stopped"
    end
  end
end

