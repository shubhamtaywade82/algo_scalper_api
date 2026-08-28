# frozen_string_literal: true

require 'prometheus_exporter'
require 'prometheus_exporter/server'
require 'prometheus_exporter/instrumentation'

# Prometheus metrics exporter for Rails
# Exposes /metrics endpoint for Prometheus scraping
Rails.application.config.after_initialize do
  next unless ENV.fetch('PROMETHEUS_EXPORTER_ENABLED', 'false') == 'true'

  PrometheusExporter::Server::Collector.new
  PrometheusExporter::Instrumentation::Process.start(type: "app")
  PrometheusExporter::Instrumentation::MethodProfiler.start(
    for: [ActiveRecord::Base],
    type: "sql",
    metric_prefix: "rails_active_record"
  )

  # Rack middleware to expose /metrics
  Rails.application.config.middleware.use PrometheusExporter::Instrumentation::Rack
end

# Custom trading metrics (defined as methods to avoid constant-in-block lint)
module TradingMetrics
  class << self
    def trades_total
      @trades_total ||= PrometheusExporter::Client.default.register(
        :counter,
        "trades_total",
        "Total number of trades executed"
      )
    end

    def positions_active
      @positions_active ||= PrometheusExporter::Client.default.register(
        :gauge,
        "positions_active",
        "Number of active positions"
      )
    end

    def pnl_realized
      @pnl_realized ||= PrometheusExporter::Client.default.register(
        :gauge,
        "pnl_realized_total",
        "Total realized P&L"
      )
    end

    def order_fills_total
      @order_fills_total ||= PrometheusExporter::Client.default.register(
        :counter,
        "order_fills_total",
        "Total order fills",
        %i[status strategy]
      )
    end

    def circuit_breaker_status
      @circuit_breaker_status ||= PrometheusExporter::Client.default.register(
        :gauge,
        "circuit_breaker_tripped",
        "Circuit breaker status (1=tripped, 0=ok)"
      )
    end
  end
end
