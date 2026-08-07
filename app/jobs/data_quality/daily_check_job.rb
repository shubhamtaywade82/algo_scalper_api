# frozen_string_literal: true

module DataQuality
  # Once-daily rollup of Section 9 data quality KPIs (docs/AlgoScalperPlatform-v2.0.md):
  # missing candle count, candle alignment accuracy, tick staleness rate, instrument
  # mapping accuracy, expired-instrument handling. Observability only — finds and records,
  # never mutates instrument/derivative state.
  #
  # Note: Instrument/Derivative have no `active` boolean column — the catalog is a raw daily
  # CSV import differentiated only by expiry_date, so "expired instrument handling" here means
  # stale (already-expired) rows still present for the underlyings we actually trade, not a
  # deactivation-flag check. The live-trading risk this could cause is already independently
  # covered by Live::ExitEngine#expired_contract? at exit time — this is catalog housekeeping
  # visibility, not a new safety gate.
  class DailyCheckJob < ApplicationJob
    queue_as :background

    TRADING_WINDOW_MINUTES = 375 # 09:15–15:30 IST

    def perform
      return unless Market::Calendar.trading_day?(Date.current)

      candle_stats = candle_gap_and_alignment_stats
      expired = expired_derivatives_for_traded_symbols.to_a

      metric = DataQualityDailyMetric.find_or_create_by!(trading_date: Date.current)
      metric.update!(
        missing_candle_count: candle_stats[:missing_total],
        candle_alignment_accuracy_pct: candle_stats[:alignment_accuracy_pct],
        tick_staleness_rate_pct: tick_staleness_rate,
        instrument_mapping_accuracy_pct: instrument_mapping_accuracy_pct,
        expired_instrument_count: expired.size,
        meta: { per_symbol_candle_gaps: candle_stats[:per_symbol] }
      )

      audit_expired_derivatives!(expired) if expired.any?
    end

    private

    def traded_symbols
      (AlgoConfig.fetch[:indices] || []).filter_map { |idx| idx[:key]&.to_s }
    end

    # ── Candle gaps + alignment ─────────────────────────────────────────────

    def candle_gap_and_alignment_stats
      today_candles = Candles::Record.where(ts: Date.current.all_day)
      combos = today_candles.distinct.pluck(:instrument_key, :timeframe)

      missing_total = 0
      aligned_rows = 0
      total_rows = 0
      per_symbol = {}

      combos.each do |instrument_key, timeframe|
        interval = interval_minutes(timeframe)
        next unless interval

        rows = today_candles.where(instrument_key: instrument_key, timeframe: timeframe).to_a
        expected = TRADING_WINDOW_MINUTES / interval
        actual = rows.size
        missing = [expected - actual, 0].max
        aligned = rows.count { |r| aligned_to_boundary?(r.ts, interval) }

        missing_total += missing
        aligned_rows += aligned
        total_rows += actual
        per_symbol[instrument_key] = { timeframe: timeframe, expected: expected, actual: actual, missing: missing }
      end

      {
        missing_total: missing_total,
        alignment_accuracy_pct: total_rows.positive? ? ((aligned_rows.to_f / total_rows) * 100).round(4) : nil,
        per_symbol: per_symbol
      }
    end

    def interval_minutes(timeframe)
      timeframe.to_s[/\A(\d+)m\z/, 1]&.to_i
    end

    def aligned_to_boundary?(ts, interval)
      local = ts.in_time_zone('Asia/Kolkata')
      local.sec.zero? && (local.min % interval).zero?
    end

    # ── Instrument mapping accuracy (scoped to traded underlyings — the full catalog
    #    import includes thousands of unrelated equity/segment rows) ───────────────

    def instrument_mapping_accuracy_pct
      symbols = traded_symbols
      return 100.0 if symbols.empty?

      instrument_scope = Instrument.where(symbol_name: symbols)
      derivative_scope = Derivative.where(underlying_symbol: symbols)
      total = instrument_scope.count + derivative_scope.count
      return 100.0 if total.zero?

      valid = instrument_scope.where.not(security_id: [nil, '']).count +
              derivative_scope.where.not(security_id: [nil, '']).count
      ((valid.to_f / total) * 100).round(4)
    end

    # ── Expired instrument handling (observability only) ────────────────────

    def expired_derivatives_for_traded_symbols
      symbols = traded_symbols
      return Derivative.none if symbols.empty?

      Derivative.where(underlying_symbol: symbols).where('expiry_date < ?', Date.current)
    end

    def audit_expired_derivatives!(expired)
      AuditLog.create!(
        event_type: 'reconciliation_mismatch',
        metadata: {
          kind: 'expired_derivatives_still_cataloged',
          count: expired.size,
          ids: expired.first(50).map(&:id)
        }
      )
    end

    # ── Tick staleness rollup (reads + clears DataQuality::TickStalenessSamplerJob's counters) ──

    def tick_staleness_rate
      keys = DataQuality::TickStalenessSamplerJob.cache_keys_for(Date.current)
      total = Rails.cache.read(keys[:total]) || 0
      return nil unless total.positive?

      stale = Rails.cache.read(keys[:stale]) || 0
      rate = ((stale.to_f / total) * 100).round(4)

      Rails.cache.delete(keys[:total])
      Rails.cache.delete(keys[:stale])
      rate
    end
  end
end
