# frozen_string_literal: true

# Paper Trading Console Helpers
#
# These methods are automatically available in Rails console when PAPER_MODE=true
#
# Usage examples:
#   paper_wallet              # Show wallet balance
#   paper_positions           # List all active positions
#   paper_status              # Show complete status (wallet + positions)
#   paper_position('50058')   # Show specific position details
#
module PaperTradingHelpers
  # Show paper wallet status
  def paper_wallet
    return puts '❌ Paper mode not enabled' unless ExecutionMode.paper?

    snapshot = Orders.config.wallet_snapshot
    puts "\n" + ('=' * 60)
    puts '  PAPER WALLET'
    puts '=' * 60
    puts "  Cash:      ₹#{snapshot[:cash].to_f.round(2)}"
    puts "  MTM (PnL): ₹#{snapshot[:mtm].to_f.round(2)}"
    puts "  Equity:    ₹#{snapshot[:equity].to_f.round(2)}"
    puts "  Exposure:  ₹#{snapshot[:exposure].to_f.round(2)}"
    puts '=' * 60
    snapshot
  end

  # Show all active paper positions
  def paper_positions
    return puts '❌ Paper mode not enabled' unless ExecutionMode.paper?

    trackers = PositionTracker.active.where("meta ->> 'paper' = 'true'")

    puts "\n" + ('=' * 100)
    puts "  ACTIVE POSITIONS (#{trackers.count})"
    puts '=' * 100

    return [] if trackers.empty?

    trackers.map do |tracker|
      segment = tracker.segment || tracker.instrument&.exchange_segment || 'NSE_FNO'
      pos = Orders.config.position(segment: segment, security_id: tracker.security_id)

      if pos
        security_id = pos[:security_id] || tracker.security_id
        segment = pos[:segment] || segment
        {
          symbol: tracker.symbol || tracker.security_id,
          security_id: security_id,
          segment: segment,
          qty: pos[:qty],
          avg_price: pos[:avg_price].to_f,
          current_ltp: pos[:last_ltp].to_f,
          upnl: pos[:upnl].to_f,
          rpnl: pos[:rpnl].to_f,
          side: tracker.side,
          order_no: tracker.order_no
        }.tap do |p|
          puts "\n  📊 #{p[:symbol]}"
          puts "     Security ID: #{p[:security_id]} (#{p[:segment]})"
          puts "     Qty: #{p[:qty]} @ ₹#{p[:avg_price].round(2)} | LTP: ₹#{p[:current_ltp].round(2)}"
          puts "     UPNL: ₹#{p[:upnl].round(2)} | RPNL: ₹#{p[:rpnl].round(2)}"
        end
      else
        { symbol: tracker.symbol || tracker.security_id, error: 'Position not found in Redis' }
      end
    end
  end

  # Show paper trading summary
  def paper_status
    return puts '❌ Paper mode not enabled' unless ExecutionMode.paper?

    paper_wallet
    paper_positions

    trackers = PositionTracker.active.where("meta ->> 'paper' = 'true'")
    puts "\n" + ('=' * 60)
    puts '  SUMMARY'
    puts '=' * 60
    puts "  Active Positions: #{trackers.count}"

    snapshot = Orders.config.wallet_snapshot
    puts "  Total P&L:        ₹#{snapshot[:mtm].to_f.round(2)}"
    puts '=' * 60
  end

  # Get position details for a specific security
  def paper_position(security_id, segment: 'NSE_FNO')
    return puts '❌ Paper mode not enabled' unless ExecutionMode.paper?

    pos = Orders.config.position(segment: segment, security_id: security_id.to_s)

    if pos
      display_seg = pos[:segment] || segment
      display_sid = pos[:security_id] || security_id
      puts "\n" + ('=' * 60)
      puts "  POSITION: #{display_sid} (#{display_seg})"
      puts '=' * 60
      puts "  Security ID:  #{display_sid}"
      puts "  Segment:      #{display_seg}"
      puts "  Quantity:     #{pos[:qty]}"
      puts "  Avg Price:    ₹#{pos[:avg_price].to_f.round(2)}"
      puts "  Current LTP:  ₹#{pos[:last_ltp].to_f.round(2)}"
      puts "  Unrealized:   ₹#{pos[:upnl].to_f.round(2)}"
      puts "  Realized:     ₹#{pos[:rpnl].to_f.round(2)}"
      puts '=' * 60
      pos
    else
      puts "❌ No position found for #{segment}:#{security_id}"
      nil
    end
  end
end

# Helpers are included via initializer in Rails console context
