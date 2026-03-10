# frozen_string_literal: true

namespace :position do
  desc 'Fix incorrect last_pnl_rupees/last_pnl_pct for paper exited positions (e.g. NIFTY24MAR22000CE BUY 50 100→120)'
  task fix_pnl: :environment do
    require_relative '../../app/services/concerns/broker_fee_calculator'

    symbol = ENV.fetch('SYMBOL', 'NIFTY24MAR22000CE')
    entry = BigDecimal(ENV.fetch('ENTRY', '100'))
    exit_px = BigDecimal(ENV.fetch('EXIT', '120'))
    qty = (ENV.fetch('QTY', '50')).to_i

    scope = PositionTracker.paper.exited.where(
      symbol: symbol,
      side: 'BUY',
      quantity: qty,
      entry_price: entry,
      exit_price: exit_px
    )

    records = scope.to_a
    if records.empty?
      puts "No paper exited position(s) found for #{symbol} BUY #{qty} @ #{entry} → #{exit_px}. Nothing to fix."
      puts "Tip: Run SYMBOL=NIFTY24MAR22000CE bundle exec rake position:recalc_pnl to fix by symbol."
    else
      gross = (exit_px - entry) * qty
      net = BrokerFeeCalculator.net_pnl(gross, is_exited: true)
      notional = entry * qty
      pct = notional.positive? ? (net / notional) : BigDecimal(0)

      puts "Found #{records.size} record(s). Correct PnL: gross=#{gross}, net=#{net}, pct=#{(pct * 100).round(2)}%"

      records.each do |t|
        prev_rupees = t.last_pnl_rupees&.to_f
        prev_pct = t.last_pnl_pct&.to_f
        t.update!(last_pnl_rupees: net, last_pnl_pct: pct, high_water_mark_pnl: [t.high_water_mark_pnl.to_f, net.to_f].max)
        puts "  id=#{t.id} order_no=#{t.order_no}: last_pnl_rupees #{prev_rupees} → #{net.to_f}, last_pnl_pct #{prev_pct} → #{pct.to_f}"
      end

      puts "Done. Refreshing paper_positions_details will show correct PnL."
    end
  end

  desc "Recalc PnL for paper exited by symbol (SYMBOL= substring; omit for all paper exited)"
  task recalc_pnl: :environment do
    require_relative '../../app/services/concerns/broker_fee_calculator'

    symbol_pattern = ENV['SYMBOL']
    scope = PositionTracker.paper.exited.where.not(exit_price: nil).where.not(entry_price: nil)
    scope = scope.where('position_trackers.symbol LIKE ?', "%#{symbol_pattern}%") if symbol_pattern.present?

    records = scope.to_a.select { |r| r.quantity.to_i.positive? }
    if records.empty?
      puts "No paper exited positions found (SYMBOL=#{symbol_pattern.inspect})."
    else
      puts "Recalculating PnL for #{records.size} record(s) from entry/exit/quantity..."
      records.each do |t|
        entry_bd = BigDecimal((t.entry_price || 0).to_s)
        exit_bd = BigDecimal((t.exit_price || 0).to_s)
        qty_i = t.quantity.to_i
        next if entry_bd.zero? || qty_i <= 0

        gross = (t.side.to_s.upcase == 'BUY' ? (exit_bd - entry_bd) : (entry_bd - exit_bd)) * qty_i
        net = BrokerFeeCalculator.net_pnl(gross, is_exited: true)
        notional = entry_bd * qty_i
        pct = notional.positive? ? (net / notional) : BigDecimal(0)

        prev_rupees = t.last_pnl_rupees&.to_f
        t.update!(last_pnl_rupees: net, last_pnl_pct: pct, high_water_mark_pnl: [t.high_water_mark_pnl.to_f, net.to_f].max)
        puts "  id=#{t.id} #{t.symbol} #{t.side} #{t.quantity} #{entry_bd}→#{exit_bd}: #{prev_rupees} → #{net.to_f} (#{(pct * 100).round(2)}%)"
      end
      puts "Done."
    end
  end

  desc "Fix quantity and PnL for paper exited (SYMBOL, ENTRY, EXIT, QTY=50); finds by symbol+entry+exit, sets quantity, recalc PnL"
  task fix_qty_and_pnl: :environment do
    require_relative '../../app/services/concerns/broker_fee_calculator'

    symbol = ENV.fetch('SYMBOL', 'NIFTY24MAR22000CE')
    entry = BigDecimal(ENV.fetch('ENTRY', '100'))
    exit_px = BigDecimal(ENV.fetch('EXIT', '120'))
    correct_qty = (ENV.fetch('QTY', '50')).to_i

    scope = PositionTracker.paper.exited.where(
      symbol: symbol,
      side: 'BUY',
      entry_price: entry,
      exit_price: exit_px
    )

    records = scope.to_a
    if records.empty?
      puts "No paper exited position(s) found for #{symbol} BUY @ #{entry} → #{exit_px}. Nothing to fix."
    else
      gross = (exit_px - entry) * correct_qty
      net = BrokerFeeCalculator.net_pnl(gross, is_exited: true)
      notional = entry * correct_qty
      pct = notional.positive? ? (net / notional) : BigDecimal(0)

      puts "Found #{records.size} record(s). Setting quantity=#{correct_qty}, PnL: net=#{net}, pct=#{(pct * 100).round(2)}%"

      records.each do |t|
        prev_qty = t.quantity.to_i
        prev_rupees = t.last_pnl_rupees&.to_f
        t.update!(
          quantity: correct_qty,
          last_pnl_rupees: net,
          last_pnl_pct: pct,
          high_water_mark_pnl: [t.high_water_mark_pnl.to_f, net.to_f].max
        )
        puts "  id=#{t.id} order_no=#{t.order_no}: quantity #{prev_qty} → #{correct_qty}, last_pnl_rupees #{prev_rupees} → #{net.to_f}"
      end

      puts "Done."
    end
  end

  desc "Fix PnL for specific position tracker IDs (IDS=3535,3536); recalc from entry/exit/quantity"
  task fix_by_ids: :environment do
    require_relative '../../app/services/concerns/broker_fee_calculator'

    ids = (ENV['IDS'] || '').split(',').map(&:strip).reject(&:empty?).map(&:to_i)
    if ids.empty?
      puts "Usage: IDS=3535,3536 bundle exec rake position:fix_by_ids"
      next
    end

    records = PositionTracker.where(id: ids).to_a
    records.each do |t|
      unless t.exited? && t.entry_price.present? && t.exit_price.present? && t.quantity.to_i.positive?
        puts "  id=#{t.id} skipped (not exited or missing entry/exit/quantity)"
        next
      end

      entry_bd = BigDecimal((t.entry_price || 0).to_s)
      exit_bd = BigDecimal((t.exit_price || 0).to_s)
      qty_i = t.quantity.to_i

      gross = (t.side.to_s.upcase == 'BUY' ? (exit_bd - entry_bd) : (entry_bd - exit_bd)) * qty_i
      net = BrokerFeeCalculator.net_pnl(gross, is_exited: true)
      notional = entry_bd * qty_i
      pct = notional.positive? ? (net / notional) : BigDecimal(0)

      prev_rupees = t.last_pnl_rupees&.to_f
      prev_pct = t.last_pnl_pct&.to_f
      t.update!(
        last_pnl_rupees: net,
        last_pnl_pct: pct,
        high_water_mark_pnl: [t.high_water_mark_pnl.to_f, net.to_f].max
      )
      puts "  id=#{t.id} #{t.order_no}: last_pnl_rupees #{prev_rupees.inspect} → #{net.to_f}, last_pnl_pct #{prev_pct.inspect} → #{(pct * 100).round(2)}%"
    end
    puts "Done."
  end

  desc 'Sync positions between DhanHQ and PositionTracker database'
  task sync: :environment do
    puts 'Starting position synchronization...'

    begin
      Live::PositionSyncService.instance.force_sync!
      puts 'Position synchronization completed successfully!'
    rescue StandardError => e
      puts "Position synchronization failed: #{e.class} - #{e.message}"
      exit 1
    end
  end

  desc 'Show position sync status'
  task status: :environment do
    puts 'Position Sync Status:'
    puts '===================='

    begin
      # Count DhanHQ positions
      dhan_positions = DhanHQ::Models::Position.active
      puts "DhanHQ Active Positions: #{dhan_positions.size}"

      # Count tracked positions
      tracked_positions = PositionTracker.active
      puts "Tracked Positions: #{tracked_positions.size}"

      # Show untracked positions
      tracked_security_ids = tracked_positions.pluck(:security_id).map(&:to_s)
      untracked = dhan_positions.reject do |pos|
        security_id = pos.security_id
        tracked_security_ids.include?(security_id.to_s)
      end

      puts "Untracked Positions: #{untracked.size}"

      if untracked.any?
        puts "\nUntracked Position Details:"
        untracked.each do |pos|
          security_id = pos.security_id
          symbol = pos.trading_symbol
          puts "  - #{security_id}: #{symbol}"
        end
      end
    rescue StandardError => e
      puts "Failed to get position status: #{e.class} - #{e.message}"
      exit 1
    end
  end
end
