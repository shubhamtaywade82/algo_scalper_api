# frozen_string_literal: true

module Reports
  module MarketBrief
    # Realtime view for the Market Mood / Market Brief page.
    #
    # One payload shape serves three callers: the live endpoint (rebuilds facts per
    # poll, cached briefly), the watcher's event frames and the generator's report
    # frames (both pass the snapshot they already built). The LLM is never called
    # here. AI commentary is the latest validated analysis for the trading date,
    # with explicit staleness and decision-change flags so old commentary is never
    # shown as an interpretation of the current facts.
    class LiveBrief
      CACHE_TTL = 3.seconds
      STALE_AI_AFTER = 20.minutes

      class << self
        def call(mode: AlgoConfig.mode, now: Time.current)
          new(mode: mode, now: now).call
        end

        def payload_for(snapshot:, mode: AlgoConfig.mode, now: Time.current)
          new(mode: mode, now: now).payload_for(snapshot)
        end
      end

      def initialize(mode:, now:)
        @mode = mode.to_s
        @now = now
      end

      def call
        payload_for(cached_snapshot)
      end

      def payload_for(snapshot)
        trading_date = snapshot['trading_date']
        analysis_report = MarketBriefReport.for_mode(@mode).where(ai_status: 'completed', trading_date: trading_date)
                                           .latest_first.first
        latest_attempt = MarketBriefReport.for_mode(@mode).ready.where(trading_date: trading_date).latest_first.first
        in_flight = MarketBriefReport.for_mode(@mode).where(status: %w[pending building]).latest_first.first

        {
          live: true,
          mode: @mode,
          fetched_at: @now.iso8601,
          snapshot: snapshot,
          snapshot_digest: SnapshotBuilder.digest(snapshot),
          ai: ai_block(snapshot, analysis_report, latest_attempt),
          in_progress: in_flight && in_progress_block(in_flight),
          events: EventLog.recent(@mode, today: trading_date_for(trading_date))
        }
      end

      private

      def cached_snapshot
        Rails.cache.fetch("market_brief:live_snapshot:#{@mode}", expires_in: CACHE_TTL) do
          SnapshotBuilder.call(now: @now)
        end
      rescue StandardError => e
        # A cache-store failure must not take the live page down; build uncached.
        Rails.logger.warn("[MarketBrief::LiveBrief] cache unavailable: #{e.class}")
        SnapshotBuilder.call(now: @now)
      end

      def trading_date_for(iso_date)
        Date.parse(iso_date.to_s)
      rescue Date::Error
        @now.in_time_zone(TradingSession::Service::IST_TIMEZONE).to_date
      end

      def in_progress_block(report)
        {
          id: report.id,
          status: report.status,
          trigger: report.trigger,
          reasons: report.trigger_reasons,
          created_at: report.created_at.iso8601
        }
      end

      # status/analysis describe the commentary on screen; latest_attempt describes the
      # most recent generation attempt (which may have failed after a success).
      def ai_block(snapshot, analysis_report, latest_attempt)
        attempt = latest_attempt && {
          report_id: latest_attempt.id,
          status: latest_attempt.ai_status,
          error: latest_attempt.ai_error,
          at: latest_attempt.updated_at&.iso8601
        }
        unless analysis_report
          # Never report 'completed' without commentary to show.
          status = latest_attempt && latest_attempt.ai_status != 'completed' ? latest_attempt.ai_status : 'unavailable'
          return { status: status, analysis: nil,
                   error: latest_attempt&.ai_error || 'no_analysis_generated_today', latest_attempt: attempt }
        end

        based_on = analysis_report.snapshot_generated_at
        age = based_on ? (@now - based_on).round : nil
        live_decision = snapshot.dig('setup', 'decision')
        ai_decision = analysis_report.snapshot.dig('setup', 'decision')

        {
          status: 'completed',
          analysis: analysis_report.ai_analysis,
          model: analysis_report.ai_model,
          generated_at: analysis_report.ai_generated_at&.iso8601,
          report_id: analysis_report.id,
          trigger: analysis_report.trigger,
          trigger_reasons: analysis_report.trigger_reasons,
          based_on_snapshot_at: based_on&.iso8601,
          age_seconds: age,
          stale: age.nil? || age > STALE_AI_AFTER.to_i,
          facts_changed: analysis_report.snapshot_digest != SnapshotBuilder.digest(snapshot),
          decision_at_analysis: ai_decision,
          decision_changed: ai_decision != live_decision,
          latest_attempt: attempt
        }
      end
    end
  end
end
