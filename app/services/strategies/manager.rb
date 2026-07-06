# frozen_string_literal: true

module Strategies
  # Replaces Signal::Scheduler with per-strategy lifecycle management.
  #
  # Registered as :strategy_manager in the trading daemon supervisor. One
  # control-loop thread (every ~2s) reconciles desired_status against actual
  # runner state. Each running strategy gets its own runner thread fed by
  # Core::EventBus :candle_closed events.
  #
  # See docs/infra-strategy-setup/05_runtime_manager.md
  class Manager
    CONTROL_LOOP_PERIOD = 2
    HEARTBEAT_INTERVAL  = 10
    ERROR_LIMIT         = 5
    ERROR_WINDOW        = 10 * 60
    BACKOFF_CAP         = 60

    attr_reader :runners

    def initialize(context_builder: nil)
      @context_builder = context_builder || ContextBuilder.new
      @runners = {} # slug => RunnerState
      @running = false
      @mutex = Mutex.new
      @bus = Core::EventBus.instance
      @log_streams = {} # slug => LogStream
    end

    def start
      return if @running

      @running = true
      @control_thread = Thread.new { control_loop }
      subscribe_to_events
      Rails.logger.info("[Strategies::Manager] started")
    end

    def stop
      @running = false
      @bus.unsubscribe_all(self) if defined?(@bus)
      @control_thread&.kill
      @mutex.synchronize { @runners.each_key { |slug| stop_runner(slug, "shutdown") } }
      Rails.logger.info("[Strategies::Manager] stopped")
    end

    def healthy?
      @running && @control_thread&.alive?
    end

    def runner_status(slug)
      @mutex.synchronize do
        state = @runners[slug]
        next nil unless state

        {
          status: state[:status],
          version_id: state[:version_id],
          thread_alive: state[:thread]&.alive?,
          last_heartbeat: state[:last_heartbeat],
          error_count: state[:errors],
          backoff_until: state[:backoff_until]
        }
      end
    end

    def all_statuses
      @mutex.synchronize do
        @runners.transform_keys { |slug| runner_status(slug) }.keys.index_with { |s| runner_status(s) }
      end
    end

    private

    def control_loop
      while @running
        reconcile
        heartbeat_runners
        sleep CONTROL_LOOP_PERIOD
      end
    rescue StandardError => e
      Rails.logger.error("[Strategies::Manager] control loop crashed: #{e.class} - #{e.message}")
      @running = false
    end

    def reconcile
      Strategies::Record.where(status: %w[running deployed]).find_each do |strategy_record|
        desired = strategy_record.desired_status || strategy_record.status
        actual = @mutex.synchronize { @runners.key?(strategy_record.slug) }

        if desired == "running" && !actual
          start_runner(strategy_record)
        elsif desired != "running" && actual
          @mutex.synchronize { stop_runner(strategy_record.slug, desired) }
        end

        if desired == "running" && strategy_record.status != "running"
          strategy_record.update!(status: "running")
          @bus.publish(:strategy_status_change,
                       slug: strategy_record.slug, status: "running")
        end
      end
    end

    def heartbeat_runners
      now = Time.current.to_i
      @mutex.synchronize do
        @runners.each do |slug, state|
          next unless state[:thread]&.alive?
          next if (now - (state[:last_heartbeat] || 0)) < HEARTBEAT_INTERVAL

          state[:last_heartbeat] = now
          state[:run]&.update_column(:stats, state[:run].stats.merge(last_heartbeat: now)) # rubocop:disable Rails/SkipsModelValidations
          broadcast_heartbeat(slug, "running")
        end
      end
    end

    def broadcast_heartbeat(slug, status)
      state = @runners[slug]
      return unless state

      ActionCable.server.broadcast("strategy_status", {
        slug: slug,
        status: status,
        heartbeat_at: Time.current.iso8601,
        error_count: state[:errors]
      })
    rescue StandardError => e
      Rails.logger.warn("[Strategies::Manager] broadcast_heartbeat failed for #{slug}: #{e.message}")
    end

    def subscribe_to_events
      @bus.subscribe(:candle_closed, self, method_name: :on_candle_closed)
    end

    def on_candle_closed(event)
      instrument_key = event[:instrument_key]
      @mutex.synchronize do
        @runners.each_value do |state|
          next unless state[:thread]&.alive?
          next unless strategy_covers_instrument?(state, instrument_key)

          state[:pending_events] << event
        end
      end
    end

    def start_runner(strategy_record)
      version = strategy_record.current_version
      return unless version

      strategy_class = Loader.load_version(version)
      strategy_instance = strategy_class.new

      log_stream = LogStream.new(strategy_record.slug)
      @context_builder.logger = log_stream

      run_record = strategy_record.runs.create!(
        strategy_version: version,
        started_at: Time.current,
        stats: { last_heartbeat: Time.current.to_i }
      )

      state = {
        status: "starting",
        thread: nil,
        version_id: version.id,
        strategy: strategy_instance,
        run: run_record,
        log_stream: log_stream,
        errors: [],
        error_timestamps: [],
        backoff_until: nil,
        last_heartbeat: Time.current.to_i,
        pending_events: Queue.new
      }

      thread = Thread.new(state, strategy_record.slug) { |s, slug| runner_loop(s, slug) }
      state[:thread] = thread
      state[:status] = "running"

      @mutex.synchronize { @runners[strategy_record.slug] = state }
      @log_streams[strategy_record.slug] = log_stream

      @bus.publish(:strategy_status_change,
                   slug: strategy_record.slug, status: "running",
                   version_id: version.id,
                   run_id: run_record.id)
      broadcast_heartbeat(strategy_record.slug, "running")
      log_stream.info("Runner started (v#{version.version})")
    end

    def stop_runner(slug, reason)
      state = @runners[slug]
      return unless state

      state[:status] = "stopping"
      state[:log_stream]&.info("Runner stopping (#{reason})")
      state[:thread]&.kill

      state[:run]&.update!(
        stopped_at: Time.current,
        stop_reason: reason,
        stats: state[:run].stats.merge(
          final_error_count: state[:errors],
          last_heartbeat: Time.current.to_i
        )
      )

      Runtime.remove(slug.camelize)

      @runners.delete(slug)
      @log_streams.delete(slug)
      @bus.publish(:strategy_status_change, slug: slug, status: "stopped", reason: reason)
      broadcast_heartbeat(slug, "stopped")
    end

    def runner_loop(state, slug)
      while @running && state[:status] == "running"
        event = state[:pending_events].pop(true)
        handle_event(state, slug, event)
      end
    rescue ThreadError
      # Queue empty — sleep and retry
      sleep 0.5
      retry
    rescue StandardError => e
      handle_crash(state, slug, e)
    end

    def handle_event(state, slug, event)
      instrument_key = event[:instrument_key]
      instrument = Instrument.find_by(symbol_name: instrument_key)
      return unless instrument

      # Check circuit breaker
      if Risk::CircuitBreaker.instance.tripped?
        state[:log_stream]&.warn("Circuit breaker tripped — skipping #{instrument_key}")
        return
      end

      context = @context_builder.build(
        instrument: instrument,
        strategy: state[:strategy],
        params: resolve_params(state[:strategy]),
        config: {}
      )

      signal = state[:strategy].call(context)
      state[:log_stream]&.info("#{instrument_key} → #{signal.class.name.demodulize}")

      persist_signal(state, slug, instrument_key, signal)
    rescue StandardError => e
      state[:log_stream]&.error("#{instrument_key} error: #{e.message}")
      handle_crash(state, slug, e)
    end

    def persist_signal(state, slug, instrument_key, signal)
      action = signal.class.name.demodulize.underscore

      Strategies::Signal.create!(
        strategy_id: Strategies::Record.find_by(slug: slug)&.id,
        strategy_version_id: state[:version_id],
        strategy_run_id: state[:run]&.id,
        instrument_key: instrument_key,
        action: action,
        confidence: signal.respond_to?(:confidence) ? signal.confidence : nil,
        reason: signal.respond_to?(:reason) ? signal.reason : nil,
        outcome: "shadow",
        emitted_at: Time.current
      )

      @bus.publish(:strategy_signal,
                   slug: slug, instrument_key: instrument_key,
                   action: action, confidence: signal.try(:confidence))
    end

    def handle_crash(state, slug, exception)
      state[:errors] += 1
      state[:error_timestamps] << Time.current.to_i
      state[:error_timestamps].reject! { |t| t < Time.current.to_i - ERROR_WINDOW }

      state[:log_stream]&.error("Crash ##{state[:errors]}: #{exception.message}")

      state[:run]&.update_column(:stats, state[:run].stats.merge( # rubocop:disable Rails/SkipsModelValidations
                                   error_count: state[:errors],
                                   last_error: exception.message,
                                   last_error_at: Time.current.to_s
                                 ))

      @bus.publish(:strategy_error, slug: slug, error: exception.message)

      if state[:errors] >= ERROR_LIMIT && state[:error_timestamps].size >= ERROR_LIMIT
        state[:log_stream]&.error("Error limit reached — auto-stopping")
        @mutex.synchronize do
          stop_runner(slug, "error_limit")
          Strategies::Record.find_by(slug: slug)&.update!(status: "errored")
        end
        return
      end

      backoff = [2**(state[:errors] - 1), BACKOFF_CAP].min
      state[:backoff_until] = Time.current.to_i + backoff
      state[:log_stream]&.warn("Backing off #{backoff}s")
      sleep backoff
    end

    def resolve_params(strategy)
      strategy.class.params_schema.transform_values { |v| v[:default] }
    end

    def strategy_covers_instrument?(state, instrument_key)
      manifest = Strategies::Version.find_by(id: state[:version_id])&.manifest
      return false unless manifest

      manifest["instruments"]&.include?(instrument_key)
    end
  end
end
