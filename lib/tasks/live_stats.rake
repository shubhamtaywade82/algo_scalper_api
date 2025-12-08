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
          # Use carriage return + clear entire line
          # \r = move to start of line, \e[2K = clear entire line (more reliable)
          print "\r\e[2K#{output}"
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
    require 'io/console'

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
          # Try multiple escape code formats for maximum compatibility
          # Method 1: \r + \e[2K (clear entire line)
          print "\r\e[2K"
          # Method 2: Also try \033[2K (alternative format)
          print "\033[2K"
          # Now print the hash
          print hash_output
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

    # Ensure stdout is not buffered
    $stdout.sync = true
    $stderr.sync = true

    # Check if we're in a TTY (interactive terminal)
    is_tty = $stdout.tty?

    # Print header once (only if TTY)
    if is_tty
      puts '📊 Live Paper Trading Statistics'
      puts 'Press Ctrl+C to stop'
      puts '=' * 80
    end

    # Number of lines in the table (header + separator + 11 data rows + separator + timestamp + instruction)
    table_lines = 16

    begin
      loop do
        stats = PositionTracker.paper_trading_stats_with_pct

        if is_tty
          # Move cursor up to clear previous table output
          print "\e[#{table_lines}A" # Move up N lines
          print "\e[J"                # Clear from cursor to end of screen
        end

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

