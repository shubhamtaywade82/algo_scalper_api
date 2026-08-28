# frozen_string_literal: true

module Positions
  # Places a market exit for one active tracker (dashboard / operator control).
  class ManualCloseService < ApplicationService
    REASON = 'MANUAL_DASHBOARD_CLOSE'

    def initialize(tracker_id:)
      @tracker_id = tracker_id
    end

    def call
      id = normalized_id
      return failure(:bad_request, 'invalid_id') if id.blank?

      tracker = PositionTracker.active.find_by(id: id)
      return failure(:not_found, 'not_found') unless tracker

      run_exit(tracker)
    rescue StandardError => e
      Rails.logger.error("[#{self.class.name}] #{e.class} - #{e.message}")
      failure(:internal_server_error, 'exception', message: e.message)
    end

    private

    def normalized_id
      v = @tracker_id.to_s.strip
      return nil if v.blank?
      return Integer(v) if v.match?(/\A\d+\z/)

      nil
    rescue ArgumentError, TypeError
      nil
    end

    def run_exit(tracker)
      clear_redis_exit_lock(tracker.id)
      exit_engine = nil
      router = TradingSystem::OrderRouter.new
      exit_engine = Live::ExitEngine.new(order_router: router)
      exit_engine.start
      translate(exit_engine.execute_exit(tracker, REASON))
    ensure
      exit_engine&.stop
    end

    def clear_redis_exit_lock(tracker_id)
      return if tracker_id.blank?

      redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379/0'))
      redis.del("exit_lock:#{tracker_id}")
    rescue StandardError => e
      Rails.logger.warn("[#{self.class.name}] clear_redis_exit_lock failed: #{e.class} - #{e.message}")
    end

    def translate(raw)
      return { status: :ok, json: raw } if raw[:success]

      failure(http_for_failure(raw[:reason]), raw[:reason].to_s, detail: raw[:error])
    end

    def http_for_failure(reason)
      case reason.to_s
      when 'exit_lock_held' then :conflict
      when 'router_failed' then :bad_gateway
      when 'invalid_router', 'invalid_reason' then :service_unavailable
      else :unprocessable_content
      end
    end

    def failure(status, code, detail: nil, message: nil)
      body = { success: false, error: code }
      body[:detail] = detail if detail.present?
      body[:message] = message if message.present?
      { status: status, json: body }
    end
  end
end
