# frozen_string_literal: true

module Observability
  class EntryFunnelMetricsJob < ApplicationJob
    queue_as :background

    def perform(date = nil)
      report_date = parse_date(date)
      service = EntryFunnelMetrics.new(date: report_date)
      report = service.call

      Rails.logger.info("[EntryFunnelMetricsJob] Post-session funnel report\n#{service.render}")
      notify_telegram(report) if telegram_notify_enabled?
    rescue StandardError => e
      Rails.logger.error("[EntryFunnelMetricsJob] #{e.class} - #{e.message}")
      raise
    end

    private

    def parse_date(raw)
      return Time.zone.today if raw.blank?

      Date.parse(raw.to_s)
    rescue ArgumentError
      Time.zone.today
    end

    def telegram_notify_enabled?
      config = AlgoConfig.fetch[:telegram] || {}
      config[:enabled] != false &&
        config.fetch(:notify_entry_funnel_at_market_close, true) != false &&
        Notifications::TelegramNotifier.instance.enabled?
    end

    def notify_telegram(report)
      summary = report[:summary]
      top_guard = report.dig(:guard_blocks, :by_guard)&.first
      top_skip = report.dig(:signal_skips, :by_code)&.first
      guard_label = top_guard ? "#{top_guard[0]} (#{top_guard[1]})" : 'none'
      skip_label = top_skip ? "#{top_skip[0]} (#{top_skip[1]})" : 'none'

      message = <<~MSG.strip
        📊 Entry Funnel — #{report[:date]}
        Breakout arms: #{summary[:breakout_arms]}
        Signals: #{summary[:signals_created]} (legacy: #{summary[:legacy_signals]} | platform: #{summary[:strategy_platform_signals]}) | Entered: #{summary[:entered]}
        Blocked: #{summary[:guard_blocked]} | Skipped: #{summary[:signal_skipped]}
        Positions opened: #{summary[:positions_opened]}
        Enter rate: #{summary[:enter_rate_pct]}%
        Top guard block: #{guard_label}
        Top signal skip: #{skip_label}
      MSG

      Notifications::TelegramNotifier.instance.send_message(message)
    end
  end
end
