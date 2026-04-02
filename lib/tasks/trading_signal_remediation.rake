# frozen_string_literal: true

namespace :trading do
  desc <<~DESC.squish
    Tag TradingSignal rows blocked by historical FloatDomainError (metadata only; preserves entry_blocked_reason).
    Default: signals created today (app timezone). Set REMEDIATE_ALL=1 for every matching row.
  DESC
  task remediate_float_domain_metadata: :environment do
    scope = TradingSignal.where("metadata->>'entry_blocked_reason' LIKE ?", '%FloatDomainError%')
    unless ENV['REMEDIATE_ALL'].to_s == '1'
      scope = scope.where(created_at: Time.zone.today.all_day)
    end

    updated = 0
    skipped = 0

    scope.find_each do |signal|
      meta = signal.metadata || {}
      if meta['historical_float_domain_error_remediated_at'].present?
        skipped += 1
        next
      end

      signal.update!(
        metadata: meta.merge(
          'historical_float_domain_error' => true,
          'historical_float_domain_error_remediated_at' => Time.current.iso8601
        )
      )
      updated += 1
    end

    puts "[trading:remediate_float_domain_metadata] updated=#{updated} skipped_already_tagged=#{skipped}"
  end

  desc <<~DESC.squish
    Create TradeAnalytic rows for exited PositionTrackers that have none (e.g. after a failed after_commit).
    Default: trackers created today (app timezone). Set REMEDIATE_ALL=1 for every matching exited row.
  DESC
  task backfill_missing_trade_analytics: :environment do
    scope = PositionTracker.exited.where.missing(:trade_analytic)
    unless ENV['REMEDIATE_ALL'].to_s == '1'
      scope = scope.where(created_at: Time.zone.today.all_day)
    end

    created = 0
    failed = 0

    scope.find_each do |tracker|
      Optimization::TradeAnalyzer.call(tracker)
      tracker.reload
      if tracker.trade_analytic.present?
        created += 1
      else
        failed += 1
      end
    end

    puts "[trading:backfill_missing_trade_analytics] created=#{created} still_missing=#{failed}"
  end
end
