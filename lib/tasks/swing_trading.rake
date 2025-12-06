# frozen_string_literal: true

namespace :swing_trading do
  desc 'Start swing trading scheduler'
  task start_scheduler: :environment do
    puts '[Swing Trading] Starting scheduler...'

    scheduler = SwingTrading::Scheduler.instance
    scheduler.start

    puts '[Swing Trading] Scheduler started. Press Ctrl+C to stop.'

    # Keep the process alive
    begin
      loop do
        sleep 60
        unless scheduler.running?
          puts '[Swing Trading] Scheduler stopped unexpectedly'
          break
        end
      end
    rescue Interrupt
      puts "\n[Swing Trading] Stopping scheduler..."
      scheduler.stop
      puts '[Swing Trading] Scheduler stopped'
    end
  end

  desc 'Analyze all watchlist items'
  task analyze_watchlist: :environment do
    puts '[Swing Trading] Analyzing watchlist items...'

    watchlist_items = WatchlistItem.active
                                    .where(kind: [:equity, :index_value])
                                    .includes(:watchable)

    if watchlist_items.empty?
      puts '[Swing Trading] No active watchlist items found'
      next
    end

    puts "[Swing Trading] Found #{watchlist_items.size} watchlist items"

    watchlist_items.each do |item|
      puts "\n[Swing Trading] Analyzing #{item.symbol_name}..."

      # Analyze for swing trading
      analyzer_swing = SwingTrading::Analyzer.new(
        watchlist_item: item,
        recommendation_type: 'swing'
      )
      result_swing = analyzer_swing.call

      if result_swing[:success]
        recommendation = SwingTradingRecommendation.create!(result_swing[:data])
        puts "  ✓ Swing recommendation created: #{recommendation.direction.upcase} @ ₹#{recommendation.entry_price} " \
             "(Confidence: #{(recommendation.confidence_score * 100).round(1)}%)"
      else
        puts "  ✗ Swing analysis failed: #{result_swing[:error]}"
      end

      # Analyze for long-term trading
      analyzer_long = SwingTrading::Analyzer.new(
        watchlist_item: item,
        recommendation_type: 'long_term'
      )
      result_long = analyzer_long.call

      if result_long[:success]
        recommendation = SwingTradingRecommendation.create!(result_long[:data])
        puts "  ✓ Long-term recommendation created: #{recommendation.direction.upcase} @ ₹#{recommendation.entry_price} " \
             "(Confidence: #{(recommendation.confidence_score * 100).round(1)}%)"
      else
        puts "  ✗ Long-term analysis failed: #{result_long[:error]}"
      end
    rescue StandardError => e
      puts "  ✗ Error analyzing #{item.symbol_name}: #{e.class} - #{e.message}"
    end

    puts "\n[Swing Trading] Analysis complete"
  end

  desc 'List active recommendations'
  task list_recommendations: :environment do
    recommendations = SwingTradingRecommendation.active
                                                  .includes(:watchlist_item)
                                                  .order(analysis_timestamp: :desc)

    if recommendations.empty?
      puts '[Swing Trading] No active recommendations found'
      next
    end

    puts "\n[Swing Trading] Active Recommendations (#{recommendations.size}):\n\n"

    recommendations.each do |rec|
      puts "ID: #{rec.id}"
      puts "Symbol: #{rec.symbol_name}"
      puts "Type: #{rec.recommendation_type.humanize}"
      puts "Direction: #{rec.direction.upcase}"
      puts "Entry: ₹#{rec.entry_price} | SL: ₹#{rec.stop_loss} | TP: ₹#{rec.take_profit}"
      puts "Quantity: #{rec.quantity} | Allocation: #{rec.allocation_pct}% | Investment: ₹#{rec.investment_amount}"
      puts "Hold Duration: #{rec.hold_duration_days} days"
      puts "Confidence: #{(rec.confidence_score * 100).round(1)}% | Risk-Reward: #{rec.risk_reward_ratio}"
      puts "Analysis Time: #{rec.analysis_timestamp.strftime('%Y-%m-%d %H:%M:%S')}"
      puts "Expires: #{rec.expires_at&.strftime('%Y-%m-%d %H:%M:%S')}"
      puts '-' * 80
    end
  end

  desc 'Expire old recommendations'
  task expire_recommendations: :environment do
    expired_count = SwingTradingRecommendation.active
                                               .where('expires_at < ?', Time.current)
                                               .update_all(status: :expired)

    puts "[Swing Trading] Expired #{expired_count} recommendations"
  end
end
