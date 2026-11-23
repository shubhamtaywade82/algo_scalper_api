# frozen_string_literal: true

require 'json'
require 'net/http'
require 'time'
require 'uri'

module Services
  module Ai
    # Client for Ollama decision models (System One, `POST /v1/systemone`).
    #
    # A decision model does not write an answer. It scores typed questions against a
    # state and returns probabilities, so a yes/no question costs one pass that
    # generates no tokens, where a chat completion has to write (and the caller has
    # to parse) a one-word reply. It talks to the endpoint over Net::HTTP because the
    # ollama-client gem has no System One method.
    #
    # Host and key come from Services::Ai::OllamaClient, so `ai.ollama_use_cloud`,
    # OLLAMA_*_URL and OLLAMA_API_KEY mean the same here as for chat.
    #
    # Env:
    #   OLLAMA_DECISION_MODEL   decision model to use; unset switches this client off
    #   OLLAMA_DECISION_TIMEOUT connect and read timeout per attempt, seconds (default 5)
    class DecisionClient
      class Error < StandardError
        attr_reader :status, :retryable, :retry_after

        # retry_after: seconds the server asked to wait (a 429 Retry-After), or nil.
        def initialize(message, status: nil, retryable: false, retry_after: nil)
          @status      = status
          @retryable   = retryable
          @retry_after = retry_after
          super(message)
        end
      end

      # A scored noul question: the probability that it is true, and what the pass cost.
      Score = Data.define(:probability, :input_tokens)

      MAX_ATTEMPTS = 3
      # Seconds for connecting and for reading, per attempt.
      REQUEST_TIMEOUT = Integer(ENV.fetch('OLLAMA_DECISION_TIMEOUT', '5'))
      # 400, 401, 402, 404 and 413 are the server's final answer and are never retried.
      RETRYABLE_STATUS = [408, 429, 500, 502, 503, 504].freeze
      MAX_RETRY_DELAY = 5.0
      LOCAL_RETRY_DELAY = 3
      QUESTION_KEY = 'question'

      class << self
        def instance
          @instance ||= new
        end

        def reset_instance!
          @instance = nil
        end

        # The configured decision model, or nil when there is none.
        def model
          ENV['OLLAMA_DECISION_MODEL'].presence
        end
      end

      delegate :model, to: :'self.class'

      # Shares the chat client's conditions: AI switched on, and a key when on the cloud.
      def enabled?
        Services::Ai::OllamaClient.instance.enabled?
      end

      # Scores +questions+ against +state+ with the configured model. Returns the parsed
      # reply (`model`, `answers`, `usage`). Raises Error; retryable ones are retried up
      # to MAX_ATTEMPTS times.
      def ask(state:, questions:)
        attempt = 0
        begin
          attempt += 1
          perform(state: state, questions: questions)
        rescue Error => e
          raise if attempt >= MAX_ATTEMPTS || !e.retryable

          wait = e.retry_after || backoff_seconds(attempt)
          Rails.logger.warn("[DecisionClient] Retrying (#{attempt}/#{MAX_ATTEMPTS}) in #{wait}s: #{e.message}")
          sleep(wait)
          retry
        end
      end

      # Probability (0.0..1.0) that the noul +question+ is true for +state+.
      def probability(state:, question:)
        reply  = ask(state: state, questions: { QUESTION_KEY => question })
        answer = reply.dig('answers', QUESTION_KEY)
        noul   = answer.is_a?(Hash) ? answer['noul'] : nil
        unless noul.is_a?(Numeric) && noul.between?(0, 1)
          raise Error, "reply is not a noul probability: #{answer.inspect}"
        end

        input_tokens = reply.dig('usage', 'input_tokens')
        Score.new(probability: noul.to_f, input_tokens: input_tokens.is_a?(Numeric) ? input_tokens : nil)
      end

      private

      def perform(state:, questions:)
        uri  = URI.join("#{base_url}/", 'v1/systemone')
        body = { model: model, state: state, questions: questions }
        # keep_alive only pins a model in local VRAM; the cloud tier is serverless.
        body[:keep_alive] = Services::Ai::OllamaClient::LOCAL_KEEP_ALIVE unless cloud?

        request = Net::HTTP::Post.new(uri)
        request['Content-Type'] = 'application/json'
        request['Authorization'] = "Bearer #{ENV['OLLAMA_API_KEY'].to_s.strip}" if cloud?
        request.body = body.to_json

        response = Net::HTTP.start(
          uri.host, uri.port,
          use_ssl: uri.scheme == 'https',
          open_timeout: REQUEST_TIMEOUT,
          read_timeout: REQUEST_TIMEOUT
        ) do |http|
          http.request(request)
        end
        parse(response)
      rescue Error
        raise
      rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error
        # The attempt already spent its whole budget, so it is not retried.
        raise Error, "no reply within #{REQUEST_TIMEOUT}s"
      rescue StandardError => e
        raise Error.new("#{e.class}: #{e.message}", retryable: true)
      end

      def parse(response)
        return parse_answers(response.body) if response.is_a?(Net::HTTPSuccess)

        code = response.code.to_i
        raise Error.new("HTTP #{code}: #{error_detail(response.body)}",
                        status: code,
                        retryable: RETRYABLE_STATUS.include?(code),
                        retry_after: retry_after_seconds(response['Retry-After']))
      end

      def parse_answers(body)
        parsed  = JSON.parse(body.to_s)
        answers = parsed.is_a?(Hash) ? parsed['answers'] : nil
        raise Error, "reply has no answers: #{body.to_s.truncate(120)}" unless answers.is_a?(Hash)

        parsed
      rescue JSON::ParserError
        raise Error, "reply is not JSON: #{body.to_s.truncate(80)}"
      end

      # The server's own words when it sent any, for example 402's "Add usage credits or upgrade".
      def error_detail(body)
        detail = JSON.parse(body.to_s)['error']
        detail.is_a?(String) && detail.present? ? detail.truncate(160) : body.to_s.truncate(160)
      rescue JSON::ParserError, TypeError
        body.to_s.truncate(160)
      end

      # Retry-After is delay seconds or an HTTP date; nil when absent, unreadable or past.
      def retry_after_seconds(header)
        return if header.blank?

        seconds = begin
          Float(header)
        rescue ArgumentError
          Time.httpdate(header) - Time.now
        end
        seconds.positive? ? [seconds, MAX_RETRY_DELAY].min : nil
      rescue ArgumentError
        nil
      end

      # Same shape as OllamaClient#chat_with_retry: exponential from OLLAMA_CLOUD_RETRY_BASE
      # on the cloud, a flat wait for the local daemon.
      def backoff_seconds(attempt)
        if cloud?
          [Services::Ai::OllamaClient::CLOUD_RETRY_BASE * (2**(attempt - 1)), MAX_RETRY_DELAY].min
        else
          LOCAL_RETRY_DELAY
        end
      end

      def base_url
        Services::Ai::OllamaClient.instance.ollama_base_url.to_s.chomp('/')
      end

      def cloud?
        Services::Ai::OllamaClient.instance.cloud?
      end
    end
  end
end
