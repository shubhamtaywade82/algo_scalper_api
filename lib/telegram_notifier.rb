# frozen_string_literal: true

require 'net/http'
require 'uri'

# Simple Telegram notifier using Net::HTTP
# Provides class methods for sending messages and chat actions
class TelegramNotifier
  TELEGRAM_API = 'https://api.telegram.org'
  MAX_LEN      = 4000 # keep margin below Telegram's 4096 limit
  OPEN_TIMEOUT = 2
  READ_TIMEOUT = 5

  # Send a message to Telegram
  # @param text [String] Message text
  # @param chat_id [String, Integer, nil] Chat ID (falls back to ENV)
  # @param skip_formatter [Boolean] Skip Markdown→HTML conversion (use when text is already HTML)
  # @param extra_params [Hash] Additional parameters (parse_mode, etc.)
  # @return [Net::HTTPResponse, nil]
  def self.send_message(text, chat_id: nil, skip_formatter: false, **extra_params)
    return if text.blank?

    chat_id ||= ENV.fetch('TELEGRAM_CHAT_ID', nil)
    return if chat_id.blank?

    chunks(text).each do |chunk|
      chunk = Telegram::Formatter.to_html(chunk) unless skip_formatter
      response = post('sendMessage',
                      chat_id: chat_id,
                      text: chunk,
                      **extra_params)

      # Telegram rejects malformed HTML/Markdown entities; resend as plain text
      # so the message is never dropped (stray <, >, & in dynamic content).
      next if response
      next if extra_params[:parse_mode].blank?

      retry_params = extra_params.except(:parse_mode)
      post('sendMessage', chat_id: chat_id, text: chunk, **retry_params)
    end
  end

  # Send a chat action (typing, uploading photo, etc.)
  # @param action [String] Action type (typing, upload_photo, etc.)
  # @param chat_id [String, Integer, nil] Chat ID (falls back to ENV)
  # @return [Net::HTTPResponse, nil]
  def self.send_chat_action(action:, chat_id: nil)
    chat_id ||= ENV.fetch('TELEGRAM_CHAT_ID', nil)
    return if chat_id.blank?

    post('sendChatAction', chat_id: chat_id, action: action)
  end

  # Check if Telegram is enabled (has bot token and chat ID)
  # @return [Boolean]
  def self.enabled?
    ENV['TELEGRAM_BOT_TOKEN'].present? && ENV['TELEGRAM_CHAT_ID'].present?
  end

  # -- PRIVATE --------------------------------------------------------------

  # Make a POST request to Telegram API
  # @param method [String] API method name
  # @param params [Hash] Parameters to send
  # @return [Net::HTTPResponse, nil]
  def self.post(method, **params)
    bot_token = ENV.fetch('TELEGRAM_BOT_TOKEN', nil)
    return if bot_token.blank?

    uri = URI("#{TELEGRAM_API}/bot#{bot_token}/#{method}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == 'https')
    http.open_timeout = OPEN_TIMEOUT
    http.read_timeout = READ_TIMEOUT
    request = Net::HTTP::Post.new(uri)
    request.set_form_data(params)
    res = http.request(request)

    unless res.is_a?(Net::HTTPSuccess)
      Rails.logger.error("[TelegramNotifier] #{method} failed: #{res.body}") if defined?(Rails)
      return nil
    end

    res
  rescue StandardError => e
    Rails.logger.error("[TelegramNotifier] #{method} error: #{e.class} - #{e.message}") if defined?(Rails)
    nil
  end

  private_class_method :post

  # Split text into safe chunks under MAX_LEN
  # Tries to split on paragraph boundaries first
  # @param text [String] Text to chunk
  # @return [Array<String>] Array of text chunks
  def self.chunks(text)
    return [] if text.blank?

    lines = text.split("\n")
    chunks = []
    buf = ''

    lines.each do |line|
      test_buf = buf.empty? ? line : "#{buf}\n#{line}"
      if test_buf.length > MAX_LEN
        chunks << buf.strip unless buf.empty?
        buf = line
      else
        buf = test_buf
      end
    end

    chunks << buf.strip unless buf.empty?
    chunks
  end

  private_class_method :chunks
end
