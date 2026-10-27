# frozen_string_literal: true

require 'timeout'

module Reports
  module MarketBrief
    # Orchestrates one Market Brief build:
    #
    #   claim (pending → building)
    #     → SnapshotBuilder (deterministic)      → persist, status ready
    #     → AI gate / digest reuse / backoff
    #     → OllamaClient chat (bounded timeout)   — no DB transaction held
    #     → AiResponseValidator                   → persist ai_* fields
    #
    # The deterministic report is persisted BEFORE the LLM runs, so risk and
    # market facts are visible even when the model is slow, down or invalid.
    # Read-only with respect to trading: no gateway, order or tracker writes.
    class Generator
      AI_TIMEOUT = ENV.fetch('MARKET_BRIEF_AI_TIMEOUT', '90').to_i.seconds
      AI_BACKOFF = 5.minutes
      AI_BACKOFF_KEY = 'market_brief:ai_backoff_until'
      AI_PROVIDER = 'ollama'

      def self.call(report, force_ai: false)
        new(report, force_ai: force_ai).call
      end

      def initialize(report, force_ai: false)
        @report = report
        @force_ai = force_ai
      end

      def call
        unless @report.claim_for_build!
          Rails.logger.info("[MarketBrief::Generator] report=#{@report.id} already #{@report.status}; skipping")
          return @report
        end

        build_snapshot!
        run_ai!
        @report
      rescue StandardError => e
        Rails.logger.error("[MarketBrief::Generator] report=#{@report.id} failed: #{e.class} - #{e.message}")
        if @report.ready?
          @report.update!(ai_status: 'unavailable', ai_error: "error: #{e.class}")
        else
          @report.update!(status: 'failed', error: e.class.name)
        end
        @report
      end

      private

      def build_snapshot!
        snapshot = SnapshotBuilder.call(now: Time.current)
        @report.update!(
          snapshot: snapshot,
          snapshot_digest: SnapshotBuilder.digest(snapshot),
          snapshot_generated_at: Time.zone.parse(snapshot['generated_at']),
          status: 'ready',
          error: nil
        )
        Rails.logger.info(
          "[MarketBrief::Generator] report=#{@report.id} snapshot ready decision=#{snapshot.dig('setup', 'decision')} " \
          "freshness=#{snapshot.dig('freshness', 'state')} warnings=#{Array(snapshot['warnings']).size}"
        )
      end

      def run_ai!
        return finish_ai('disabled', error: 'ai.enabled is false') if AlgoConfig.fetch.dig(:ai, :enabled) == false

        client = Services::Ai::OllamaClient.instance
        return finish_ai('disabled', error: 'ollama_not_configured') unless client.enabled?
        return if reuse_previous_analysis!
        return finish_ai('skipped_market_closed') if Ai::GenerativeAiMarketGate.skip?(force: @force_ai)
        return finish_ai('unavailable', error: 'provider_backoff_active') if backoff_active?

        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        raw = Timeout.timeout(AI_TIMEOUT) do
          client.chat(messages: AiPromptBuilder.build(@report.snapshot), temperature: 0.1,
                      log_context: 'market_brief')
        end
        model = client.selected_model.presence || ENV.fetch('OLLAMA_MODEL', nil)

        if raw.blank?
          trip_backoff!
          # OllamaClient#chat swallows errors (including our Timeout::Error) and returns nil,
          # so a timeout is recognised by elapsed time rather than by exception.
          elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
          reason = elapsed >= AI_TIMEOUT.to_f - 0.5 ? "timeout_after_#{AI_TIMEOUT.to_i}s" : 'no_response'
          return finish_ai('unavailable', model: model, error: reason)
        end

        result = AiResponseValidator.new(@report.snapshot).call(raw)
        if result.valid?
          finish_ai('completed', model: model, analysis: result.analysis)
        else
          Rails.logger.warn("[MarketBrief::Generator] report=#{@report.id} AI output rejected: #{result.errors.join(', ')}")
          finish_ai('invalid', model: model, error: result.errors.join(', ').truncate(250))
        end
      rescue Timeout::Error
        trip_backoff!
        finish_ai('unavailable', error: "timeout_after_#{AI_TIMEOUT.to_i}s")
      end

      # Identical facts → identical interpretation; avoid a second model call.
      def reuse_previous_analysis!
        previous = MarketBriefReport.where(snapshot_digest: @report.snapshot_digest, ai_status: 'completed')
                                    .where.not(id: @report.id)
                                    .latest_first.first
        return false unless previous

        @report.update!(ai_status: 'completed', ai_model: previous.ai_model, ai_analysis: previous.ai_analysis,
                        ai_error: nil, ai_generated_at: previous.ai_generated_at)
        Rails.logger.info("[MarketBrief::Generator] report=#{@report.id} reused AI analysis from report=#{previous.id}")
        true
      end

      def backoff_active?
        until_ts = Rails.cache.read(AI_BACKOFF_KEY)
        until_ts.present? && until_ts.to_i > Time.current.to_i
      rescue StandardError
        false
      end

      def trip_backoff!
        Rails.cache.write(AI_BACKOFF_KEY, (Time.current + AI_BACKOFF).to_i, expires_in: AI_BACKOFF)
      rescue StandardError => e
        Rails.logger.warn("[MarketBrief::Generator] backoff write failed: #{e.class}")
      end

      def finish_ai(status, model: nil, analysis: nil, error: nil)
        @report.update!(
          ai_status: status,
          ai_model: model ? "#{AI_PROVIDER}:#{model}" : nil,
          ai_analysis: analysis,
          ai_error: error,
          ai_generated_at: status == 'completed' ? Time.current : nil
        )
        Rails.logger.info("[MarketBrief::Generator] report=#{@report.id} ai_status=#{status}#{" (#{error})" if error}")
      end
    end
  end
end
