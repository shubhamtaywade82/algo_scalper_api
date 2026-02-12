# frozen_string_literal: true

# Handles DhanHQ API errors, especially authentication/token expiry
module DhanhqErrorHandler
  extend ActiveSupport::Concern

  # Error codes that indicate token expiry
  TOKEN_EXPIRY_CODES = %w[DH-901 401].freeze
  TOKEN_EXPIRY_KEYWORDS = [
    'access token.*expired',
    'token.*invalid',
    'Client ID.*invalid',
    'authentication.*failed',
    'unauthorized'
  ].freeze

  # Notification cooldown (prevent spam) - 1 hour
  NOTIFICATION_COOLDOWN = 1.hour
  REFRESH_COOLDOWN = 30.seconds

  # Make methods available as module methods (for direct calls like DhanhqErrorHandler.handle_dhanhq_error)
  # and as class methods (when included via ActiveSupport::Concern)
  module_function

  # Check if error indicates token expiry
  # @param error [StandardError, String] Error object or message
  # @return [Boolean]
  def token_expired?(error)
    error_msg = error.is_a?(String) ? error : error.message.to_s
    return false if error_msg.blank?

    # Check for error codes
    return true if TOKEN_EXPIRY_CODES.any? { |code| error_msg.include?(code) }

    # Check for error keywords (case-insensitive)
    TOKEN_EXPIRY_KEYWORDS.any? do |keyword|
      error_msg.match?(/#{keyword}/i)
    end
  end

  # Send Telegram notification for token expiry (with cooldown)
  # @param context [String] Context where error occurred (e.g., "intraday_ohlc", "fetch_option_chain")
  # @param error [StandardError, String] Error object or message
  # @return [Boolean] true if notification was sent, false otherwise
  def notify_token_expiry(context: 'API', error: nil)
    return false unless TelegramNotifier.enabled?

    # Check cooldown to prevent spam
    cache_key = 'dhanhq_token_expiry_notification_sent'
    last_notified = Rails.cache.read(cache_key)

    if last_notified && (Time.current - last_notified) < NOTIFICATION_COOLDOWN
      Rails.logger.debug('[DhanhqErrorHandler] Token expiry notification skipped (cooldown active)')
      return false
    end

    # Build notification message
    error_msg = error.is_a?(String) ? error : (error&.message || 'Unknown error')
    message = <<~MSG
      🚨 **DhanHQ Access Token Expired**

      **Context:** #{context}
      **Error:** #{error_msg}

      **Auto-heal:**
      The system will attempt to refresh the token (TOTP) and restart WebSockets.
      If this keeps happening, verify your `CLIENT_ID`, `DHAN_PIN`, and `DHAN_TOTP_SECRET`.

      **Note:** This notification will be sent again after #{NOTIFICATION_COOLDOWN.inspect} if issue persists.
    MSG

    # Send notification
    result = TelegramNotifier.send_message(message, parse_mode: 'Markdown')
    if result
      Rails.cache.write(cache_key, Time.current, expires_in: NOTIFICATION_COOLDOWN)
      Rails.logger.warn('[DhanhqErrorHandler] Token expiry notification sent to Telegram')
      true
    else
      Rails.logger.error('[DhanhqErrorHandler] Failed to send token expiry notification')
      false
    end
  rescue StandardError => e
    Rails.logger.error("[DhanhqErrorHandler] Error sending token expiry notification: #{e.class} - #{e.message}")
    false
  end

  # Handle DhanHQ errors with token expiry detection and notification
  # @param error [StandardError] Error object
  # @param context [String] Context where error occurred
  # @return [Hash] Error information hash
  def handle_dhanhq_error(error, context: 'API')
    error_msg = error.message.to_s
    is_token_expiry = token_expired?(error)

    if is_token_expiry
      Rails.logger.error("[DhanhqErrorHandler] Token expiry detected in #{context}: #{error.class} - #{error_msg}")
      attempt_refresh_if_configured(context: context, error: error)
      notify_token_expiry(context: context, error: error)
    else
      Rails.logger.error("[DhanhqErrorHandler] DhanHQ error in #{context}: #{error.class} - #{error_msg}")
    end

    {
      error: error,
      message: error_msg,
      token_expired: is_token_expiry
    }
  end

  def attempt_refresh_if_configured(context:, error:)
    return false unless defined?(Dhan::TokenManager)

    # prevent rapid-fire refresh attempts across repeated failing calls
    cache_key = 'dhanhq_token_refresh_attempted_at'
    last_attempt = Rails.cache.read(cache_key)
    return false if last_attempt && (Time.current - last_attempt) < REFRESH_COOLDOWN

    Rails.cache.write(cache_key, Time.current, expires_in: REFRESH_COOLDOWN)

    Rails.logger.warn("[DhanhqErrorHandler] Attempting token refresh (context=#{context})")
    Dhan::TokenManager.refresh!
    true
  rescue StandardError => e
    Rails.logger.error("[DhanhqErrorHandler] Refresh failed: #{e.class} - #{e.message}")
    false
  end

  # For ActiveSupport::Concern compatibility - make methods available as class methods when included
  class_methods do
    def token_expired?(error)
      DhanhqErrorHandler.token_expired?(error)
    end

    def notify_token_expiry(context: 'API', error: nil)
      DhanhqErrorHandler.notify_token_expiry(context: context, error: error)
    end

    def handle_dhanhq_error(error, context: 'API')
      DhanhqErrorHandler.handle_dhanhq_error(error, context: context)
    end

    def attempt_refresh_if_configured(context:, error:)
      DhanhqErrorHandler.attempt_refresh_if_configured(context: context, error: error)
    end
  end
end
