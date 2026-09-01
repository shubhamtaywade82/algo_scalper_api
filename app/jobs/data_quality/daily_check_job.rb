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
    FILL_TOLERANCE_PCT = 0.5 # allowed deviation from the real 1m candle's [low, high] range
    FILL_RECONCILIATION_API_DELAY_SECONDS = 0.25 # keeps us well under Dhan's 5 req/sec data-API limit

    def perform
      return unless Market::Calendar.trading_day?(Date.current)

      candle_stats = candle_gap_and_alignment_stats
      expired = expired_derivatives_for_traded_symbols.to_a
      fill_stats = fill_reconciliation_stats

      metric = DataQualityDailyMetric.find_or_create_by!(trading_date: Date.current)
      metric.update!(
        missing_candle_count: candle_stats[:missing_total],
        candle_alignment_accuracy_pct: candle_stats[:alignment_accuracy_pct],
        tick_staleness_rate_pct: tick_staleness_rate,
        instrument_mapping_accuracy_pct: instrument_mapping_accuracy_pct,
        expired_instrument_count: expired.size,
        fill_reconciliation_checked_count: fill_stats[:checked],
        fill_reconciliation_mismatch_count: fill_stats[:mismatches].size,
        meta: { per_symbol_candle_gaps: candle_stats[:per_symbol], fill_mismatches: fill_stats[:mismatches] }
      )

      audit_expired_derivatives!(expired) if expired.any?
      audit_and_notify_fill_mismatches!(fill_stats[:mismatches]) if fill_stats[:mismatches].any?
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

      Derivative.where(underlying_symbol: symbols).where(expiry_date: ...Date.current)
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

    # ── Fill-price reconciliation (recorded entry/exit price vs real 1m OHLC) ─
    #
    # Catches fills computed from a stale cached tick (e.g. a residual price left over from a
    # security_id's earlier session activity) — the kind of bug that inflates or fabricates a
    # trade's PnL without any trace in the trade's own record. One API call per unique
    # (segment, security_id) traded today, not per trade, so this stays cheap even on a busy day.
    def fill_reconciliation_stats
      positions = PositionTracker.where(status: 'exited', exited_at: Date.current.all_day)
                                 .where.not(security_id: [nil, '']).where.not(segment: [nil, ''])
      return { checked: 0, mismatches: [] } if positions.empty?

      candles_by_instrument = fetch_candles_for(positions)
      mismatches = positions.flat_map { |position| fill_mismatches_for(position, candles_by_instrument) }

      { checked: positions.count, mismatches: mismatches }
    end

    def fetch_candles_for(positions)
      positions.map { |p| [p.segment, p.security_id] }.uniq.each_with_object({}) do |(segment, security_id), out|
        out[[segment, security_id]] = fetch_intraday_candles(segment: segment, security_id: security_id)
        sleep FILL_RECONCILIATION_API_DELAY_SECONDS
      end
    end

    def fetch_intraday_candles(segment:, security_id:)
      data = DhanHQ::Models::HistoricalData.intraday(
        security_id: security_id,
        exchange_segment: segment,
        instrument: 'OPTIDX',
        interval: '1',
        from_date: "#{Date.current} 09:15:00",
        to_date: "#{Date.current} 15:30:00"
      )
      return {} unless data.is_a?(Array)

      data.each_with_object({}) do |candle, out|
        ts = candle[:timestamp]
        ts = ts.in_time_zone('Asia/Kolkata') if ts.respond_to?(:in_time_zone)
        out[ts.change(sec: 0)] = candle
      end
    rescue StandardError => e
      Rails.logger.error("[DataQuality::DailyCheckJob] candle fetch failed for #{segment}:#{security_id}: #{e.class} - #{e.message}")
      {}
    end

    def fill_mismatches_for(position, candles_by_instrument)
      candles = candles_by_instrument[[position.segment, position.security_id]]
      return [] if candles.blank?

      [
        fill_mismatch(position, candles, :entry_price, position.created_at),
        fill_mismatch(position, candles, :exit_price, position.exited_at)
      ].compact
    end

    def fill_mismatch(position, candles, price_field, at)
      return nil if at.blank?

      price = position.public_send(price_field).to_f
      return nil unless price.positive?

      candle = candles[at.in_time_zone('Asia/Kolkata').change(sec: 0)]
      return nil unless candle

      low = candle[:low].to_f * (1 - (FILL_TOLERANCE_PCT / 100.0))
      high = candle[:high].to_f * (1 + (FILL_TOLERANCE_PCT / 100.0))
      return nil if price.between?(low, high)

      {
        position_id: position.id, symbol: position.symbol, security_id: position.security_id,
        field: price_field.to_s, recorded_price: price,
        candle_low: candle[:low].to_f, candle_high: candle[:high].to_f, at: at.iso8601
      }
    end

    def audit_and_notify_fill_mismatches!(mismatches)
      AuditLog.create!(
        event_type: 'reconciliation_mismatch',
        metadata: { kind: 'fill_price_vs_ohlc_mismatch', count: mismatches.size, mismatches: mismatches.first(50) }
      )

      summary = mismatches.first(5).map { |m| "#{m[:symbol]} #{m[:field]}: ₹#{m[:recorded_price]} vs candle ₹#{m[:candle_low]}-#{m[:candle_high]}" }
      Notifications::TelegramNotifier.instance.notify_warning(
        "#{mismatches.size} fill price mismatch(es) vs real OHLC today:\n#{summary.join("\n")}",
        context: 'DataQuality::DailyCheckJob'
      )
    rescue StandardError => e
      Rails.logger.error("[DataQuality::DailyCheckJob] Failed to audit/notify fill mismatches: #{e.class} - #{e.message}")
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
