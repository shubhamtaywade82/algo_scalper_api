# frozen_string_literal: true

require 'json'
require 'net/http'

module Notifications
  module Telegram
    class Client
      TELEGRAM_API = 'https://api.telegram.org'

      def initialize(token:, chat_id:)
        @token = token
        @chat_id = chat_id
      end

      def send_message(text)
        return nil if @token.to_s.empty? || @chat_id.to_s.empty?

        uri = URI("#{TELEGRAM_API}/bot#{@token}/sendMessage")

        payload = {
          chat_id: @chat_id,
          text: text,
          parse_mode: 'Markdown'
        }

        Net::HTTP.post(uri, payload.to_json, 'Content-Type' => 'application/json')
      rescue StandardError => e
        Rails.logger.error("[Notifications::Telegram::Client] #{e.class} - #{e.message}")
        nil
      end
    end
  end
end

