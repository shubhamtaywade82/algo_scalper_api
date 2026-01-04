# frozen_string_literal: true

require 'net/http'
require 'json'

module Services
  module Ai
    # Abstraction layer for OpenAI API clients
    # Supports both ruby-openai (dev) and openai-ruby (production)
    # Also supports Ollama (local/network instances)
    #
    # CLIENT OPTIMIZATION FOR REMOTE OLLAMA:
    # - Serializes requests (mutex lock)
    # - Adds delays between requests
    # - Uses proper timeouts
    # - Prevents parallel LLM calls
    class OpenaiClient
      class << self
        def instance
          @instance ||= new
        end

        delegate :client, to: :instance

        delegate :enabled?, to: :instance
      end

      # Request serialization mutex (prevents parallel calls)
      REQUEST_MUTEX = Mutex.new

      # Delay between requests (milliseconds)
      REQUEST_DELAY_MS = ENV.fetch('OLLAMA_REQUEST_DELAY_MS', '500').to_i

      # Cache for Ollama models list (class-level, shared across instances)
      # Format: { base_url => { models: [...], fetched_at: Time } }
      @models_cache = {}
      @models_cache_mutex = Mutex.new
      MODELS_CACHE_TTL = ENV.fetch('OLLAMA_MODELS_CACHE_TTL', '300').to_i # Default: 5 minutes

      class << self
        attr_accessor :models_cache, :models_cache_mutex
      end

      # Initialize class variables
      self.models_cache = {}
      self.models_cache_mutex = Mutex.new

      def initialize
        @client = nil
        @provider = determine_provider
        @enabled = check_enabled
        @available_models = nil
        @selected_model = nil
        @last_request_time = nil
        initialize_client if @enabled
        fetch_and_select_model if @enabled && @provider == :ollama
      end

      attr_reader :client, :provider, :selected_model, :available_models

      def enabled?
        @enabled
      end

      # Get Ollama base URL (supports both OLLAMA_HOST_URL and OLLAMA_BASE_URL)
      def ollama_base_url
        ENV['OLLAMA_HOST_URL'] || ENV['OLLAMA_BASE_URL'] || 'http://localhost:11434'
      end

      # Ensure request serialization and delay (for Ollama)
      def with_request_serialization
        return yield unless @provider == :ollama

        REQUEST_MUTEX.synchronize do
          # Add delay between requests if needed
          if @last_request_time
            elapsed = (Time.current - @last_request_time) * 1000 # milliseconds
            sleep((REQUEST_DELAY_MS - elapsed) / 1000.0) if elapsed < REQUEST_DELAY_MS
          end

          @last_request_time = Time.current
          yield
        end
      end

      # Get available models from Ollama (with caching)
      def fetch_available_models
        return [] unless @provider == :ollama && @enabled

        base_url = ollama_base_url

        # Check cache first
        cached = get_cached_models(base_url)
        if cached
          Rails.logger.debug { "[OpenAIClient] Using cached models list for #{base_url}" }
          @available_models = cached
          return cached
        end

        # Cache miss or expired - fetch from API
        begin
          response = Net::HTTP.get_response(URI("#{base_url}/api/tags"))

          if response.code == '200'
            data = JSON.parse(response.body)
            models = data['models'] || []
            @available_models = models.map { |m| m['name'] }.compact

            # Cache the result
            set_cached_models(base_url, @available_models)

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

      # Get cached models for a base URL (class method)
      def self.get_cached_models(base_url)
        models_cache_mutex.synchronize do
          cached = models_cache[base_url]
          return nil unless cached

          # Check if cache is expired
          age = Time.current - cached[:fetched_at]
          if age > MODELS_CACHE_TTL
            models_cache.delete(base_url)
            return nil
          end

          cached[:models]
        end
      end

      # Set cached models for a base URL (class method)
      def self.set_cached_models(base_url, models)
        models_cache_mutex.synchronize do
          models_cache[base_url] = {
            models: models,
            fetched_at: Time.current
          }
        end
      end

      # Instance method wrappers for class methods
      delegate :get_cached_models, to: :class

      delegate :set_cached_models, to: :class

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

        # Priority order: prefer models that work well for trading analysis
        # Trading analysis requires: complex reasoning, financial understanding, structured output
        # Note: For CPU-only setups (OLLAMA_NUM_GPU=0), prefer smaller models (3B-7B)
        priority_models = [
          # 8B models (best balance: capable + fast enough for real-time analysis)
          # Note: May require GPU or 16GB+ RAM for CPU-only
          'llama3.1:8b', 'llama3.1:8b-instruct', 'llama3:8b', 'llama3:8b-instruct',
          # 7B models (good for CPU-only with 16GB RAM)
          'mistral:7b', 'mistral', 'mistral:instruct',
          # 3B models (excellent for CPU-only, good balance of speed and capability)
          'llama3.2:3b', 'llama3.2:3b-instruct', 'llama3:3b',
          # Small models (fastest for CPU-only, good for quick queries)
          'phi3:mini', 'phi3', 'phi3:medium',
          'qwen2.5:1.5b-instruct', 'gemma:2b', 'gemma',
          # Large models (best for complex analysis, but require GPU or lots of RAM)
          'llama3:70b', 'llama3:70b-instruct',
          'llama3', 'llama3:instruct',
          # Code models (not ideal for trading, but better than tiny models)
          'codellama', 'codellama:instruct',
          # Other small models
          'gemma:7b'
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
      # For Ollama: Serializes requests to prevent parallel calls
      # Returns full response object if tools are provided, otherwise returns content string
      def chat(messages:, model: nil, temperature: 0.7, tools: nil, tool_choice: nil, **)
        return nil unless enabled?

        # Auto-select model for Ollama if not provided
        model ||= if @provider == :ollama
                    @selected_model || select_best_model || ENV['OLLAMA_MODEL'] || 'llama3'
                  else
                    'gpt-4o'
                  end

        # Serialize Ollama requests to prevent parallel calls
        result = if @provider == :ollama
                   with_request_serialization do
                     execute_chat(messages: messages, model: model, temperature: temperature, tools: tools, tool_choice: tool_choice, **)
                   end
                 else
                   execute_chat(messages: messages, model: model, temperature: temperature, tools: tools, tool_choice: tool_choice, **)
                 end

        # If tools are provided, return full response hash; otherwise return content string (backward compatibility)
        if tools
          result
        else
          # Extract just the content string for backward compatibility
          result.is_a?(Hash) ? (result[:content] || result['content'] || result.to_s) : result.to_s
        end
      rescue StandardError => e
        Rails.logger.error("[OpenAIClient] Chat error: #{e.class} - #{e.message}")
        nil
      end

      # Internal chat execution (without serialization wrapper)
      def execute_chat(messages:, model:, temperature:, tools: nil, tool_choice: nil, **)
        case @provider
        when :ruby_openai
          chat_ruby_openai(messages: messages, model: model, temperature: temperature, tools: tools, tool_choice: tool_choice, **)
        when :openai_ruby
          chat_openai_ruby(messages: messages, model: model, temperature: temperature, tools: tools, tool_choice: tool_choice, **)
        when :ollama
          # Ollama uses OpenAI-compatible API, use the same client methods
          if defined?(OpenAI) && OpenAI.respond_to?(:configure)
            chat_ruby_openai(messages: messages, model: model, temperature: temperature, tools: tools, tool_choice: tool_choice, **)
          else
            chat_openai_ruby(messages: messages, model: model, temperature: temperature, tools: tools, tool_choice: tool_choice, **)
          end
        else
          raise "Unknown provider: #{@provider}"
        end
      end

      # Streaming chat completion
      # For Ollama: Serializes requests to prevent parallel calls
      # Supports tools and tool_choice for native tool calling
      def chat_stream(messages:, model: nil, temperature: 0.7, tools: nil, tool_choice: nil, &block)
        return nil unless enabled?

        # Auto-select model for Ollama if not provided
        model ||= if @provider == :ollama
                    @selected_model || select_best_model || ENV['OLLAMA_MODEL'] || 'llama3'
                  else
                    'gpt-4o'
                  end

        # Serialize Ollama requests to prevent parallel calls
        if @provider == :ollama
          with_request_serialization do
            execute_chat_stream(messages: messages, model: model, temperature: temperature, tools: tools, tool_choice: tool_choice, &block)
          end
        else
          execute_chat_stream(messages: messages, model: model, temperature: temperature, tools: tools, tool_choice: tool_choice, &block)
        end
      rescue StandardError => e
        Rails.logger.error("[OpenAIClient] Chat stream error: #{e.class} - #{e.message}")
        nil
      end

      # Internal streaming chat execution (without serialization wrapper)
      def execute_chat_stream(messages:, model:, temperature:, tools: nil, tool_choice: nil, &)
        case @provider
        when :ruby_openai
          chat_stream_ruby_openai(messages: messages, model: model, temperature: temperature, tools: tools, tool_choice: tool_choice, &)
        when :openai_ruby
          chat_stream_openai_ruby(messages: messages, model: model, temperature: temperature, tools: tools, tool_choice: tool_choice, &)
        when :ollama
          # Ollama uses OpenAI-compatible API, use the same client methods
          if defined?(OpenAI) && OpenAI.respond_to?(:configure)
            chat_stream_ruby_openai(messages: messages, model: model, temperature: temperature, tools: tools, tool_choice: tool_choice, &)
          else
            chat_stream_openai_ruby(messages: messages, model: model, temperature: temperature, tools: tools, tool_choice: tool_choice, &)
          end
        else
          raise "Unknown provider: #{@provider}"
        end
      end

      private

      def determine_provider
        # Check environment variable first, then fall back to Rails.env
        provider_env = ENV['OPENAI_PROVIDER']&.downcase&.to_sym

        # Check if Ollama is configured (supports both OLLAMA_HOST_URL and OLLAMA_BASE_URL)
        return :ollama if ENV['OLLAMA_HOST_URL'].present? || ENV['OLLAMA_BASE_URL'].present?

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

        # Ollama doesn't require API key, check base URL instead (supports both OLLAMA_HOST_URL and OLLAMA_BASE_URL)
        if @provider == :ollama
          unless ENV['OLLAMA_HOST_URL'].present? || ENV['OLLAMA_BASE_URL'].present?
            Rails.logger.warn('[OpenAIClient] Ollama base URL not configured (OLLAMA_HOST_URL or OLLAMA_BASE_URL)')
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

        base_url = ollama_base_url
        api_key = ENV['OLLAMA_API_KEY'] || 'ollama' # Ollama doesn't require auth, but some clients expect a key

        # Optimized timeouts for remote Ollama server
        # Default: 20s for non-streaming chat
        # Connection timeout: 5s (fast failure if server unreachable)
        # Note: Streaming requests have no application-level timeout (streams run until completion)
        # HTTP client still has request_timeout for connection management (prevents truly hung connections)
        request_timeout = ENV.fetch('OLLAMA_TIMEOUT', '20').to_i # Default 20s for non-streaming
        # Use a high timeout for HTTP client to allow long-running streams (1 hour default)
        http_client_timeout = ENV.fetch('OLLAMA_HTTP_TIMEOUT', '3600').to_i # Default 3600s (1 hour) for HTTP client
        open_timeout = ENV.fetch('OLLAMA_OPEN_TIMEOUT', '5').to_i # Default 5s for connection

        # Store timeouts (stream_timeout no longer used for application-level timeout)
        @request_timeout = request_timeout

        # Use ruby-openai if available (better Ollama support)
        if defined?(OpenAI) && OpenAI.respond_to?(:configure)
          OpenAI.configure do |config|
            config.access_token = api_key
            config.uri_base = "#{base_url}/v1" # Ollama uses /v1 prefix
            config.log_errors = Rails.env.development?
            # Configure optimized timeouts for remote server
            # Use high timeout to allow long-running streams (no application-level timeout)
            config.request_timeout = http_client_timeout # High timeout for HTTP client (allows long streams)
            config.open_timeout = open_timeout if config.respond_to?(:open_timeout=)
          end
          @client = OpenAI::Client.new
        else
          # Fallback to openai-ruby
          @client = OpenAI::Client.new(
            api_key: api_key,
            uri_base: "#{base_url}/v1",
            request_timeout: http_client_timeout # High timeout for HTTP client (allows long streams)
          )
          # NOTE: openai-ruby may not support open_timeout directly
        end

        Rails.logger.info("[OpenAIClient] Connected to Ollama at #{base_url}")
      end

      # Chat completion using ruby-openai
      def chat_ruby_openai(messages:, model:, temperature:, tools: nil, tool_choice: nil, **options)
        formatted_messages = format_messages_ruby_openai(messages)
        token_count = estimate_token_count(formatted_messages)

        # Log prompt and token count
        log_prompt_and_tokens(messages: formatted_messages, model: model, token_count: token_count)

        parameters = {
          model: model,
          messages: formatted_messages,
          temperature: temperature
        }

        # Add tools if provided (for native tool calling)
        parameters[:tools] = tools if tools
        parameters[:tool_choice] = tool_choice if tool_choice

        response = @client.chat(parameters: parameters.merge(options))

        # Return full response hash if tools were used, otherwise extract content string
        if tools
          extract_content_ruby_openai(response)
        else
          # Backward compatibility: return just the content string
          content_data = extract_content_ruby_openai(response)
          content_data.is_a?(Hash) ? content_data[:content] : content_data.to_s
        end
      end

      # Chat completion using openai-ruby
      def chat_openai_ruby(messages:, model:, temperature:, tools: nil, tool_choice: nil, **)
        formatted_messages = format_messages_openai_ruby(messages)
        token_count = estimate_token_count(formatted_messages)

        # Log prompt and token count
        log_prompt_and_tokens(messages: formatted_messages, model: model, token_count: token_count)

        params = {
          messages: formatted_messages,
          model: model,
          temperature: temperature
        }

        # Add tools if provided (for native tool calling)
        params[:tools] = tools if tools
        params[:tool_choice] = tool_choice if tool_choice

        response = @client.chat.completions.create(**params.merge(**))

        # Return full response hash if tools were used, otherwise extract content string
        if tools
          extract_content_openai_ruby(response)
        else
          # Backward compatibility: return just the content string
          content_data = extract_content_openai_ruby(response)
          content_data.is_a?(Hash) ? content_data[:content] : content_data.to_s
        end
      end

      # Streaming chat using ruby-openai
      def chat_stream_ruby_openai(messages:, model:, temperature:, tools: nil, tool_choice: nil, &block)
        stream_start = Time.current
        chunk_count = 0

        formatted_messages = format_messages_ruby_openai(messages)
        token_count = estimate_token_count(formatted_messages)

        # Log prompt and token count
        log_prompt_and_tokens(messages: formatted_messages, model: model, token_count: token_count)

        begin
          parameters = {
            model: model,
            messages: formatted_messages,
            temperature: temperature
          }

          # Add tools if provided (for native tool calling)
          parameters[:tools] = tools if tools
          parameters[:tool_choice] = tool_choice if tool_choice

          # No timeout wrapper - let stream run until completion or natural connection timeout
          @client.chat(
            parameters: parameters.merge(
              stream: proc do |chunk, _event|
                content = chunk.dig('choices', 0, 'delta', 'content')
                if content.present? && block
                  chunk_count += 1
                  yield(content)
                end
              end
            )
          )

          elapsed = Time.current - stream_start
          Rails.logger.debug { "[OpenAIClient] Stream completed in #{elapsed.round(2)}s (#{chunk_count} chunks)" }
        rescue Faraday::TimeoutError, Net::ReadTimeout => e
          elapsed = Time.current - stream_start
          # Connection-level timeout errors (from HTTP client) - log but don't fail if we got some content
          Rails.logger.warn("[OpenAIClient] Stream connection timeout after #{elapsed.round(2)}s: #{e.class} - #{e.message} (#{chunk_count} chunks received)")
          # Return nil to indicate partial stream
          nil
        rescue StandardError => e
          elapsed = Time.current - stream_start
          # Some streaming implementations may raise errors on stream end
          # This is expected behavior for some providers
          if e.message.include?('end of file') || e.message.include?('Connection') || e.message.include?('closed')
            Rails.logger.debug { "[OpenAIClient] Stream ended normally after #{elapsed.round(2)}s: #{e.class} (#{chunk_count} chunks)" } if Rails.env.development?
            nil
          else
            Rails.logger.error("[OpenAIClient] Stream error after #{elapsed.round(2)}s: #{e.class} - #{e.message} (#{chunk_count} chunks)")
            Rails.logger.error("[OpenAIClient] Backtrace: #{e.backtrace.first(3).join("\n")}")
            raise
          end
        end
      end

      # Streaming chat using openai-ruby
      def chat_stream_openai_ruby(messages:, model:, temperature:, tools: nil, tool_choice: nil, &block)
        stream_start = Time.current
        chunk_count = 0

        formatted_messages = format_messages_openai_ruby(messages)
        token_count = estimate_token_count(formatted_messages)

        # Log prompt and token count
        log_prompt_and_tokens(messages: formatted_messages, model: model, token_count: token_count)

        begin
          params = {
            messages: formatted_messages,
            model: model,
            temperature: temperature,
            stream: true
          }

          # Add tools if provided (for native tool calling)
          params[:tools] = tools if tools
          params[:tool_choice] = tool_choice if tool_choice

          # No timeout wrapper - let stream run until completion or natural connection timeout
          stream = @client.chat.completions.create(**params)

          stream.each do |event|
            content = event.dig('choices', 0, 'delta', 'content')
            next unless content.present?

            chunk_count += 1
            yield(content) if block
          end

          elapsed = Time.current - stream_start
          Rails.logger.debug { "[OpenAIClient] Stream completed in #{elapsed.round(2)}s (#{chunk_count} chunks)" }
        rescue Faraday::TimeoutError, Net::ReadTimeout => e
          elapsed = Time.current - stream_start
          # Connection-level timeout errors (from HTTP client) - log but don't fail if we got some content
          Rails.logger.warn("[OpenAIClient] Stream connection timeout after #{elapsed.round(2)}s: #{e.class} - #{e.message} (#{chunk_count} chunks received)")
          nil
        rescue StandardError => e
          elapsed = Time.current - stream_start
          if e.message.include?('end of file') || e.message.include?('Connection') || e.message.include?('closed')
            Rails.logger.debug { "[OpenAIClient] Stream ended normally after #{elapsed.round(2)}s: #{e.class} (#{chunk_count} chunks)" } if Rails.env.development?
            nil
          else
            Rails.logger.error("[OpenAIClient] Stream error after #{elapsed.round(2)}s: #{e.class} - #{e.message} (#{chunk_count} chunks)")
            Rails.logger.error("[OpenAIClient] Backtrace: #{e.backtrace.first(3).join("\n")}")
            raise
          end
        end
      end

      # Format messages for ruby-openai (expects array of hashes)
      # Handles tool_calls and tool messages for native tool calling
      def format_messages_ruby_openai(messages)
        messages.map do |msg|
          if msg.is_a?(Hash)
            formatted = { role: msg[:role] || msg['role'] }

            # Handle content (can be nil for tool calls)
            content = msg[:content] || msg['content']
            formatted[:content] = content if content

            # Handle tool_calls (assistant messages with tool calls)
            if (tool_calls = msg[:tool_calls] || msg['tool_calls'])
              formatted[:tool_calls] = tool_calls
            end

            # Handle tool messages (tool role with tool_call_id)
            if (tool_call_id = msg[:tool_call_id] || msg['tool_call_id'])
              formatted[:tool_call_id] = tool_call_id
            end

            # Handle tool name
            if (tool_name = msg[:name] || msg['name'])
              formatted[:name] = tool_name
            end

            formatted
          else
            msg
          end
        end
      end

      # Format messages for openai-ruby (expects array of hashes with symbol keys)
      # Handles tool_calls and tool messages for native tool calling
      def format_messages_openai_ruby(messages)
        messages.map do |msg|
          if msg.is_a?(Hash)
            formatted = { role: (msg[:role] || msg['role']).to_sym }

            # Handle content (can be nil for tool calls)
            content = msg[:content] || msg['content']
            formatted[:content] = content if content

            # Handle tool_calls (assistant messages with tool calls)
            if (tool_calls = msg[:tool_calls] || msg['tool_calls'])
              formatted[:tool_calls] = tool_calls
            end

            # Handle tool messages (tool role with tool_call_id)
            if (tool_call_id = msg[:tool_call_id] || msg['tool_call_id'])
              formatted[:tool_call_id] = tool_call_id
            end

            # Handle tool name
            if (tool_name = msg[:name] || msg['name'])
              formatted[:name] = tool_name
            end

            formatted
          else
            msg
          end
        end
      end

      # Extract content from ruby-openai response
      # Also extracts tool_calls if present
      def extract_content_ruby_openai(response)
        # ruby-openai returns a hash
        if response.is_a?(Hash)
          message = response.dig('choices', 0, 'message') || {}
          {
            content: message['content'],
            tool_calls: message['tool_calls']
          }
        else
          # Fallback for different response formats
          if response.respond_to?(:dig)
            message = response.dig('choices', 0, 'message') || {}
            {
              content: message['content'],
              tool_calls: message['tool_calls']
            }
          else
            { content: response.to_s, tool_calls: nil }
          end
        end
      end

      # Extract content from openai-ruby response
      # Also extracts tool_calls if present
      def extract_content_openai_ruby(response)
        # openai-ruby returns an object with methods
        if response.respond_to?(:choices)
          message = response.choices.first.message
          {
            content: message.content,
            tool_calls: message.tool_calls&.map(&:to_h) || message.respond_to?(:tool_calls) ? message.tool_calls : nil
          }
        elsif response.is_a?(Hash)
          message = response.dig('choices', 0, 'message') || {}
          {
            content: message['content'],
            tool_calls: message['tool_calls']
          }
        else
          { content: response.to_s, tool_calls: nil }
        end
      end

      # Estimate token count from messages
      # Uses approximation: 1 token ≈ 4 characters (common for English text)
      # This is a rough estimate - actual tokenization varies by model
      def estimate_token_count(messages)
        return 0 unless messages.is_a?(Array)

        total_chars = messages.sum do |msg|
          content = msg[:content] || msg['content'] || ''
          role = msg[:role] || msg['role'] || ''
          # Count characters in content and role
          content.to_s.length + role.to_s.length + 4 # +4 for message structure overhead
        end

        # Rough approximation: 1 token ≈ 4 characters
        # Add some overhead for message structure (role tags, etc.)
        (total_chars / 4.0).ceil + (messages.length * 2)
      end

      # Log prompt and token count
      def log_prompt_and_tokens(messages:, model:, token_count:)
        # Build a summary of messages for logging (no truncation by default)
        message_summary = messages.map do |msg|
          role = msg[:role] || msg['role'] || 'unknown'
          content = msg[:content] || msg['content'] || ''
          "#{role}: #{content}"
        end.join("\n")

        Rails.logger.info("[OpenAIClient] Sending prompt to #{model}")
        Rails.logger.info("[OpenAIClient] Estimated token count: #{token_count}")
        Rails.logger.debug { "[OpenAIClient] Prompt messages:\n#{message_summary}" }
      end
    end
  end
end
