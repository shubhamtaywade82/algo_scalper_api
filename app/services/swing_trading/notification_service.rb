# frozen_string_literal: true

module SwingTrading
  class NotificationService < ApplicationService
    # Notification channels
    CHANNELS = %i[api websocket email].freeze

    def initialize(recommendation:, channels: [:api])
      @recommendation = recommendation
      @channels = Array(channels).map(&:to_sym) & CHANNELS
    end

    def call
      return error_result('No valid channels specified') if @channels.empty?

      results = {}
      @channels.each do |channel|
        results[channel] = send_notification(channel)
      end

      if results.values.all? { |r| r[:success] }
        success_result(results)
      else
        error_result('Some notifications failed', results)
      end
    rescue StandardError => e
      Rails.logger.error("[SwingTrading::NotificationService] Error: #{e.class} - #{e.message}")
      error_result("Notification failed: #{e.message}")
    end

    private

    def send_notification(channel)
      case channel
      when :api
        # API notifications are handled via the API endpoints
        # This is a placeholder for future webhook/HTTP notification support
        { success: true, message: 'API notification ready' }
      when :websocket
        send_websocket_notification
      when :email
        send_email_notification
      else
        { success: false, error: "Unknown channel: #{channel}" }
      end
    end

    def send_websocket_notification
      # Broadcast recommendation via ActionCable/WebSocket
      # This requires ActionCable to be configured
      if defined?(ActionCable)
        ActionCable.server.broadcast(
          'swing_trading_recommendations',
          format_recommendation_for_broadcast
        )
        { success: true, message: 'WebSocket notification sent' }
      else
        Rails.logger.warn('[SwingTrading::NotificationService] ActionCable not available, skipping WebSocket notification')
        { success: false, error: 'ActionCable not configured' }
      end
    rescue StandardError => e
      Rails.logger.error("[SwingTrading::NotificationService] WebSocket notification failed: #{e.message}")
      { success: false, error: e.message }
    end

    def send_email_notification
      # Email notification via ActionMailer
      # This requires mailer configuration
      if defined?(ActionMailer)
        SwingTradingMailer.recommendation_notification(@recommendation).deliver_later
        { success: true, message: 'Email notification queued' }
      else
        Rails.logger.warn('[SwingTrading::NotificationService] ActionMailer not available, skipping email notification')
        { success: false, error: 'ActionMailer not configured' }
      end
    rescue StandardError => e
      Rails.logger.error("[SwingTrading::NotificationService] Email notification failed: #{e.message}")
      { success: false, error: e.message }
    end

    def format_recommendation_for_broadcast
      {
        id: @recommendation.id,
        symbol_name: @recommendation.symbol_name,
        recommendation_type: @recommendation.recommendation_type,
        direction: @recommendation.direction,
        entry_price: @recommendation.entry_price.to_f,
        stop_loss: @recommendation.stop_loss.to_f,
        take_profit: @recommendation.take_profit.to_f,
        quantity: @recommendation.quantity,
        allocation_pct: @recommendation.allocation_pct.to_f,
        hold_duration_days: @recommendation.hold_duration_days,
        confidence_score: @recommendation.confidence_score&.to_f,
        risk_reward_ratio: @recommendation.risk_reward_ratio,
        investment_amount: @recommendation.investment_amount,
        reasoning: @recommendation.reasoning,
        analysis_timestamp: @recommendation.analysis_timestamp,
        timestamp: Time.current
      }
    end

    def success_result(data)
      { success: true, data: data }
    end

    def error_result(message, data = nil)
      result = { success: false, error: message }
      result[:data] = data if data
      result
    end
  end
end
