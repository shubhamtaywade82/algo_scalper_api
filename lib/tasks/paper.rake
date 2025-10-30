# frozen_string_literal: true

namespace :paper do
  desc 'Show paper trading wallet status'
  task wallet: :environment do
    unless ExecutionMode.paper?
      puts "❌ Paper mode is not enabled. Set PAPER_MODE=true to use paper trading."
      exit 1
    end

    begin
      snapshot = Orders.config.wallet_snapshot

      puts "\n" + "=" * 60
      puts "  PAPER TRADING WALLET"
      puts "=" * 60
      puts "  Cash Available:  ₹#{(snapshot[:cash].to_f).round(2)}"
      puts "  Unrealized P&L:  ₹#{(snapshot[:mtm].to_f).round(2)}"
      puts "  Total Equity:    ₹#{(snapshot[:equity].to_f).round(2)}"
      puts "  Total Exposure:  ₹#{(snapshot[:exposure].to_f).round(2)}"
      puts "=" * 60
      puts "\n"
    rescue StandardError => e
      puts "❌ Failed to fetch wallet: #{e.class} - #{e.message}"
      exit 1
    end
  end

  desc 'Show all active paper positions with P&L'
  task positions: :environment do
    unless ExecutionMode.paper?
      puts "❌ Paper mode is not enabled. Set PAPER_MODE=true to use paper trading."
      exit 1
    end

    begin
      # Get position trackers
      trackers = PositionTracker.active.where("meta ->> 'paper' = 'true'")

      puts "\n#{'=' * 100}"
      puts "  ACTIVE PAPER POSITIONS (#{trackers.count})"
      puts "=" * 100

      if trackers.empty?
        puts "  No active positions."
      else
        total_upnl = 0

        trackers.each do |tracker|
          # Get position from Paper::Gateway
          pos = Orders.config.position(
            segment: tracker.segment || tracker.instrument&.exchange_segment || 'NSE_FNO',
            security_id: tracker.security_id
          )

          if pos
            upnl = pos[:upnl].to_f
            rpnl = pos[:rpnl].to_f
            total_upnl += upnl

            symbol = tracker.symbol || tracker.instrument&.symbol_name || tracker.security_id
            entry_price = pos[:avg_price].to_f
            current_price = pos[:last_ltp].to_f
            qty = pos[:qty]

            pnl_color = upnl >= 0 ? "\033[32m" : "\033[31m"
            reset_color = "\033[0m"

            puts "\n  📊 #{symbol}"
            puts "     Security ID: #{tracker.security_id}"
            puts "     Quantity:    #{qty} @ ₹#{entry_price.round(2)}"
            puts "     Current LTP: ₹#{current_price.round(2)}"
            puts "     Unrealized:  #{pnl_color}₹#{(upnl).round(2)}#{reset_color}"
            puts "     Realized:    ₹#{rpnl.round(2)}"
            puts "     Entry Price: ₹#{entry_price.round(2)}"
            puts "     Side:        #{tracker.side}"
            puts "     Order No:    #{tracker.order_no}"
          else
            puts "\n  ⚠️  #{tracker.symbol || tracker.security_id} - Position data not found in Redis"
          end
        end

        puts "\n#{'-' * 100}"
        total_color = total_upnl >= 0 ? "\033[32m" : "\033[31m"
        puts "  Total Unrealized P&L: #{total_color}₹#{(total_upnl).round(2)}\033[0m"
        puts "=" * 100
      end

      puts "\n"
    rescue StandardError => e
      puts "❌ Failed to fetch positions: #{e.class} - #{e.message}"
      puts e.backtrace.first(5).join("\n")
      exit 1
    end
  end

  desc 'Show complete paper trading status (wallet + positions)'
  task status: :environment do
    unless ExecutionMode.paper?
      puts "❌ Paper mode is not enabled. Set PAPER_MODE=true to use paper trading."
      exit 1
    end

    Rake::Task['paper:wallet'].invoke
    Rake::Task['paper:positions'].invoke
  end

  desc 'Reset paper wallet to initial capital'
  task :reset_wallet, [:seed_amount] => :environment do |_t, args|
    unless ExecutionMode.paper?
      puts "❌ Paper mode is not enabled. Set PAPER_MODE=true to use paper trading."
      exit 1
    end

    seed_amount = args[:seed_amount]&.to_f || ENV.fetch('PAPER_SEED_CASH', '100000').to_f

    begin
      # Clear all positions and reset wallet
      if Orders.config.respond_to?(:reset_wallet!)
        Orders.config.reset_wallet!(seed_amount: seed_amount)
        puts "✅ Paper wallet reset to ₹#{seed_amount}"
      else
        puts "❌ Wallet reset not implemented in gateway"
      end
    rescue StandardError => e
      puts "❌ Failed to reset wallet: #{e.class} - #{e.message}"
      exit 1
    end
  end

  desc 'Sync paper positions from PositionTracker to Redis (useful after server restart)'
  task sync: :environment do
    unless ExecutionMode.paper?
      puts "❌ Paper mode is not enabled. Set PAPER_MODE=true to use paper trading."
      exit 1
    end

    begin
      puts 'Starting paper position sync from PositionTracker...'
      result = Paper::PositionSync.sync!

      puts "\n" + "=" * 60
      puts "  SYNC RESULTS"
      puts "=" * 60
      puts "  Positions synced: #{result[:synced]}"
      puts "  Errors:           #{result[:errors]}"
      puts "=" * 60
      puts "\n"

      if result[:synced] > 0
        puts "✅ Successfully synced #{result[:synced]} position(s) to Redis"
      else
        puts "ℹ️  No positions found to sync"
      end

      puts "✅ Sync complete!\n\n"
    rescue StandardError => e
      puts "❌ Failed to sync positions: #{e.class} - #{e.message}"
      puts e.backtrace.first(5).join("\n")
      exit 1
    end
  end
end

