# frozen_string_literal: true

require 'open3'
require 'timeout'

module Graphify
  class ContextService
    GRAPH_PATH = Rails.root.join('graphify-out/graph.json')
    DEFAULT_BUDGET = ENV.fetch('GRAPHIFY_TOKEN_BUDGET', 2000).to_i
    DEFAULT_TIMEOUT = ENV.fetch('GRAPHIFY_QUERY_TIMEOUT', 3).to_i
    SANITIZE_PATTERN = /["`$]/

    class << self
      def enabled?
        GRAPH_PATH.exist?
      end

      def fetch(prompt, domain: 'algo_scalper trading', budget: DEFAULT_BUDGET)
        return '' unless enabled?

        query = build_query(prompt, domain)
        run_command(
          'query',
          query,
          '--graph', GRAPH_PATH.to_s,
          '--budget', budget.to_s
        )
      end

      def path(from, to)
        return '' unless enabled?

        run_command(
          'path',
          sanitize(from),
          sanitize(to),
          '--graph', GRAPH_PATH.to_s
        )
      end

      def explain(concept)
        return '' unless enabled?

        run_command(
          'explain',
          sanitize(concept),
          '--graph', GRAPH_PATH.to_s
        )
      end

      private

      def build_query(prompt, domain)
        sanitize("#{prompt} #{domain} Rails")
      end

      def sanitize(value)
        value.to_s.gsub(SANITIZE_PATTERN, '').first(200)
      end

      def run_command(*args)
        started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        stdout, stderr, status = Timeout.timeout(DEFAULT_TIMEOUT) do
          Open3.capture3('graphify', *args)
        end
        elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round

        unless status.success?
          Rails.logger.warn(
            "[Graphify::ContextService] command=graphify #{args.first} " \
            "exit=#{status.exitstatus} elapsed_ms=#{elapsed_ms} stderr=#{stderr.to_s.strip}"
          )
          return ''
        end

        Rails.logger.info(
          "[Graphify::ContextService] command=graphify #{args.first} " \
          "elapsed_ms=#{elapsed_ms} bytes=#{stdout.bytesize}"
        )
        stdout.strip
      rescue Timeout::Error
        Rails.logger.warn("[Graphify::ContextService] command=graphify #{args.first} timed out")
        ''
      rescue Errno::ENOENT
        Rails.logger.warn('[Graphify::ContextService] graphify CLI not found')
        ''
      end
    end
  end
end
