# frozen_string_literal: true

require 'ollama_client'

module Services
  module Ai
    # Thin wrapper around Ollama::Client for trading AI analysis.
    # Provides serialized request queuing, model auto-selection, and a
    # stable interface (chat / generate / chat_stream) for the rest of the app.
    class OllamaClient
      class << self
        def instance
          @instance ||= new
        end

        def reset_instance!
          @instance = nil
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
        @provider              = :ollama
        @config_mutex          = Mutex.new
        @connection_fingerprint = nil
        @enabled               = false
        @client                = nil
        @available_models      = nil
        @selected_model        = nil
        @last_request_time     = nil
        ensure_connection!
      end

      attr_reader :provider, :selected_model, :available_models

      def client
        ensure_connection!
        @client
      end

      def enabled?
        ensure_connection!
        @enabled
      end

      # Effective HTTP base URL after applying +ai.ollama_use_cloud+ (AlgoConfig) and ENV.
      def ollama_base_url
        ensure_connection!
        resolved_base_url(ollama_use_cloud?)
      end

      # ------------------------------------------------------------------
      # Model discovery
      # ------------------------------------------------------------------

      def fetch_available_models
        ensure_connection!
        return [] unless @enabled

        base_url = resolved_base_url(ollama_use_cloud?)
        cached   = self.class.get_cached_models(base_url)
        if cached
          @available_models = cached
          return cached
        end

        names = @client.list_model_names
        @available_models = names
        self.class.set_cached_models(base_url, names)
        Rails.logger.info("[OllamaClient] Found #{names.count} Ollama models: #{names.join(', ')}")
        names
      rescue StandardError => e
        Rails.logger.error("[OllamaClient] Error fetching Ollama models: #{e.class} - #{e.message}")
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
            Rails.logger.info("[OllamaClient] Using explicitly set model: #{explicit}")
            return explicit
          else
            Rails.logger.warn("[OllamaClient] OLLAMA_MODEL=#{explicit} not found in available models — falling back to auto-selection")
          end
        end

        return nil if @available_models.blank?

        priority = %w[
          llama3.1:8b llama3.1:8b-instruct llama3:8b llama3:8b-instruct
          mistral:7b mistral mistral:instruct
          qwen3.5:4b qwen3.5:4b-instruct
          phi3:mini phi3 phi3:medium
          qwen2.5:1.5b-instruct gemma:2b gemma
          llama3:70b llama3:70b-instruct llama3 llama3:instruct
          codellama codellama:instruct gemma:7b
        ]

        selected = priority.find { |m| @available_models.include?(m) }
        selected ||= @available_models.find { |m| text_capable_model?(m) }
        selected ||= @available_models.first

        @selected_model = selected
        Rails.logger.info("[OllamaClient] Auto-selected model: #{selected}")
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
        ensure_connection!
        return nil unless @enabled

        model = resolve_model(model)
        log_prompt_and_tokens(messages: messages, model: model, log_context: log_context)

        result = chat_with_retry(messages: messages, model: model, temperature: temperature, tools: tools)

        if tools
          result
        elsif result.is_a?(Hash)
          (result[:content] || result['content']).to_s
        else
          result.to_s
        end
      rescue StandardError => e
        Rails.logger.error("[OllamaClient] Chat error: #{e.class} - #{e.message}")
        nil
      end

      # ------------------------------------------------------------------
      # Streaming chat
      # ------------------------------------------------------------------

      def chat_stream(messages:, model: nil, temperature: 0.7, tools: nil, tool_choice: nil, &block)
        ensure_connection!
        return nil unless @enabled

        model = resolve_model(model)
        log_prompt_and_tokens(messages: messages, model: model)

        with_serialization do
          stream_start  = Time.current
          chunk_count   = 0

          hooks = {
            on_token: lambda { |token|
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
          Rails.logger.debug { "[OllamaClient] Stream completed in #{elapsed.round(2)}s (#{chunk_count} chunks)" }
          response
        end
      rescue Ollama::TimeoutError, Ollama::Error => e
        Rails.logger.error("[OllamaClient] Chat stream error: #{e.class} - #{e.message}")
        nil
      end

      # ------------------------------------------------------------------
      # Generate (structured / raw)
      # ------------------------------------------------------------------

      def generate(prompt:, model: nil, schema: nil, stream: false, **)
        ensure_connection!
        return nil unless @enabled

        model = resolve_model(model)

        with_serialization do
          @client.generate(
            prompt: prompt,
            model: model,
            schema: schema
          )
        end
      rescue StandardError => e
        Rails.logger.error("[OllamaClient] Generate error: #{e.class} - #{e.message}")
        nil
      end

      private

      # ------------------------------------------------------------------
      # Internals
      # ------------------------------------------------------------------

      def ensure_connection!
        @config_mutex.synchronize do
          use_cloud = ollama_use_cloud?
          base      = resolved_base_url(use_cloud)
          key       = use_cloud ? ENV['OLLAMA_API_KEY'].to_s.strip : ''
          ai_on     = AlgoConfig.fetch.dig(:ai, :enabled) != false
          fp        = [use_cloud, base, key, ai_on].join('|')

          return if @client && @connection_fingerprint == fp

          @connection_fingerprint = fp
          @client = nil
          @available_models = nil
          @selected_model = nil
          @enabled = connection_allowed?(use_cloud: use_cloud, base: base, key: key)
          build_client! if @enabled
        end
      end

      def ollama_use_cloud?
        v = AlgoConfig.fetch.dig(:ai, :ollama_use_cloud)
        ActiveModel::Type::Boolean.new.cast(v)
      rescue StandardError
        false
      end

      def resolved_base_url(use_cloud)
        if use_cloud
          ENV['OLLAMA_CLOUD_URL'].presence ||
            ENV['OLLAMA_BASE_URL'].presence ||
            'https://ollama.com'
        else
          ENV['OLLAMA_LOCAL_URL'].presence ||
            ENV['OLLAMA_HOST_URL'].presence ||
            ENV['OLLAMA_BASE_URL'].presence ||
            'http://localhost:11434'
        end
      end

      def connection_allowed?(use_cloud:, base:, key:)
        return false if AlgoConfig.fetch.dig(:ai, :enabled) == false

        if base.blank?
          Rails.logger.warn('[OllamaClient] Resolved Ollama base URL is blank')
          return false
        end

        if use_cloud && key.blank?
          Rails.logger.warn('[OllamaClient] Cloud mode (ai.ollama_use_cloud) requires OLLAMA_API_KEY')
          return false
        end

        true
      rescue StandardError => e
        Rails.logger.warn("[OllamaClient] connection_allowed? failed: #{e.class} - #{e.message}")
        false
      end

      def build_client!
        timeout = ENV.fetch('OLLAMA_TIMEOUT', '120').to_i
        use_cloud = ollama_use_cloud?
        base      = resolved_base_url(use_cloud)

        config = Ollama::Config.new
        config.base_url    = base
        config.model       = ENV.fetch('OLLAMA_MODEL', 'qwen3.5:4b')
        config.timeout     = timeout
        config.temperature = 0.2
        config.strict_json = false
        key = ENV['OLLAMA_API_KEY'].presence
        config.api_key = key if use_cloud && key.present?

        @client = Ollama::Client.new(config: config)
        mode = use_cloud ? 'cloud' : 'local'
        Rails.logger.info("[OllamaClient] Connected (#{mode}) at #{base}")
        Rails.logger.info('[OllamaClient] Initialized with provider: ollama')
      rescue StandardError => e
        Rails.logger.error("[OllamaClient] Failed to initialize: #{e.class} - #{e.message}")
        @enabled = false
        @client = nil
      end

      def resolve_model(model)
        return model if model.present?

        fetch_and_select_model if @selected_model.nil?
        @selected_model || ENV.fetch('OLLAMA_MODEL', 'qwen3.5:4b')
      end

      def with_serialization(&)
        REQUEST_MUTEX.synchronize do
          if @last_request_time
            elapsed_ms = (Time.current - @last_request_time) * 1000
            sleep((REQUEST_DELAY_MS - elapsed_ms) / 1000.0) if elapsed_ms < REQUEST_DELAY_MS
          end
          @last_request_time = Time.current
          yield
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

          Rails.logger.warn("[OllamaClient] Retrying (#{attempt}/#{max_attempts}) after #{e.class}: #{e.message}")
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
            'id' => tc.id,
            'type' => 'function',
            'function' => {
              'name' => tc.function&.name,
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
          logger.info("[OllamaClient] Sending prompt to #{model} (~#{token_count} tokens)")
        else
          Rails.logger.info("[OllamaClient] Sending prompt to #{model} (~#{token_count} tokens)")
        end
      end
    end
  end
end
