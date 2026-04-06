# frozen_string_literal: true

require 'erb'

module Notifications
  module Telegram
    # Advisory Telegram for tick-triggered SMC confluence rising-edge + AI narrative.
    class SmcTickAiAlert
      def initialize(instrument:, fired_keys:, ltp:, analysis_text:)
        @instrument = instrument
        @fired_keys = fired_keys
        @ltp = ltp
        @analysis_text = analysis_text.to_s
      end

      def deliver!
        return unless telegram_enabled?
        return if @analysis_text.blank?

        client.send_message(format_message)
      rescue StandardError => e
        Rails.logger.error("[SmcTickAiAlert] #{e.class} - #{e.message}")
      end

      private

      def telegram_enabled?
        AlgoConfig.fetch.dig(:telegram, :enabled) == true &&
          ENV['TELEGRAM_BOT_TOKEN'].present? &&
          ENV['TELEGRAM_CHAT_ID'].present?
      rescue StandardError
        false
      end

      def client
        @client ||= Client.new(
          token: ENV.fetch('TELEGRAM_BOT_TOKEN'),
          chat_id: ENV.fetch('TELEGRAM_CHAT_ID')
        )
      end

      def format_message
        sym = escape(@instrument.symbol_name.to_s)
        keys = @fired_keys.map { |k| escape(k.to_s) }.join(', ')
        ltp_s = @ltp.to_f.positive? ? format('%.2f', @ltp.to_f) : 'N/A'
        body = escape(@analysis_text)

        <<~MSG.strip
          <b>Tick SMC AI</b> | #{sym}
          LTP: ₹#{ltp_s}
          <b>Edge:</b> #{keys}

          #{body}
        MSG
      end

      def escape(str)
        ERB::Util.html_escape(str.to_s)
      end
    end
  end
end
