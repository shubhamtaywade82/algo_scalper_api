# frozen_string_literal: true

module Reports
  # Builds a Market Brief off the request path (the LLM call can take a minute).
  #
  #   Reports::MarketBriefJob.perform_later(report.id)          # manual refresh
  #   Reports::MarketBriefJob.perform_later(nil, 'scheduled')    # recurring.yml
  #
  # Arguments are positional on purpose: recurring.yml args are plain YAML and
  # must not depend on keyword/hash-key coercion.
  #
  # Idempotent: MarketBriefReport#claim_for_build! lets exactly one execution
  # build a given report; replays and duplicates exit without side effects.
  class MarketBriefJob < ApplicationJob
    queue_as :background

    discard_on ActiveRecord::RecordNotFound

    def perform(report_id = nil, trigger = 'manual', force_ai = false) # rubocop:disable Style/OptionalBooleanParameter
      report = if report_id
                 MarketBriefReport.find(report_id)
               else
                 scheduled_report(trigger)
               end
      return unless report

      Reports::MarketBrief::Generator.call(report, force_ai: force_ai == true)
    end

    private

    def scheduled_report(trigger)
      today = Time.current.in_time_zone(TradingSession::Service::IST_TIMEZONE).to_date
      unless Market::Calendar.trading_day?(today)
        Rails.logger.info("[Reports::MarketBriefJob] #{today} is not a trading day; no scheduled brief")
        return nil
      end

      report, = MarketBriefReport.request!(mode: AlgoConfig.mode, trigger: trigger)
      report
    end
  end
end
