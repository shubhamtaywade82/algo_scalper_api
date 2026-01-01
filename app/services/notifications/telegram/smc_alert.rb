# frozen_string_literal: true

module Notifications
  module Telegram
    class SmcAlert
      def initialize(signal_event)
        @signal = signal_event
      end

      def notify!
        return nil unless @signal.valid?

        telegram_token = ENV['TELEGRAM_BOT_TOKEN']
        telegram_chat_id = ENV['TELEGRAM_CHAT_ID']

        if telegram_token.to_s.empty? || telegram_chat_id.to_s.empty?
          Rails.logger.warn('[Notifications::Telegram::SmcAlert] Telegram env missing; skipping alert')
          return nil
        end

        Client.new(token: telegram_token, chat_id: telegram_chat_id).send_message(format_message)
      rescue StandardError => e
        Rails.logger.error("[Notifications::Telegram::SmcAlert] #{e.class} - #{e.message}")
        nil
      end

      private

      def format_message
        <<~MSG
          🚨 *SMC + AVRZ SIGNAL*

          📌 *Instrument*: #{@signal.instrument.symbol_name}
          📊 *Action*: #{@signal.decision.to_s.upcase}
          ⏱ *Timeframe*: #{@signal.timeframe}
          💰 *Spot Price*: #{@signal.price}

          🧠 *Confluence*:
          #{formatted_reasons}

          🕒 *Time*: #{Time.current.strftime('%d %b %Y, %H:%M')}
        MSG
      end

      def formatted_reasons
        @signal.reasons.map { |r| "• #{r}" }.join("\n")
      end
    end
  end
end

