# frozen_string_literal: true

module Dhan
  # DhanHQ 4.1.1 Connection#loop_run wraps each session in EM.run, but EM.run returns immediately
  # when the reactor is already running (order-update WS, or a feed client left over from a
  # restart). The loop then never blocked or backed off and opened ~50 feed sockets per second
  # until Dhan stopped sending ticks. Sessions now run on one shared reactor and block until
  # their socket closes. Prepended onto DhanHQ::WS::Connection in an initializer.
  module SharedReactorConnection
    REACTOR_CHECK_SECONDS = 5
    CLEAN_CLOSE_PAUSE_SECONDS = 1
    REACTOR_LOCK = Mutex.new

    def self.ensure_reactor!
      REACTOR_LOCK.synchronize do
        next if EM.reactor_running?

        Thread.new { EM.run }.name = 'dhan-ws-reactor'
        sleep 0.01 until EM.reactor_running?
      end
    end

    private

    def loop_run
      backoff = 2.0
      session = 0
      until @stop
        session += 1
        close_reason = run_session(session)
        break if @stop

        backoff = pause_after(close_reason, backoff)
      end
    end

    # @return [Symbol] :clean, :failed or :rate_limited
    def run_session(session)
      closed = Queue.new
      SharedReactorConnection.ensure_reactor!
      EM.schedule { open_socket(session, closed) }
      wait_for_close(closed)
    ensure
      @ws = nil
    end

    def open_socket(session, closed)
      @ws = Faye::WebSocket::Client.new(@url, nil, headers: default_headers)
      @ws.on(:open) { |_| handle_open(session) }
      @ws.on(:message) do |ev|
        notify(:message, nil)
        @on_binary&.call(ev.data)
      end
      @ws.on(:error) { |ev| notify(:error, ev.message) }
      @ws.on(:close) { |ev| closed << close_reason_for(ev) }
    end

    def close_reason_for(event)
      EM.cancel_timer(@timer) if @timer
      @timer = nil
      DhanHQ.logger&.warn("[DhanHQ::WS] close #{event.code} #{event.reason}")
      reason = if @stopping || event.code == 1000 then :clean
               elsif event.reason.to_s.include?('429') then :rate_limited
               else :failed
               end
      notify(:close, { code: event.code, reason: event.reason, reconnecting: reason != :clean })
      reason
    end

    # Another client calling EM.stop kills the shared reactor without firing our close event.
    def wait_for_close(closed)
      loop do
        reason = closed.pop(timeout: REACTOR_CHECK_SECONDS)
        return reason if reason
        return :failed unless EM.reactor_running?
      end
    end

    def pause_after(close_reason, backoff)
      case close_reason
      when :clean
        sleep CLEAN_CLOSE_PAUSE_SECONDS
        2.0
      when :rate_limited
        sleep self.class::COOL_OFF_429
        backoff
      else
        sleep [backoff, self.class::MAX_BACKOFF].min
        backoff * 2.0
      end
    end
  end
end
