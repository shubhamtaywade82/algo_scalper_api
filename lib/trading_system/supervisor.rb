# frozen_string_literal: true

module TradingSystem
  # Coordinates lifecycle for long-running trading services.
  #
  # NOTE: This supervisor is intentionally NOT a Singleton. Multiple processes
  # (web, daemon) may each have their own supervisor instance.
  class Supervisor
    def initialize
      @services = {} # { name(Symbol) => service_instance }
      @running = false
      @mutex = Mutex.new
    end

    def register(name, instance)
      @services[name.to_sym] = instance
    end

    delegate :[], :key?, :fetch, :dig, to: :@services

    def services
      @services.dup
    end

    def running?
      @mutex.synchronize { @running }
    end

    def start_all
      @mutex.synchronize do
        return if @running

        @services.each_key { |name| start_one(name) }

        @running = true
      end
    end

    def stop_all
      @mutex.synchronize do
        return unless @running

        @services.keys.reverse_each { |name| stop_one(name) }

        @running = false
      end
    end

    def start_service(name)
      name = name.to_sym
      @mutex.synchronize do
        raise "Unknown service: #{name}" unless @services.key?(name)

        start_one(name)
      end
    end

    def stop_service(name)
      name = name.to_sym
      @mutex.synchronize do
        raise "Unknown service: #{name}" unless @services.key?(name)

        stop_one(name)
      end
    end

    def restart_service(name)
      name = name.to_sym
      @mutex.synchronize do
        raise "Unknown service: #{name}" unless @services.key?(name)

        stop_one(name)
        start_one(name)
      end
    end

    private

    def start_one(name)
      service = @services[name]
      service.start
      Rails.logger.info("[Supervisor] started #{name}")
    rescue StandardError => e
      Rails.logger.error("[Supervisor] failed starting #{name}: #{e.class} - #{e.message}")
    end

    def stop_one(name)
      service = @services[name]
      service.stop
      Rails.logger.info("[Supervisor] stopped #{name}")
    rescue StandardError => e
      Rails.logger.error("[Supervisor] error stopping #{name}: #{e.class} - #{e.message}")
    end

    # Best-effort health snapshot for use by API health endpoints.
    # Returns a hash keyed by service name with boolean statuses.
    def health_check
      @services.transform_values do |svc|
        if svc.respond_to?(:healthy?)
          svc.healthy?
        elsif svc.respond_to?(:running?)
          svc.running?
        else
          true
        end
      rescue StandardError
        false
      end
    end
  end
end

