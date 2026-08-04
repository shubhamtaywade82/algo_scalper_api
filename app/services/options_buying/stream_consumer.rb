# frozen_string_literal: true

module OptionsBuying
  class StreamConsumer
    CONSUMER_NAME = 'processor_1'

    def initialize
      @running = false
      @thread = nil
      @mutex = Mutex.new
    end

    def start
      return unless Mode.streams_enabled?

      @mutex.synchronize do
        return if @running

        @running = true
      end

      ensure_groups_for_monitored_strikes!

      @thread = Thread.new do
        Thread.current.name = 'options-buying-stream-consumer'
        consume_loop
      end

      Rails.logger.info('[OptionsBuying::StreamConsumer] Started')
    end

    def stop
      @mutex.synchronize { @running = false }
      return unless @thread

      @thread.join(2) if @thread.alive?
      @thread = nil
      Rails.logger.info('[OptionsBuying::StreamConsumer] Stopped')
    end

    private

    def consume_loop
      empty_reads = 0
      while @running
        begin
          ensure_groups_for_monitored_strikes!
          processed = read_batch
          if processed.zero?
            empty_reads += 1
            # Exponential backoff: 0.1s, 0.2s, 0.4s, 0.8s, 1.6s, max 2s
            backoff = [0.1 * (2**(empty_reads - 1)), 2.0].min
            sleep(backoff)
          else
            empty_reads = 0
          end
        rescue StandardError => e
          Rails.logger.warn("[OptionsBuying::StreamConsumer] #{e.class} - #{e.message}")
          sleep(0.25)
        end
      end
    end

    def read_batch
      count = 0
      StateStore.monitored_strikes.each do |security_id|
        messages = StateStore.xreadgroup(security_id, consumer_name: CONSUMER_NAME, count: 5)
        next if messages.blank?

        stream_messages = messages[StateStore.stream_key(security_id)] || messages.values.first
        stream_messages&.each do |message_id, fields|
          process_message!(security_id, message_id, fields)
          count += 1
        end
      end
      count
    end

    def process_message!(security_id, message_id, fields)
      return if StateStore.kill_switch_active?

      tick = StateStore.parse_stream_message(fields)
      index_key = index_key_for_security(security_id)
      return unless index_key

      StrategyEngine.evaluate!(
        index_key: index_key,
        security_id: security_id,
        current_tick: tick
      )
    ensure
      StateStore.xack(security_id, message_id)
    end

    def ensure_groups_for_monitored_strikes!
      StateStore.monitored_strikes.each do |security_id|
        StateStore.ensure_stream_group!(security_id)
      end

      IndexConfigLoader.load_indices.each do |idx|
        StateStore.radar_strikes(idx[:key]).each do |strike|
          sid = strike[:security_id].to_s
          next if sid.blank?

          StateStore.ensure_stream_group!(sid)
        end
      end
    rescue StandardError => e
      Rails.logger.warn("[OptionsBuying::StreamConsumer] ensure_groups #{e.class} - #{e.message}")
    end

    def index_key_for_security(security_id)
      IndexConfigLoader.load_indices.each do |idx|
        return idx[:key] if idx[:sid].to_s == security_id.to_s

        strikes = StateStore.radar_strikes(idx[:key])
        return idx[:key] if strikes.any? { |s| s[:security_id].to_s == security_id.to_s }
      end
      nil
    end
  end
end
