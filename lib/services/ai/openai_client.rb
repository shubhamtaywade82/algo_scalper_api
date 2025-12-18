# frozen_string_literal: true

require 'net/http'
require 'json'

module Services
  module Ai
    # Abstraction layer for OpenAI API clients
    # Supports both ruby-openai (dev) and openai-ruby (production)
    # Also supports Ollama (local/network instances)
    class OpenaiClient
      class << self
        def instance
          @instance ||= new
        end

        delegate :client, to: :instance

        delegate :enabled?, to: :instance
      end

      def initialize
        @client = nil
        @provider = determine_provider
        @enabled = check_enabled
        @available_models = nil
        @selected_model = nil
        initialize_client if @enabled
        fetch_and_select_model if @enabled && @provider == :ollama
      end

      attr_reader :client, :provider, :selected_model, :available_models

      def enabled?
        @enabled
      end

      # Get available models from Ollama
      def fetch_available_models
        return [] unless @provider == :ollama && @enabled

        begin
          base_url = ENV['OLLAMA_BASE_URL'] || 'http://localhost:11434'
          response = Net::HTTP.get_response(URI("#{base_url}/api/tags"))

          if response.code == '200'
            data = JSON.parse(response.body)
            models = data['models'] || []
            @available_models = models.map { |m| m['name'] }.compact
            Rails.logger.info("[OpenAIClient] Found #{@available_models.count} Ollama models: #{@available_models.join(', ')}")
            @available_models
          else
            Rails.logger.warn("[OpenAIClient] Failed to fetch Ollama models: HTTP #{response.code}")
            []
          end
        rescue StandardError => e
          Rails.logger.error("[OpenAIClient] Error fetching Ollama models: #{e.class} - #{e.message}")
          []
        end
      end

      # Select best model from available models
      def select_best_model
        return nil unless @provider == :ollama

        # Use explicitly set model if provided
        explicit_model = ENV.fetch('OLLAMA_MODEL', nil)
        if explicit_model.present?
          if @available_models&.include?(explicit_model)
            @selected_model = explicit_model
            Rails.logger.info("[OpenAIClient] Using explicitly set model: #{explicit_model}")
            return explicit_model
          else
            Rails.logger.warn("[OpenAIClient] Model '#{explicit_model}' not found, selecting from available models")
          end
        end

        # Auto-select best model based on priority
        return nil if @available_models.blank?

        # Priority order: prefer larger/more capable models for trading analysis
        # Trading analysis requires: complex reasoning, financial understanding, structured output
        priority_models = [
          # Large models (best for complex analysis, but slower)
          'llama3:70b', 'llama3:70b-instruct',
          'llama3', 'llama3:instruct',
          # 8B models (best balance: capable + fast enough for real-time analysis)
          'llama3.1:8b', 'llama3.1:8b-instruct', 'llama3:8b', 'llama3:8b-instruct',
          # 7B models (good alternative)
          'mistral:7b', 'mistral', 'mistral:instruct',
          # 3B models (faster but less capable)
          'llama3.2:3b', 'llama3.2:3b-instruct', 'llama3:3b',
          # Code models (not ideal for trading, but better than tiny models)
          'codellama', 'codellama:instruct',
          # Small models (fast but limited reasoning)
          'phi3', 'phi3:mini', 'phi3:medium',
          'qwen2.5:1.5b-instruct', 'gemma', 'gemma:2b', 'gemma:7b'
        ]

        # Try priority models first
        selected = priority_models.find { |m| @available_models.include?(m) }

        # If no priority model found, use first available
        selected ||= @available_models.first

        @selected_model = selected
        Rails.logger.info("[OpenAIClient] Auto-selected best model: #{selected}")
        selected
      end

      def fetch_and_select_model
        fetch_available_models
        select_best_model
      end

      # Chat completion interface (works with both gems)
      def chat(messages:, model: nil, temperature: 0.7, **)
        return nil unless enabled?

        # Auto-select model for Ollama if not provided
        model ||= if @provider == :ollama
                    @selected_model || select_best_model || ENV['OLLAMA_MODEL'] || 'llama3'
                  else
                    'gpt-4o'
                  end

        case @provider
        when :ruby_openai
          chat_ruby_openai(messages: messages, model: model, temperature: temperature, **)
        when :openai_ruby
          chat_openai_ruby(messages: messages, model: model, temperature: temperature, **)
        when :ollama
          # Ollama uses OpenAI-compatible API, use the same client methods
          if defined?(OpenAI) && OpenAI.respond_to?(:configure)
            chat_ruby_openai(messages: messages, model: model, temperature: temperature, **)
          else
            chat_openai_ruby(messages: messages, model: model, temperature: temperature, **)
          end
        else
          raise "Unknown provider: #{@provider}"
        end
      rescue StandardError => e
        Rails.logger.error("[OpenAIClient] Chat error: #{e.class} - #{e.message}")
        nil
      end

      # Streaming chat completion
      def chat_stream(messages:, model: nil, temperature: 0.7, &)
        return nil unless enabled?

        # Auto-select model for Ollama if not provided
        model ||= if @provider == :ollama
                    @selected_model || select_best_model || ENV['OLLAMA_MODEL'] || 'llama3'
                  else
                    'gpt-4o'
                  end

        case @provider
        when :ruby_openai
          chat_stream_ruby_openai(messages: messages, model: model, temperature: temperature, &)
        when :openai_ruby
          chat_stream_openai_ruby(messages: messages, model: model, temperature: temperature, &)
        when :ollama
          # Ollama uses OpenAI-compatible API, use the same client methods
          if defined?(OpenAI) && OpenAI.respond_to?(:configure)
            chat_stream_ruby_openai(messages: messages, model: model, temperature: temperature, &)
          else
            chat_stream_openai_ruby(messages: messages, model: model, temperature: temperature, &)
          end
        else
          raise "Unknown provider: #{@provider}"
        end
      rescue StandardError => e
        Rails.logger.error("[OpenAIClient] Chat stream error: #{e.class} - #{e.message}")
        nil
      end

      private

      def determine_provider
        # Check environment variable first, then fall back to Rails.env
        provider_env = ENV['OPENAI_PROVIDER']&.downcase&.to_sym

        # Check if Ollama is configured
        return :ollama if ENV['OLLAMA_BASE_URL'].present?

        if %i[ruby_openai openai_ruby ollama].include?(provider_env)
          provider_env
        elsif Rails.env.local?
          :ruby_openai
        else
          :openai_ruby
        end
      end

      def check_enabled
        enabled_config = AlgoConfig.fetch.dig(:ai, :enabled)

        if enabled_config == false
          Rails.logger.info('[OpenAIClient] AI integration disabled in config')
          return false
        end

        # Ollama doesn't require API key, check base URL instead
        if @provider == :ollama
          unless ENV['OLLAMA_BASE_URL'].present?
            Rails.logger.warn('[OpenAIClient] Ollama base URL not configured (OLLAMA_BASE_URL)')
            return false
          end
          return true
        end

        # OpenAI requires API key
        api_key = ENV['OPENAI_API_KEY'] || ENV.fetch('OPENAI_ACCESS_TOKEN', nil)
        unless api_key.present?
          Rails.logger.warn('[OpenAIClient] No OpenAI API key found (OPENAI_API_KEY or OPENAI_ACCESS_TOKEN)')
          return false
        end

        true
      end

      def initialize_client
        case @provider
        when :ollama
          initialize_ollama
        when :ruby_openai
          api_key = ENV['OPENAI_API_KEY'] || ENV.fetch('OPENAI_ACCESS_TOKEN', nil)
          initialize_ruby_openai(api_key)
        when :openai_ruby
          api_key = ENV['OPENAI_API_KEY'] || ENV.fetch('OPENAI_ACCESS_TOKEN', nil)
          initialize_openai_ruby(api_key)
        end

        Rails.logger.info("[OpenAIClient] Initialized with provider: #{@provider}")
      rescue StandardError => e
        Rails.logger.error("[OpenAIClient] Failed to initialize: #{e.class} - #{e.message}")
        @enabled = false
      end

      # ruby-openai initialization (alexrudall/ruby-openai)
      def initialize_ruby_openai(api_key)
        # ruby-openai uses 'ruby/openai' require path
        # Check if already loaded to avoid conflicts
        unless defined?(OpenAI) && OpenAI.const_defined?(:Client)
          begin
            require 'ruby/openai'
          rescue LoadError => e
            Rails.logger.error("[OpenAIClient] Failed to load ruby-openai: #{e.message}")
            raise 'ruby-openai gem not available. Install with: bundle install'
          end
        end

        OpenAI.configure do |config|
          config.access_token = api_key
          config.log_errors = Rails.env.development?
        end

        @client = OpenAI::Client.new
      end

      # openai-ruby initialization (official gem)
      def initialize_openai_ruby(api_key)
        # openai-ruby uses 'openai' require path
        # Check if already loaded to avoid conflicts
        unless defined?(OpenAI) && OpenAI.const_defined?(:Client)
          begin
            require 'openai'
          rescue LoadError => e
            Rails.logger.error("[OpenAIClient] Failed to load openai-ruby: #{e.message}")
            raise 'openai-ruby gem not available. Install with: bundle install'
          end
        end

        @client = OpenAI::Client.new(api_key: api_key)
      end

      # Ollama initialization (local/network Ollama instance)
      def initialize_ollama
        # Ollama is OpenAI-compatible, use ruby-openai gem with custom base URI
        unless defined?(OpenAI) && OpenAI.const_defined?(:Client)
          begin
            require 'ruby/openai'
          rescue LoadError
            begin
              require 'openai'
            rescue LoadError => e
              Rails.logger.error("[OpenAIClient] Failed to load OpenAI client for Ollama: #{e.message}")
              raise 'OpenAI client gem not available. Install ruby-openai or openai-ruby'
            end
          end
        end

        base_url = ENV['OLLAMA_BASE_URL'] || 'http://localhost:11434'
        api_key = ENV['OLLAMA_API_KEY'] || 'ollama' # Ollama doesn't require auth, but some clients expect a key

        # Use ruby-openai if available (better Ollama support)
        if defined?(OpenAI) && OpenAI.respond_to?(:configure)
          # Configure longer timeouts for Ollama (streaming can take time)
          timeout = ENV.fetch('OLLAMA_TIMEOUT', '300').to_i # Default 5 minutes for streaming

          OpenAI.configure do |config|
            config.access_token = api_key
            config.uri_base = "#{base_url}/v1" # Ollama uses /v1 prefix
            config.log_errors = Rails.env.development?
            # Configure request timeout for streaming
            config.request_timeout = timeout
          end
          @client = OpenAI::Client.new
        else
          # Fallback to openai-ruby
          timeout = ENV.fetch('OLLAMA_TIMEOUT', '300').to_i
          @client = OpenAI::Client.new(
            api_key: api_key,
            uri_base: "#{base_url}/v1",
            request_timeout: timeout
          )
        end

        Rails.logger.info("[OpenAIClient] Connected to Ollama at #{base_url}")
      end

      # Chat completion using ruby-openai
      def chat_ruby_openai(messages:, model:, temperature:, **options)
        response = @client.chat(
          parameters: {
            model: model,
            messages: format_messages_ruby_openai(messages),
            temperature: temperature,
            **options
          }
        )

        extract_content_ruby_openai(response)
      end

      # Chat completion using openai-ruby
      def chat_openai_ruby(messages:, model:, temperature:, **)
        response = @client.chat.completions.create(
          messages: format_messages_openai_ruby(messages),
          model: model,
          temperature: temperature,
          **
        )

        extract_content_openai_ruby(response)
      end

      # Streaming chat using ruby-openai
      def chat_stream_ruby_openai(messages:, model:, temperature:, &block)
        @client.chat(
          parameters: {
            model: model,
            messages: format_messages_ruby_openai(messages),
            temperature: temperature,
            stream: proc do |chunk, _event|
              content = chunk.dig('choices', 0, 'delta', 'content')
              yield(content) if content.present? && block_given?
            end
          }
        )
      rescue Faraday::TimeoutError, Net::ReadTimeout => e
        # Timeout errors during streaming - log but don't fail if we got some content
        Rails.logger.warn { "[OpenAIClient] Stream timeout: #{e.class} - #{e.message}" }
        # Return nil to indicate partial stream
        nil
      rescue StandardError => e
        # Some streaming implementations may raise errors on stream end
        # This is expected behavior for some providers
        if e.message.include?('end of file') || e.message.include?('Connection') || e.message.include?('closed')
          Rails.logger.debug { "[OpenAIClient] Stream ended normally: #{e.class}" } if Rails.env.development?
          nil
        else
          Rails.logger.error { "[OpenAIClient] Stream error: #{e.class} - #{e.message}" }
          raise
        end
      end

      # Streaming chat using openai-ruby
      def chat_stream_openai_ruby(messages:, model:, temperature:, &block)
        stream = @client.chat.completions.create(
          messages: format_messages_openai_ruby(messages),
          model: model,
          temperature: temperature,
          stream: true
        )

        stream.each do |event|
          content = event.dig('choices', 0, 'delta', 'content')
          yield(content) if content.present?
        end
      end

      # Format messages for ruby-openai (expects array of hashes)
      def format_messages_ruby_openai(messages)
        messages.map do |msg|
          if msg.is_a?(Hash)
            { role: msg[:role] || msg['role'], content: msg[:content] || msg['content'] }
          else
            msg
          end
        end
      end

      # Format messages for openai-ruby (expects array of hashes with symbol keys)
      def format_messages_openai_ruby(messages)
        messages.map do |msg|
          if msg.is_a?(Hash)
            { role: (msg[:role] || msg['role']).to_sym, content: msg[:content] || msg['content'] }
          else
            msg
          end
        end
      end

      # Extract content from ruby-openai response
      def extract_content_ruby_openai(response)
        # ruby-openai returns a hash
        if response.is_a?(Hash)
          response.dig('choices', 0, 'message', 'content')
        else
          # Fallback for different response formats
          response.respond_to?(:dig) ? response.dig('choices', 0, 'message', 'content') : response.to_s
        end
      end

      # Extract content from openai-ruby response
      def extract_content_openai_ruby(response)
        # openai-ruby returns an object with methods
        if response.respond_to?(:choices)
          response.choices.first.message.content
        elsif response.is_a?(Hash)
          response.dig('choices', 0, 'message', 'content')
        else
          response.to_s
        end
      end
    end
  end
end
