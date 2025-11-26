# frozen_string_literal: true

namespace :trading do
  desc 'Analyze all PositionTracker records for exit strategy optimization'
  task analyze_positions: :environment do
    require 'bigdecimal'

    puts '=' * 100
    puts 'POSITION TRACKER ANALYSIS - EXIT STRATEGY OPTIMIZATION'
    puts '=' * 100
    puts

    # Get all exited positions
    exited = PositionTracker.exited_paper.order(created_at: :desc)
    active = PositionTracker.paper.active

    puts "📊 SUMMARY"
    puts '-' * 100
    puts "Total Exited Positions: #{exited.count}"
    puts "Active Positions: #{active.count}"
    puts

    # Analyze exited positions
    analyze_exited_positions(exited)
    puts

    # Analyze active positions
    analyze_active_positions(active) if active.any?
    puts

    # Identify problematic patterns
    identify_problematic_patterns(exited)
    puts

    # Generate recommendations
    generate_recommendations(exited)
  end

  private

  def analyze_exited_positions(exited)
    puts '=' * 100
    puts 'EXITED POSITIONS ANALYSIS'
    puts '=' * 100
    puts

    total = exited.count
    winners = exited.select { |t| t.last_pnl_rupees.to_f.positive? }
    losers = exited.select { |t| t.last_pnl_rupees.to_f.negative? }
    breakeven = exited.select { |t| t.last_pnl_rupees.to_f.zero? }

    puts "Winners: #{winners.count} (#{(winners.count.to_f / total * 100).round(2)}%)"
    puts "Losers: #{losers.count} (#{(losers.count.to_f / total * 100).round(2)}%)"
    puts "Breakeven: #{breakeven.count} (#{(breakeven.count.to_f / total * 100).round(2)}%)"
    puts

    # Positions with high HWM but closed in loss
    high_hwm_losses = exited.select do |t|
      hwm = t.high_water_mark_pnl.to_f
      final_pnl = t.last_pnl_rupees.to_f
      hwm.positive? && final_pnl.negative?
    end

    puts "⚠️  CRITICAL: Positions with High HWM but Closed in Loss: #{high_hwm_losses.count}"
    puts

    if high_hwm_losses.any?
      puts "Top 20 Worst Cases (HWM Profit → Final Loss):"
      puts '-' * 100
      puts format('%-8s | %-12s | %-10s | %-10s | %-12s | %-12s | %-15s | %-20s',
                  'ID', 'Order No', 'Entry Time', 'Exit Time', 'HWM (₹)', 'Final PnL (₹)', 'Drop from Peak', 'Exit Reason')
      puts '-' * 100

      sorted = high_hwm_losses.sort_by { |t| t.high_water_mark_pnl.to_f }.reverse.first(20)
      sorted.each do |tracker|
        hwm = tracker.high_water_mark_pnl.to_f
        final = tracker.last_pnl_rupees.to_f
        drop = hwm.positive? ? ((hwm - final) / hwm * 100.0) : 0.0
        entry_time = tracker.created_at.strftime('%H:%M:%S')
        exit_time = tracker.updated_at.strftime('%H:%M:%S')
        exit_reason = (tracker.meta.is_a?(Hash) ? tracker.meta['exit_reason'] : nil) || 'unknown'
        duration = ((tracker.updated_at - tracker.created_at) / 60.0).round(1)

        puts format('%-8d | %-12s | %-10s | %-10s | %-12.2f | %-12.2f | %-15.2f%% | %-20s',
                    tracker.id, tracker.order_no, entry_time, exit_time, hwm, final, drop, exit_reason)
      end
      puts
    end

    # Calculate drop from peak statistics
    calculate_drop_statistics(exited)
    puts

    # Analyze by exit reason
    analyze_by_exit_reason(exited)
    puts

    # Analyze by timing
    analyze_by_timing(exited)
  end

  def calculate_drop_statistics(exited)
    puts '=' * 100
    puts 'DROP FROM PEAK (HWM) STATISTICS'
    puts '=' * 100
    puts

    positions_with_hwm = exited.select { |t| t.high_water_mark_pnl.to_f.positive? }
    return unless positions_with_hwm.any?

    drops = positions_with_hwm.map do |tracker|
      hwm = tracker.high_water_mark_pnl.to_f
      final = tracker.last_pnl_rupees.to_f
      next nil if hwm.zero? || hwm.negative?

      drop_rupees = hwm - final
      drop_pct = hwm.positive? ? (drop_rupees / hwm * 100.0) : 0.0
      { tracker: tracker, drop_rupees: drop_rupees, drop_pct: drop_pct, hwm: hwm, final: final }
    end.compact

    return if drops.empty?

    avg_drop_pct = drops.sum { |d| d[:drop_pct] } / drops.count
    max_drop_pct = drops.max_by { |d| d[:drop_pct] }[:drop_pct]
    min_drop_pct = drops.min_by { |d| d[:drop_pct] }[:drop_pct]

    # Positions that dropped more than 5% from peak
    high_drops = drops.select { |d| d[:drop_pct] > 5.0 }
    # Positions that dropped more than 10% from peak
    very_high_drops = drops.select { |d| d[:drop_pct] > 10.0 }
    # Positions that dropped more than 20% from peak
    extreme_drops = drops.select { |d| d[:drop_pct] > 20.0 }

    puts "Positions with HWM: #{positions_with_hwm.count}"
    puts "Average Drop from Peak: #{avg_drop_pct.round(2)}%"
    puts "Max Drop from Peak: #{max_drop_pct.round(2)}%"
    puts "Min Drop from Peak: #{min_drop_pct.round(2)}%"
    puts
    puts "⚠️  Drops > 5%: #{high_drops.count} (#{(high_drops.count.to_f / drops.count * 100).round(2)}%)"
    puts "⚠️  Drops > 10%: #{very_high_drops.count} (#{(very_high_drops.count.to_f / drops.count * 100).round(2)}%)"
    puts "⚠️  Drops > 20%: #{extreme_drops.count} (#{(extreme_drops.count.to_f / drops.count * 100).round(2)}%)"
    puts

    if extreme_drops.any?
      puts "Top 10 Extreme Drops (>20% from peak):"
      puts '-' * 100
      sorted = extreme_drops.sort_by { |d| d[:drop_pct] }.reverse.first(10)
      sorted.each do |d|
        t = d[:tracker]
        puts format('ID: %d | HWM: ₹%.2f → Final: ₹%.2f | Drop: %.2f%% | Reason: %s',
                    t.id, d[:hwm], d[:final], d[:drop_pct], (t.meta.is_a?(Hash) ? t.meta['exit_reason'] : nil) || 'unknown')
      end
      puts
    end
  end

  def analyze_by_exit_reason(exited)
    puts '=' * 100
    puts 'ANALYSIS BY EXIT REASON'
    puts '=' * 100
    puts

    reasons = exited.group_by { |t| (t.meta.is_a?(Hash) ? t.meta['exit_reason'] : nil) || 'unknown' }
    reasons.each do |reason, trackers|
      winners = trackers.select { |t| t.last_pnl_rupees.to_f.positive? }
      losers = trackers.select { |t| t.last_pnl_rupees.to_f.negative? }
      avg_pnl = trackers.sum { |t| t.last_pnl_rupees.to_f } / trackers.count
      avg_hwm = trackers.select { |t| t.high_water_mark_pnl.to_f.positive? }
                        .sum { |t| t.high_water_mark_pnl.to_f } / [trackers.count, 1].max

      puts "#{reason}:"
      puts "  Count: #{trackers.count}"
      puts "  Winners: #{winners.count} | Losers: #{losers.count}"
      puts "  Avg PnL: ₹#{avg_pnl.round(2)}"
      puts "  Avg HWM: ₹#{avg_hwm.round(2)}"
      puts
    end
  end

  def analyze_by_timing(exited)
    puts '=' * 100
    puts 'ANALYSIS BY TIMING'
    puts '=' * 100
    puts

    # Group by hour of entry
    by_entry_hour = exited.group_by { |t| t.created_at.hour }
    puts "Positions by Entry Hour:"
    by_entry_hour.sort.each do |hour, trackers|
      winners = trackers.select { |t| t.last_pnl_rupees.to_f.positive? }
      avg_pnl = trackers.sum { |t| t.last_pnl_rupees.to_f } / trackers.count
      puts "  #{hour}:00 - #{hour + 1}:00 | Count: #{trackers.count} | Winners: #{winners.count} | Avg PnL: ₹#{avg_pnl.round(2)}"
    end
    puts

    # Group by hour of exit
    by_exit_hour = exited.group_by { |t| t.updated_at.hour }
    puts "Positions by Exit Hour:"
    by_exit_hour.sort.each do |hour, trackers|
      winners = trackers.select { |t| t.last_pnl_rupees.to_f.positive? }
      avg_pnl = trackers.sum { |t| t.last_pnl_rupees.to_f } / trackers.count
      puts "  #{hour}:00 - #{hour + 1}:00 | Count: #{trackers.count} | Winners: #{winners.count} | Avg PnL: ₹#{avg_pnl.round(2)}"
    end
    puts

    # Duration analysis
    durations = exited.map do |t|
      ((t.updated_at - t.created_at) / 60.0).round(1) # minutes
    end
    avg_duration = durations.sum / durations.count
    puts "Average Position Duration: #{avg_duration.round(1)} minutes"
    puts
  end

  def analyze_active_positions(active)
    puts '=' * 100
    puts 'ACTIVE POSITIONS ANALYSIS'
    puts '=' * 100
    puts

    active.each do |tracker|
      hwm = tracker.current_hwm_pnl.to_f
      current_pnl = tracker.current_pnl_rupees.to_f
      drop = hwm.positive? ? ((hwm - current_pnl) / hwm * 100.0) : 0.0

      puts format('ID: %d | Order: %s | Current PnL: ₹%.2f | HWM: ₹%.2f | Drop: %.2f%%',
                  tracker.id, tracker.order_no, current_pnl, hwm, drop)
    end
    puts
  end

  def identify_problematic_patterns(exited)
    puts '=' * 100
    puts 'PROBLEMATIC PATTERNS IDENTIFIED'
    puts '=' * 100
    puts

    # Pattern 1: High HWM but closed in loss
    high_hwm_losses = exited.select do |t|
      hwm = t.high_water_mark_pnl.to_f
      final_pnl = t.last_pnl_rupees.to_f
      hwm.positive? && final_pnl.negative? && hwm > 500 # HWM > ₹500
    end

    if high_hwm_losses.any?
      puts "1. ⚠️  HIGH HWM → LOSS PATTERN: #{high_hwm_losses.count} positions"
      puts "   These positions had significant profit (HWM > ₹500) but closed in loss."
      puts "   Average HWM: ₹#{high_hwm_losses.sum { |t| t.high_water_mark_pnl.to_f } / high_hwm_losses.count.round(2)}"
      puts "   Average Final Loss: ₹#{high_hwm_losses.sum { |t| t.last_pnl_rupees.to_f } / high_hwm_losses.count.round(2)}"
      puts
    end

    # Pattern 2: Large drops from peak (>10%)
    large_drops = exited.select do |t|
      hwm = t.high_water_mark_pnl.to_f
      final = t.last_pnl_rupees.to_f
      next false if hwm.zero?

      drop_pct = ((hwm - final) / hwm * 100.0)
      drop_pct > 10.0
    end

    if large_drops.any?
      puts "2. ⚠️  LARGE DROP FROM PEAK (>10%): #{large_drops.count} positions"
      puts "   These positions dropped more than 10% from their peak before exit."
      puts
    end

    # Pattern 3: Positions that hit HWM early but gave back all gains
    early_hwm_losses = exited.select do |t|
      hwm = t.high_water_mark_pnl.to_f
      final = t.last_pnl_rupees.to_f
      duration = (t.updated_at - t.created_at) / 60.0 # minutes

      hwm.positive? && final.negative? && duration > 30 # More than 30 minutes
    end

    if early_hwm_losses.any?
      puts "3. ⚠️  EARLY HWM → LOSS PATTERN: #{early_hwm_losses.count} positions"
      puts "   These positions hit HWM early but gave back all gains over time."
      puts
    end
  end

  def generate_recommendations(exited)
    puts '=' * 100
    puts 'OPTIMIZATION RECOMMENDATIONS'
    puts '=' * 100
    puts

    high_hwm_losses = exited.select do |t|
      hwm = t.high_water_mark_pnl.to_f
      final_pnl = t.last_pnl_rupees.to_f
      hwm.positive? && final_pnl.negative?
    end

    large_drops = exited.select do |t|
      hwm = t.high_water_mark_pnl.to_f
      final = t.last_pnl_rupees.to_f
      next false if hwm.zero?

      drop_pct = ((hwm - final) / hwm * 100.0)
      drop_pct > 10.0
    end

    puts "Based on analysis of #{exited.count} exited positions:"
    puts

    if high_hwm_losses.any? || large_drops.any?
      puts "🔴 CRITICAL ISSUES FOUND:"
      puts

      if high_hwm_losses.any?
        avg_drop = high_hwm_losses.map do |t|
          hwm = t.high_water_mark_pnl.to_f
          final = t.last_pnl_rupees.to_f
          hwm.positive? ? ((hwm - final) / hwm * 100.0) : 0.0
        end.sum / high_hwm_losses.count

        puts "1. Peak Drawdown Protection Too Weak"
        puts "   - #{high_hwm_losses.count} positions had high HWM but closed in loss"
        puts "   - Average drop from peak: #{avg_drop.round(2)}%"
        puts "   - Current peak_drawdown_exit_pct: 5%"
        puts
        puts "   💡 RECOMMENDATION:"
        puts "   - Reduce peak_drawdown_exit_pct from 5% to 3% (tighter protection)"
        puts "   - OR enable peak_drawdown_activation with lower thresholds"
        puts "   - Consider dynamic drawdown based on profit level:"
        puts "     * <10% profit: 2% drawdown"
        puts "     * 10-25% profit: 3% drawdown"
        puts "     * >25% profit: 5% drawdown"
        puts
      end

      if large_drops.any?
        puts "2. Trailing Stop Not Aggressive Enough"
        puts "   - #{large_drops.count} positions dropped >10% from peak"
        puts "   - Current trailing tiers may be too lenient"
        puts
        puts "   💡 RECOMMENDATION:"
        puts "   - Tighten trailing tiers for higher profit levels:"
        puts "     * At 25% profit: SL offset should be 5% (not 10%)"
        puts "     * At 40% profit: SL offset should be 10% (not 20%)"
        puts "     * At 60% profit: SL offset should be 15% (not 30%)"
        puts "   - Add more tiers between 15-25% profit range"
        puts
      end

      puts "3. Time-Based Exit Optimization"
      puts "   - Review positions that exited near market close"
      puts "   - Consider earlier exit time (3:15 PM instead of 3:20 PM)"
      puts "   - Add profit protection: if PnL > X% at 3:10 PM, exit immediately"
      puts
    else
      puts "✅ No critical issues found. Current exit strategy appears effective."
      puts
    end

    puts "📋 SUGGESTED CONFIG CHANGES:"
    puts
    puts "risk:"
    puts "  peak_drawdown_exit_pct: 3  # Reduced from 5"
    puts "  peak_drawdown_activation_profit_pct: 10.0  # Reduced from 25.0"
    puts "  peak_drawdown_activation_sl_offset_pct: 5.0  # Reduced from 10.0"
    puts
    puts "  trailing_tiers:"
    puts "    - { trigger_pct: 5, sl_offset_pct: -15 }"
    puts "    - { trigger_pct: 10, sl_offset_pct: -5 }"
    puts "    - { trigger_pct: 15, sl_offset_pct: 0 }"
    puts "    - { trigger_pct: 20, sl_offset_pct: 5 }  # NEW: Tighter at 20%"
    puts "    - { trigger_pct: 25, sl_offset_pct: 5 }  # Changed from 10"
    puts "    - { trigger_pct: 40, sl_offset_pct: 10 }  # Changed from 20"
    puts "    - { trigger_pct: 60, sl_offset_pct: 15 }  # Changed from 30"
    puts "    - { trigger_pct: 80, sl_offset_pct: 25 }  # Changed from 40"
    puts "    - { trigger_pct: 120, sl_offset_pct: 50 }  # Changed from 60"
    puts
  end
end

