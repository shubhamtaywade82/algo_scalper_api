# frozen_string_literal: true

require 'faraday'
require 'json'

module Providers
  # Client for Ollama inference server (Machine B - Client Side)
  #
  # Usage:
  #   Providers::OllamaClient.generate("What is the trend?", model: "phi3:mini")
  #   Providers::OllamaClient.embed("Some text", model: "nomic-embed-text")
  #
  # Safety:
  #   - All requests are serialized (no parallel calls)
  #   - Timeouts prevent hanging
  #   - Never mix chat + embeddings concurrently
  class OllamaClient
    TIMEOUT_SECONDS = 20
    OPEN_TIMEOUT_SECONDS = 5
    DEFAULT_CHAT_MODEL = 'phi3:mini'
    DEFAULT_EMBED_MODEL = 'nomic-embed-text'

    class << self
      # Generate text completion using chat model
      #
      # @param prompt [String] The prompt to send
      # @param model [String] Model name (default: "phi3:mini")
      # @return [String, Symbol] Response text or :ollama_timeout on timeout
      def generate(prompt, model: DEFAULT_CHAT_MODEL)
        return :ollama_not_configured unless configured?

        response = faraday_client.post('/api/generate') do |req|
          req.body = {
            model: model,
            prompt: prompt,
            stream: false
          }.to_json
          req.headers['Content-Type'] = 'application/json'
        end

        parsed = JSON.parse(response.body)
        parsed['response']
      rescue Faraday::TimeoutError
        Rails.logger.error("[OllamaClient] Timeout generating with model #{model}")
        :ollama_timeout
      rescue JSON::ParserError => e
        Rails.logger.error("[OllamaClient] JSON parse error: #{e.class} - #{e.message}")
        :ollama_error
      rescue StandardError => e
        Rails.logger.error("[OllamaClient] Generate error: #{e.class} - #{e.message}")
        :ollama_error
      end

      # Generate embeddings using embedding model
      #
      # @param text [String] Text to embed
      # @param model [String] Embedding model name (default: "nomic-embed-text")
      # @return [Array<Float>, Symbol] Embedding vector or error symbol
      def embed(text, model: DEFAULT_EMBED_MODEL)
        return :ollama_not_configured unless configured?

        response = faraday_client.post('/api/embeddings') do |req|
          req.body = {
            model: model,
            prompt: text
          }.to_json
          req.headers['Content-Type'] = 'application/json'
        end

        parsed = JSON.parse(response.body)
        parsed['embedding']
      rescue Faraday::TimeoutError
        Rails.logger.error("[OllamaClient] Timeout embedding with model #{model}")
        :ollama_timeout
      rescue JSON::ParserError => e
        Rails.logger.error("[OllamaClient] JSON parse error: #{e.class} - #{e.message}")
        :ollama_error
      rescue StandardError => e
        Rails.logger.error("[OllamaClient] Embed error: #{e.class} - #{e.message}")
        :ollama_error
      end

      # Health check - verify Ollama server is reachable
      #
      # @return [Boolean] true if server responds, false otherwise
      def health_check
        return false unless configured?

        response = faraday_client.get('/api/version') do |req|
          req.options.timeout = 2
        end

        response.status == 200
      rescue StandardError
        false
      end

      private

      def configured?
        ENV['OLLAMA_HOST'].present?
      end

      def faraday_client
        @faraday_client ||= Faraday.new(url: ENV.fetch('OLLAMA_HOST')) do |conn|
          conn.options.timeout = TIMEOUT_SECONDS
          conn.options.open_timeout = OPEN_TIMEOUT_SECONDS
          conn.adapter Faraday.default_adapter
        end
      end
    end
  end
end
