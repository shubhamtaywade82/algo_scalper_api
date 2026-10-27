# frozen_string_literal: true

module Reports
  module MarketBrief
    # Event-driven Market Brief for the trading daemon (registered in TradingSystem::Bootstrap).
    #
    # During the cash session it rebuilds the deterministic snapshot every INTERVAL,
    # detects state changes and levels (EventDetector), and:
    #   * records each event in today's EventLog and pushes an event frame to the page,
    #   * when a material change happened, creates one `event` report carrying the
    #     change descriptions and enqueues the existing Market Brief job, which runs
    #     the LLM and pushes the finished analysis as a report frame.
    #
    # The LLM is never called from this process: the daemon serves the trading loop,
    # and the job runs in the job worker with its own timeout. Nothing here places,
    # modifies or cancels orders; it reads cached state and writes report rows and
    # cache entries only.
    #
    # Bounds on LLM work, all enforced from shared state so they survive a restart:
    #   * AI_DEBOUNCE: at most one event run per window; changes in between are batched
    #     into the next run, and the reasons are kept in memory until it starts,
    #   * MAX_AI_RUNS_PER_HOUR: hard cap per mode,
    #   * one in flight per mode: a new event waits while the previous run is building,
    #   * AI availability: disabled config, unavailable provider, market-closed gate and
    #     provider backoff all suppress runs (events still show on the page).
    class Watcher
      INTERVAL = 10.seconds
      IDLE_INTERVAL = 15.seconds # below the 30s heartbeat TTL
      AI_DEBOUNCE = 60.seconds
      MAX_AI_RUNS_PER_HOUR = 12
      IN_FLIGHT_WINDOW = 15.minutes # a build older than this is treated as dead, not in flight
      HEARTBEAT = :market_brief_watcher
      IST = TradingSession::Service::IST_TIMEZONE

      def initialize(detector: EventDetector.new, clock: -> { Time.current },
                     builder: ->(now) { SnapshotBuilder.call(now: now) }, broadcaster: Broadcaster)
        @detector = detector
        @clock = clock
        @builder = builder
        @broadcaster = broadcaster
        @pending_reasons = []
        @running = false
        @thread = nil
        @lock = Mutex.new
      end

      def start
        @lock.synchronize do
          return if @running

          @running = true
          @thread = Thread.new { run_loop }
        end
      end

      def stop
        @lock.synchronize do
          @running = false
          @thread&.kill
          @thread&.join(1)
          @thread = nil
        end
      end

      # One watcher cycle. Public so tests and diagnostics can drive it directly.
      #
      # @return [Hash] { status: :idle | :running, events: Integer, report_id: Integer, nil }
      def cycle
        return idle! unless cash_session_open?

        now = @clock.call
        mode = AlgoConfig.mode.to_s
        snapshot = @builder.call(now)
        events = @detector.detect(snapshot)

        if events.any?
          EventLog.append(mode, events)
          queue_reasons(events)
          @broadcaster.events(snapshot: snapshot, mode: mode, events: events, now: now)
          Rails.logger.info("[MarketBrief::Watcher] #{events.size} event(s): #{events.pluck('kind').join(', ')}")
        end

        { status: :running, events: events.size, report_id: maybe_request_ai(mode, now) }
      end

      private

      def run_loop
        Thread.current.name = 'market-brief-watcher'
        while @running
          result = safe_cycle
          Live::SystemStatusCache.instance.report_heartbeat(HEARTBEAT)
          sleep(result[:status] == :idle ? IDLE_INTERVAL : INTERVAL)
        end
      end

      def safe_cycle
        cycle
      rescue StandardError => e
        Rails.logger.error("[MarketBrief::Watcher] cycle failed: #{e.class} - #{e.message}")
        { status: :error }
      end

      def cash_session_open?
        today = @clock.call.in_time_zone(IST).to_date
        Market::Calendar.trading_day?(today) && !TradingSession::Service.market_closed?
      end

      # Outside the session the detector forgets its baseline, so the next open
      # starts clean instead of comparing against yesterday's close.
      def idle!
        @detector.reset!
        @pending_reasons.clear
        { status: :idle }
      end

      def queue_reasons(events)
        events.select { |e| EventDetector.ai_trigger?(e) }.each do |event|
          @pending_reasons << event['message']
        end
        @pending_reasons.uniq!
      end

      # @return [Integer, nil] id of the report enqueued this cycle
      # Reasons wait while a run is in flight or the debounce window is open. They are
      # dropped when AI is unavailable or the hourly cap is hit: the events themselves
      # are already on the page, and a manual refresh remains available.
      def maybe_request_ai(mode, now)
        return nil if @pending_reasons.empty?

        unless ai_available?(now)
          drop_pending('ai unavailable')
          return nil
        end
        return nil if in_flight?(mode, now) || within_debounce?(mode, now)

        if hourly_cap_reached?(mode, now)
          drop_pending('hourly cap reached')
          return nil
        end

        enqueue_event_run(mode, now)
      end

      def enqueue_event_run(mode, now)
        reasons = @pending_reasons.dup
        @pending_reasons.clear
        report, created = MarketBriefReport.request!(mode: mode, trigger: 'event', now: now, reasons: reasons)
        return nil unless created

        Reports::MarketBriefJob.perform_later(report.id, 'event', false)
        Rails.logger.info("[MarketBrief::Watcher] event run enqueued report=#{report.id} reasons=#{reasons.size}")
        report.id
      end

      def drop_pending(why)
        Rails.logger.info("[MarketBrief::Watcher] #{@pending_reasons.size} pending reason(s) dropped: #{why}")
        @pending_reasons.clear
      end

      def ai_available?(now)
        return false if AlgoConfig.fetch.dig(:ai, :enabled) == false
        return false if Ai::GenerativeAiMarketGate.skip?(force: false)
        return false if backoff_active?(now)

        Services::Ai::OllamaClient.instance.enabled?
      end

      def backoff_active?(now)
        until_ts = Rails.cache.read(Generator::AI_BACKOFF_KEY)
        until_ts.present? && until_ts.to_i > now.to_i
      rescue StandardError
        false
      end

      def in_flight?(mode, now)
        MarketBriefReport.for_mode(mode).where(status: %w[pending building])
                         .where(created_at: (now - IN_FLIGHT_WINDOW)..).exists?
      end

      def within_debounce?(mode, now)
        last = MarketBriefReport.for_mode(mode).where(trigger: 'event').latest_first.pick(:created_at)
        last.present? && now - last < AI_DEBOUNCE
      end

      def hourly_cap_reached?(mode, now)
        MarketBriefReport.for_mode(mode).where(trigger: 'event', created_at: (now - 1.hour)..).count >= MAX_AI_RUNS_PER_HOUR
      end
    end
  end
end
