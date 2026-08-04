# frozen_string_literal: true

# rubocop:disable Rails/Output
module Ai
  module TradingBot
    # Telegram notification handler for trading signals and executions.
    class Notifier
      def initialize(config)
        @config = config
      end

      # Sends notification about a trade signal and execution result.
      def notify_signal(symbol, signal, result)
        return unless @config.telegram_notify

        message = build_message(symbol, signal, result)
        send_telegram(message)
      rescue StandardError => e
        puts "  Notification error: #{e.message}" if @config.verbose?
      end

      private

      def build_message(symbol, signal, result)
        action = signal[:action]
        emoji = case action
                when 'BUY' then "\u{1f7e2}"
                when 'SELL' then "\u{1f534}"
                else "\u{1f7e1}"
                end
        status = result[:success] ? 'Executed' : 'Failed'

        lines = []
        lines << "#{emoji} *#{symbol}* #{action} — #{status}"
        lines << "Entry: \u20b9#{signal[:entry_price]&.round(2)}"
        lines << "SL: \u20b9#{signal[:stop_loss]&.round(2)}"
        lines << "TP: \u20b9#{signal[:take_profit]&.round(2)}"
        lines << "R:R: #{signal[:rr_ratio]}" if signal[:rr_ratio]
        lines << "Confidence: #{((signal[:confidence] || 0) * 100).round(1)}%"

        if result[:success]
          lines << "Type: #{result[:type]}"
          lines << "Qty: #{result[:qty]}"
        else
          lines << "Error: #{result[:reason]}"
        end

        lines << "Time: #{Time.now.strftime('%H:%M:%S')}"
        lines.join("\n")
      end

      def send_telegram(message)
        return unless telegram_configured?

        bot_token = ENV.fetch('TELEGRAM_BOT_TOKEN', nil)
        chat_id = ENV.fetch('TELEGRAM_CHAT_ID', nil)

        uri = URI("https://api.telegram.org/bot#{bot_token}/sendMessage")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = 5
        http.read_timeout = 5

        req = Net::HTTP::Post.new(uri)
        req['Content-Type'] = 'application/json'
        req.body = JSON.generate({
          chat_id: chat_id,
          text: message,
          parse_mode: 'Markdown'
        })

        http.request(req)
      end

      def telegram_configured?
        ENV.fetch('TELEGRAM_BOT_TOKEN', nil) && ENV.fetch('TELEGRAM_CHAT_ID', nil)
      end
    end
  end
end
# rubocop:enable Rails/Output
