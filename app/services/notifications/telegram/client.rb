# frozen_string_literal: true

require 'net/http'
require 'json'

module Notifications
  module Telegram
    class Client
      TELEGRAM_API = 'https://api.telegram.org'

      def initialize(token:, chat_id:)
        @token   = token
        @chat_id = chat_id
      end

      TELEGRAM_MAX_MESSAGE_LENGTH = 4096

      def send_message(text)
        # Split message into chunks if it exceeds Telegram's limit
        chunks = split_into_chunks(text)

        chunks.each_with_index do |chunk, index|
          success = send_single_message(chunk, index + 1, chunks.size)
          return false unless success

          # Add small delay between chunks to avoid rate limiting
          sleep(0.5) if chunks.size > 1 && index < chunks.size - 1
        end

        true
      end

      def send_single_message(text, chunk_number = nil, total_chunks = nil)
        uri = URI("#{TELEGRAM_API}/bot#{@token}/sendMessage")

        # Add chunk indicator if message is split (but ensure total length is still under limit)
        if chunk_number && total_chunks && total_chunks > 1
          chunk_indicator = "\n\n<i>(Part #{chunk_number}/#{total_chunks})</i>"
          # If adding indicator would exceed limit, truncate text
          max_text_length = TELEGRAM_MAX_MESSAGE_LENGTH - chunk_indicator.length
          display_text = if text.length > max_text_length
                           "#{text[0..(max_text_length - 4)]}...#{chunk_indicator}"
                         else
                           text + chunk_indicator
                         end
        else
          display_text = text
        end

        # Final safety check - truncate if still too long
        if display_text.length > TELEGRAM_MAX_MESSAGE_LENGTH
          display_text = "#{display_text[0..(TELEGRAM_MAX_MESSAGE_LENGTH - 4)]}..."
        end

        payload = {
          chat_id: @chat_id,
          text: display_text,
          parse_mode: 'HTML'
        }

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = 10
        request = Net::HTTP::Post.new(uri.path)
        request['Content-Type'] = 'application/json'
        request.body = payload.to_json

        response = http.request(request)

        if response.is_a?(Net::HTTPSuccess)
          chunk_info = chunk_number ? " (chunk #{chunk_number}/#{total_chunks})" : ''
          Rails.logger.debug { "[Telegram] Message sent successfully to chat #{@chat_id}#{chunk_info}" }
          return true
        end

        # Log error details
        error_body = begin
          JSON.parse(response.body)
        rescue StandardError
          response.body
        end

        Rails.logger.error("[Telegram] Failed to send message: #{response.code} - #{error_body}")
        false
      rescue StandardError => e
        Rails.logger.error("[Telegram] Failed to send message: #{e.class} - #{e.message}")
        Rails.logger.debug { e.backtrace.first(5).join("\n") }
        false
      end

      private

      def split_into_chunks(text)
        return [text] if text.length <= TELEGRAM_MAX_MESSAGE_LENGTH

        chunks = []
        current_chunk = +''
        lines = text.split("\n")

        # Reserve space for chunk indicator (worst case: "(Part 999/999)" = ~20 chars + HTML tags = ~40 chars)
        # Use 50 chars as buffer to be safe
        max_chunk_size = TELEGRAM_MAX_MESSAGE_LENGTH - 50

        lines.each do |line|
          line_with_newline = "#{line}\n"

          # If a single line is too long, split it
          if line.length > max_chunk_size
            # Save current chunk if it has content
            chunks << current_chunk.strip if current_chunk.present?
            current_chunk = +''

            # Split the long line into smaller pieces
            line.chars.each_slice(max_chunk_size - 10) do |slice|
              chunks << slice.join
            end
          # If adding this line would exceed the limit, start a new chunk
          elsif (current_chunk + line_with_newline).length > max_chunk_size
            chunks << current_chunk.strip if current_chunk.present?
            current_chunk = line_with_newline
          else
            current_chunk << line_with_newline
          end
        end

        chunks << current_chunk.strip if current_chunk.present?
        chunks.reject(&:empty?)
      end
    end
  end
end
