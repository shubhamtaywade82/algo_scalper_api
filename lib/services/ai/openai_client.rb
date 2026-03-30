# frozen_string_literal: true

require 'ollama_client'

module Services
  module Ai
    # Thin wrapper around Ollama::Client for trading AI analysis.
    # Provides serialized request queuing, model auto-selection, and a
    # stable interface (chat / generate / chat_stream) for the rest of the app.
    class OpenaiClient
      class << self
        def instance
          @instance ||= new
        end

        delegate :client, :enabled?, to: :instance
      end

      # Serialize concurrent Ollama calls so we don't overwhelm a single GPU
      REQUEST_MUTEX = Mutex.new
      REQUEST_DELAY_MS = ENV.fetch('OLLAMA_REQUEST_DELAY_MS', '500').to_i

      MODELS_CACHE_TTL = ENV.fetch('OLLAMA_MODELS_CACHE_TTL', '300').to_i

      @models_cache = {}
      @models_cache_mutex = Mutex.new

      class << self
        attr_accessor :models_cache, :models_cache_mutex
      end

      self.models_cache = {}
      self.models_cache_mutex = Mutex.new

      def initialize
        @provider       = :ollama
        @enabled        = check_enabled
        @available_models = nil
        @selected_model   = nil
        @last_request_time = nil
        initialize_client if @enabled
      end

      attr_reader :client, :provider, :selected_model, :available_models

      def enabled?
        @enabled
      end

      def ollama_base_url
        ENV['OLLAMA_HOST_URL'] || ENV['OLLAMA_BASE_URL'] || 'http://localhost:11434'
      end

      # ------------------------------------------------------------------
      # Model discovery
      # ------------------------------------------------------------------

      def fetch_available_models
        return [] unless @enabled

        base_url = ollama_base_url
        cached   = self.class.get_cached_models(base_url)
        if cached
          @available_models = cached
          return cached
        end

        names = @client.list_model_names
        @available_models = names
        self.class.set_cached_models(base_url, names)
        Rails.logger.info("[OpenAIClient] Found #{names.count} Ollama models: #{names.join(', ')}")
        names
      rescue StandardError => e
        Rails.logger.error("[OpenAIClient] Error fetching Ollama models: #{e.class} - #{e.message}")
        []
      end

      def self.get_cached_models(base_url)
        models_cache_mutex.synchronize do
          cached = models_cache[base_url]
          return nil unless cached
          return nil if Time.current - cached[:fetched_at] > MODELS_CACHE_TTL

          cached[:models]
        end
      end

      def self.set_cached_models(base_url, models)
        models_cache_mutex.synchronize do
          models_cache[base_url] = { models: models, fetched_at: Time.current }
        end
      end

      delegate :get_cached_models, :set_cached_models, to: :class

      def select_best_model
        fetch_available_models if @available_models.nil?

        explicit = ENV['OLLAMA_MODEL'].presence
        if explicit
          if @available_models&.include?(explicit)
            @selected_model = explicit
            Rails.logger.info("[OpenAIClient] Using explicitly set model: #{explicit}")
            return explicit
          else
            Rails.logger.warn("[OpenAIClient] OLLAMA_MODEL=#{explicit} not found in available models — falling back to auto-selection")
          end
        end

        return nil if @available_models.blank?

        priority = %w[
          llama3.1:8b llama3.1:8b-instruct llama3:8b llama3:8b-instruct
          mistral:7b mistral mistral:instruct
          llama3.2:3b llama3.2:3b-instruct
          phi3:mini phi3 phi3:medium
          qwen2.5:1.5b-instruct gemma:2b gemma
          llama3:70b llama3:70b-instruct llama3 llama3:instruct
          codellama codellama:instruct gemma:7b
        ]

        selected = priority.find { |m| @available_models.include?(m) }
        selected ||= @available_models.find { |m| text_capable_model?(m) }
        selected ||= @available_models.first

        @selected_model = selected
        Rails.logger.info("[OpenAIClient] Auto-selected model: #{selected}")
        selected
      end

      def preferred_text_model(default: 'llama3.1:8b')
        fetch_and_select_model if @selected_model.nil? && @available_models.nil?

        explicit = ENV['OLLAMA_MODEL'].presence
        return explicit if explicit && text_capable_model?(explicit)

        return @selected_model if @selected_model.present? && text_capable_model?(@selected_model)

        @available_models&.find { |m| text_capable_model?(m) } || default
      end

      def fetch_and_select_model
        fetch_available_models
        select_best_model
      end

      # ------------------------------------------------------------------
      # Chat
      # ------------------------------------------------------------------

      # Returns content string when no tools; returns {content:, tool_calls:} hash when tools provided.
      def chat(messages:, model: nil, temperature: 0.7, tools: nil, tool_choice: nil, log_context: nil, **)
        return nil unless enabled?

        model = resolve_model(model)
        log_prompt_and_tokens(messages: messages, model: model, log_context: log_context)

        result = chat_with_retry(messages: messages, model: model, temperature: temperature, tools: tools)

        tools ? result : (result.is_a?(Hash) ? (result[:content] || result['content']).to_s : result.to_s)
      rescue StandardError => e
        Rails.logger.error("[OpenAIClient] Chat error: #{e.class} - #{e.message}")
        nil
      end

      # ------------------------------------------------------------------
      # Streaming chat
      # ------------------------------------------------------------------

      def chat_stream(messages:, model: nil, temperature: 0.7, tools: nil, tool_choice: nil, &block)
        return nil unless enabled?

        model = resolve_model(model)
        log_prompt_and_tokens(messages: messages, model: model)

        with_serialization do
          stream_start  = Time.current
          chunk_count   = 0

          hooks = {
            on_token: ->(token) {
              chunk_count += 1
              block&.call(token)
            }
          }

          response = @client.chat(
            messages: format_messages(messages),
            model: model,
            stream: true,
            options: { temperature: temperature },
            tools: tools,
            hooks: hooks
          )

          elapsed = Time.current - stream_start
          Rails.logger.debug { "[OpenAIClient] Stream completed in #{elapsed.round(2)}s (#{chunk_count} chunks)" }
          response
        end
      rescue Ollama::TimeoutError, Ollama::Error => e
        Rails.logger.error("[OpenAIClient] Chat stream error: #{e.class} - #{e.message}")
        nil
      end

      # ------------------------------------------------------------------
      # Generate (structured / raw)
      # ------------------------------------------------------------------

      def generate(prompt:, model: nil, schema: nil, stream: false, **)
        return nil unless enabled?

        model = resolve_model(model)

        with_serialization do
          @client.generate(
            prompt: prompt,
            model: model,
            schema: schema
          )
        end
      rescue StandardError => e
        Rails.logger.error("[OpenAIClient] Generate error: #{e.class} - #{e.message}")
        nil
      end

      private

      # ------------------------------------------------------------------
      # Internals
      # ------------------------------------------------------------------

      def check_enabled
        return false if AlgoConfig.fetch.dig(:ai, :enabled) == false

        unless ollama_base_url.present?
          Rails.logger.warn('[OpenAIClient] Ollama base URL not configured (OLLAMA_HOST_URL or OLLAMA_BASE_URL)')
          return false
        end

        true
      rescue StandardError
        false
      end

      def initialize_client
        timeout = ENV.fetch('OLLAMA_TIMEOUT', '120').to_i

        config = Ollama::Config.new
        config.base_url    = ollama_base_url
        config.model       = ENV.fetch('OLLAMA_MODEL', 'llama3.2:3b')
        config.timeout     = timeout
        config.temperature = 0.2
        config.strict_json = false

        @client = Ollama::Client.new(config: config)
        Rails.logger.info("[OpenAIClient] Connected to Ollama at #{ollama_base_url}")
        Rails.logger.info("[OpenAIClient] Initialized with provider: ollama")
      rescue StandardError => e
        Rails.logger.error("[OpenAIClient] Failed to initialize: #{e.class} - #{e.message}")
        @enabled = false
      end

      def resolve_model(model)
        return model if model.present?

        fetch_and_select_model if @selected_model.nil?
        @selected_model || ENV.fetch('OLLAMA_MODEL', 'llama3.2:3b')
      end

      def with_serialization(&block)
        REQUEST_MUTEX.synchronize do
          if @last_request_time
            elapsed_ms = (Time.current - @last_request_time) * 1000
            sleep((REQUEST_DELAY_MS - elapsed_ms) / 1000.0) if elapsed_ms < REQUEST_DELAY_MS
          end
          @last_request_time = Time.current
          block.call
        end
      end

      def chat_with_retry(messages:, model:, temperature:, tools:)
        max_attempts = 3
        attempt      = 0

        begin
          attempt += 1
          with_serialization do
            response = @client.chat(
              messages: format_messages(messages),
              model: model,
              options: { temperature: temperature },
              tools: tools
            )
            extract_content(response, tools)
          end
        rescue Ollama::TimeoutError, Ollama::HTTPError => e
          raise unless attempt < max_attempts

          Rails.logger.warn("[OpenAIClient] Retrying (#{attempt}/#{max_attempts}) after #{e.class}: #{e.message}")
          sleep(3)
          retry
        end
      end

      # Normalize messages to plain hashes with string keys for Ollama
      def format_messages(messages)
        messages.map do |msg|
          next msg unless msg.is_a?(Hash)

          out = { 'role' => (msg[:role] || msg['role']).to_s }
          content = msg[:content] || msg['content']
          out['content'] = content if content
          out['tool_calls']   = msg[:tool_calls]   || msg['tool_calls']   if msg[:tool_calls]   || msg['tool_calls']
          out['tool_call_id'] = msg[:tool_call_id] || msg['tool_call_id'] if msg[:tool_call_id] || msg['tool_call_id']
          out['name']         = msg[:name]         || msg['name']         if msg[:name]         || msg['name']
          out
        end
      end

      # Map Ollama::Response → {content:, tool_calls:} or plain string
      def extract_content(response, tools)
        return { content: nil, tool_calls: [] } unless response

        content = response.content
        tool_calls = response.message&.tool_calls&.map do |tc|
          {
            'id'       => tc.id,
            'type'     => 'function',
            'function' => {
              'name'      => tc.function&.name,
              'arguments' => tc.function&.arguments.to_json
            }
          }
        end || []

        { content: content, tool_calls: tool_calls }
      end

      def text_capable_model?(name)
        return false if name.blank?

        %w[vl vision llava minicpm-v qwen-vl].none? { |m| name.downcase.include?(m) }
      end

      def estimate_token_count(messages)
        return 0 unless messages.is_a?(Array)

        total = messages.sum { |m| (m[:content] || m['content'] || '').to_s.length + 4 }
        (total / 4.0).ceil + (messages.length * 2)
      end

      def log_prompt_and_tokens(messages:, model:, log_context: nil)
        token_count = estimate_token_count(messages)
        logger      = log_context == :ai_intent &&
                        Rails.application.config.respond_to?(:ai_intent_logger) &&
                        Rails.application.config.ai_intent_logger

        if logger
          logger.info("[OpenAIClient] Sending prompt to #{model} (~#{token_count} tokens)")
        else
          Rails.logger.info("[OpenAIClient] Sending prompt to #{model} (~#{token_count} tokens)")
        end
      end
    end
  end
end
