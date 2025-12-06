# frozen_string_literal: true

require 'singleton'

module SwingTrading
  class Scheduler < TradingSystem::BaseService
    include Singleton

    # Run every 15 minutes for swing trading analysis
    INTERVAL = 900 # 15 minutes in seconds

    def initialize
      super
      @thread = nil
      @running = false
      @last_analysis_time = {}
    end

    def start
      return if @running

      Rails.logger.info('[SwingTrading::Scheduler] Starting swing trading scheduler')
      @running = true
      @thread = Thread.new { run_loop }
      @thread.name = 'swing-trading-scheduler'
    end

    def stop
      Rails.logger.info('[SwingTrading::Scheduler] Stopping swing trading scheduler')
      @running = false
      @thread&.kill
      @thread = nil
    end

    def running?
      @running && @thread&.alive?
    end

    private

    def run_loop
      loop do
        break unless @running

        begin
          # Check if market is open (swing trading can analyze even after market hours)
          # But we prefer to analyze during or just after market hours
          perform_analysis_cycle
        rescue StandardError => e
          Rails.logger.error("[SwingTrading::Scheduler] Error in run loop: #{e.class} - #{e.message}")
          Rails.logger.error("[SwingTrading::Scheduler] Backtrace: #{e.backtrace.first(5).join(', ')}")
        end

        sleep INTERVAL
      end
    end

    def perform_analysis_cycle
      # Get active watchlist items (equity stocks)
      watchlist_items = WatchlistItem.active
                                      .where(kind: [:equity, :index_value])
                                      .includes(:watchable)

      return if watchlist_items.empty?

      Rails.logger.info("[SwingTrading::Scheduler] Analyzing #{watchlist_items.size} watchlist items")

      watchlist_items.each do |item|
        # Skip if analyzed recently (within last hour)
        next if analyzed_recently?(item, 1.hour)

        # Analyze for both swing and long-term if configured
        analyze_item(item, 'swing')
        analyze_item(item, 'long_term')
      rescue StandardError => e
        Rails.logger.error("[SwingTrading::Scheduler] Error analyzing #{item.symbol_name}: #{e.class} - #{e.message}")
      end
    end

    def analyze_item(watchlist_item, recommendation_type)
      analyzer = SwingTrading::Analyzer.new(
        watchlist_item: watchlist_item,
        recommendation_type: recommendation_type
      )

      result = analyzer.call

      if result[:success]
        recommendation_data = result[:data]
        recommendation = create_recommendation(watchlist_item, recommendation_data)

        if recommendation
          # Send notification for new recommendations
          send_notification(recommendation)
          mark_analyzed(watchlist_item)

          Rails.logger.info(
            "[SwingTrading::Scheduler] Generated #{recommendation_type} recommendation for " \
            "#{watchlist_item.symbol_name}: #{recommendation_data[:direction].upcase} @ " \
            "₹#{recommendation_data[:entry_price]} (Confidence: #{(recommendation_data[:confidence_score] * 100).round(1)}%)"
          )
        end
      else
        Rails.logger.debug(
          "[SwingTrading::Scheduler] No recommendation for #{watchlist_item.symbol_name} " \
          "(#{recommendation_type}): #{result[:error]}"
        )
      end
    end

    def create_recommendation(watchlist_item, recommendation_data)
      # Check if similar active recommendation already exists
      existing = SwingTradingRecommendation.active
                                            .where(watchlist_item_id: watchlist_item.id)
                                            .where(recommendation_type: recommendation_data[:recommendation_type])
                                            .where(direction: recommendation_data[:direction])
                                            .where('analysis_timestamp > ?', 24.hours.ago)
                                            .first

      if existing
        # Update existing recommendation if confidence is higher
        if recommendation_data[:confidence_score] > (existing.confidence_score || 0)
          existing.update!(
            entry_price: recommendation_data[:entry_price],
            stop_loss: recommendation_data[:stop_loss],
            take_profit: recommendation_data[:take_profit],
            quantity: recommendation_data[:quantity],
            allocation_pct: recommendation_data[:allocation_pct],
            hold_duration_days: recommendation_data[:hold_duration_days],
            confidence_score: recommendation_data[:confidence_score],
            technical_analysis: recommendation_data[:technical_analysis],
            volume_analysis: recommendation_data[:volume_analysis],
            reasoning: recommendation_data[:reasoning],
            analysis_timestamp: recommendation_data[:analysis_timestamp],
            expires_at: recommendation_data[:expires_at]
          )
          Rails.logger.info(
            "[SwingTrading::Scheduler] Updated recommendation for #{watchlist_item.symbol_name} " \
            "(confidence improved to #{(recommendation_data[:confidence_score] * 100).round(1)}%)"
          )
          existing
        else
          nil # Don't update if confidence is lower
        end
      else
        # Create new recommendation
        SwingTradingRecommendation.create!(recommendation_data)
      end
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error(
        "[SwingTrading::Scheduler] Failed to create recommendation for #{watchlist_item.symbol_name}: " \
        "#{e.record.errors.full_messages.join(', ')}"
      )
      nil
    end

    def send_notification(recommendation)
      return unless recommendation

      notification_service = SwingTrading::NotificationService.new(
        recommendation: recommendation,
        channels: [:api] # Add :websocket, :email as needed
      )

      notification_service.call
    rescue StandardError => e
      Rails.logger.error("[SwingTrading::Scheduler] Notification failed: #{e.message}")
    end

    def analyzed_recently?(watchlist_item, time_window)
      last_time = @last_analysis_time[watchlist_item.id]
      return false unless last_time

      Time.current - last_time < time_window
    end

    # Mark item as analyzed
    def mark_analyzed(watchlist_item)
      @last_analysis_time[watchlist_item.id] = Time.current
    end
  end
end
