# frozen_string_literal: true

module Observability
  class EntryFunnelMetrics < ApplicationService
    GUARD_BUCKETS = [
      [/breakout not armed|breakout guard unavailable/i, 'BreakoutReadyGuard'],
      [/rsi/i, 'RsiBiasGuard'],
      [/cooldown/i, 'CooldownGuard'],
      [/circuit breaker|tripped/i, 'CircuitBreakerGuard'],
      [/drawdown/i, 'DrawdownGuard'],
      [/midday|adx/i, 'MiddayQualityGuard'],
      [/smc_navigator/i, 'SmcNavigatorGuard'],
      [/edge failure/i, 'EdgeFailureGuard'],
      [/loss streak/i, 'LossStreakGuard'],
      [/daily limit|trades today/i, 'DailyLimitsGuard'],
      [/exposure|concurrent/i, 'ExposureGuard'],
      [/spread|bid.?ask/i, 'BidAskSpreadGuard'],
      [/transaction cost|tcm/i, 'TransactionCostGuard'],
      [/compression/i, 'CompressionSetupGuard'],
      [/ltp|tick/i, 'LtpResolutionGuard'],
      [/order_failed|execution/i, 'OrderExecution'],
      [/exception:/i, 'Exception']
    ].freeze

    def initialize(date: Time.zone.today, index_key: nil, include_live_state: false)
      @date = date.to_date
      @index_key = index_key&.to_s&.downcase.presence
      @include_live_state = include_live_state
    end

    def call
      @call ||= build_report
    end

    def render
      data = call
      lines = []
      lines << ('=' * 88)
      lines << "ENTRY FUNNEL METRICS — #{data[:date]}#{index_suffix(data[:index_key])}"
      lines << ('=' * 88)
      lines << ''
      lines << 'SUMMARY'
      lines << ('-' * 88)
      append_summary_lines(lines, data[:summary])
      lines << ''
      lines << 'OPTIONS BUYING — BREAKOUT ARMS (telemetry)'
      lines << ('-' * 88)
      append_count_lines(lines, data[:breakout_events], empty: 'none')
      lines << ''
      lines << 'POSITIONS OPENED'
      lines << ('-' * 88)
      append_count_lines(lines, data[:positions], empty: 'none')
      lines << ''
      lines << 'TRADING SIGNALS — ENTRY OUTCOMES'
      lines << ('-' * 88)
      append_signal_lines(lines, data[:signals])
      lines << ''
      lines << 'GUARD BLOCKS (try_enter)'
      lines << ('-' * 88)
      append_guard_lines(lines, data[:guard_blocks])
      lines << ''
      lines << 'SIGNAL SKIPS (post-signal, pre-try_enter)'
      lines << ('-' * 88)
      append_skip_lines(lines, data[:signal_skips])
      lines << ''
      lines << 'BREAKOUT ALIGNMENT'
      lines << ('-' * 88)
      append_alignment_lines(lines, data[:alignment])
      if data[:live_state].present?
        lines << ''
        lines << 'LIVE REDIS STATE (now)'
        lines << ('-' * 88)
        append_live_state_lines(lines, data[:live_state])
      end
      if data[:notes].any?
        lines << ''
        lines << 'NOTES'
        lines << ('-' * 88)
        data[:notes].each { |note| lines << "  • #{note}" }
      end
      lines.join("\n")
    end

    def self.guard_bucket_for(reason)
      return 'unknown' if reason.blank?

      GUARD_BUCKETS.each do |pattern, bucket|
        return bucket if reason.match?(pattern)
      end

      'Other'
    end

    private

    def build_report
      {
        date: @date.iso8601,
        index_key: @index_key,
        summary: summary_counts,
        breakout_events: breakout_event_counts,
        positions: position_counts,
        signals: signal_breakdown,
        guard_blocks: guard_block_counts,
        signal_skips: signal_skip_counts,
        alignment: alignment_metrics,
        live_state: live_breakout_state,
        notes: report_notes
      }
    end

    def day_range
      @date.in_time_zone.all_day
    end

    def index_suffix(index_key)
      index_key.present? ? " — #{index_key.upcase}" : ' — ALL INDICES'
    end

    def summary_counts
      signals = signal_scope.to_a
      outcomes = signals.group_by { |s| s.metadata&.dig('entry_outcome') }
      entered = outcomes['entered']&.size.to_i
      blocked = outcomes['blocked']&.size.to_i
      skipped = outcomes['skipped']&.size.to_i
      no_outcome = signals.size - entered - blocked - skipped
      attempted = entered + blocked
      arms = breakout_event_scope.count

      {
        breakout_arms: arms,
        signals_created: signals.size,
        try_enter_attempts: attempted,
        entered: entered,
        guard_blocked: blocked,
        signal_skipped: skipped,
        no_outcome_recorded: no_outcome,
        positions_opened: position_scope.count,
        enter_rate_pct: percentage(entered, attempted),
        signal_to_enter_pct: percentage(entered, signals.size)
      }
    end

    def breakout_event_counts
      sort_desc(
        count_hash(breakout_event_scope.to_a) { |row| "#{row.index_key} #{row.event_type}" }
      )
    end

    def position_counts
      sort_desc(
        count_hash(position_scope.to_a) do |tracker|
          meta = tracker.meta.is_a?(Hash) ? tracker.meta : {}
          meta['index_key'].presence || 'unknown'
        end
      )
    end

    def signal_breakdown
      signals = signal_scope.to_a
      by_outcome = count_hash(signals) { |s| s.metadata&.dig('entry_outcome').presence || 'no_outcome' }
      by_index = count_hash(signals) { |s| s.index_key.to_s }
      by_direction = count_hash(signals) { |s| s.direction.to_s }

      { by_outcome: by_outcome, by_index: by_index, by_direction: by_direction }
    end

    def guard_block_counts
      blocked_signals = signal_scope.where("metadata->>'entry_outcome' = ?", 'blocked')
      by_guard = count_hash(blocked_signals) do |signal|
        self.class.guard_bucket_for(signal.metadata&.dig('entry_blocked_reason'))
      end
      by_reason = count_hash(blocked_signals) do |signal|
        signal.metadata&.dig('entry_blocked_reason').presence || 'unknown'
      end

      breakout_blocks = blocked_signals.select do |signal|
        self.class.guard_bucket_for(signal.metadata&.dig('entry_blocked_reason')) == 'BreakoutReadyGuard'
      end
      breakout_by_index = count_hash(breakout_blocks) { |s| s.index_key.to_s }

      {
        by_guard: sort_desc(by_guard),
        by_reason: sort_desc(by_reason),
        breakout_by_index: sort_desc(breakout_by_index),
        total: blocked_signals.count
      }
    end

    def signal_skip_counts
      skipped = signal_scope.where("metadata->>'entry_outcome' = ?", 'skipped')
      by_code = count_hash(skipped) { |s| s.metadata&.dig('entry_skip_code').presence || 'unspecified' }
      by_stage = count_hash(skipped) { |s| s.metadata&.dig('entry_skip_stage').presence || 'unspecified' }

      {
        by_code: sort_desc(by_code),
        by_stage: sort_desc(by_stage),
        total: skipped.count
      }
    end

    def alignment_metrics
      ce_arms = breakout_event_scope.where(event_type: 'breakout_armed_ce').count
      pe_arms = breakout_event_scope.where(event_type: 'breakout_armed_pe').count
      breakout_blocks = guard_block_counts[:breakout_by_index].values.sum
      entered = signal_scope.where("metadata->>'entry_outcome' = ?", 'entered').count

      {
        breakout_armed_ce: ce_arms,
        breakout_armed_pe: pe_arms,
        guard_blocked_breakout: breakout_blocks,
        entered_after_signal: entered,
        arms_without_enter: [ce_arms + pe_arms - entered, 0].max,
        dominant_block_guard: guard_block_counts[:by_guard].first&.first
      }
    end

    def live_breakout_state
      return {} unless @include_live_state

      indices = live_index_keys
      indices.index_with do |key|
        {
          bullish_ready: OptionsBuying::StateStore.breakout_ready?(key, direction: :bullish),
          bearish_ready: OptionsBuying::StateStore.breakout_ready?(key, direction: :bearish),
          resistance: OptionsBuying::StateStore.resistance(key),
          support: OptionsBuying::StateStore.support(key)
        }
      end
    rescue StandardError => e
      { error: "#{e.class}: #{e.message}" }
    end

    def live_index_keys
      if @index_key.present?
        [@index_key]
      else
        signal_scope.distinct.pluck(:index_key).presence ||
          OptionsBuyingSignalEvent.where(occurred_at: day_range).distinct.pluck(:index_key).presence ||
          %w[nifty banknifty sensex]
      end
    end

    def report_notes
      notes = []
      notes << 'Pre-signal cycle blocks (entry_quality, trading_context, etc.) are log-only — not in TradingSignal rows.'
      notes << 'Set LIVE=1 to include current Redis breakout_ready flags.'
      notes << 'Dominant guard block suggests where to relax config first.' if guard_block_counts[:by_guard].any?
      notes
    end

    def signal_scope
      scope = TradingSignal.where(created_at: day_range)
      scope = scope.where(index_key: @index_key) if @index_key.present?
      scope
    end

    def breakout_event_scope
      scope = OptionsBuyingSignalEvent.where(occurred_at: day_range)
      scope = scope.where(index_key: @index_key) if @index_key.present?
      scope
    end

    def position_scope
      scope = PositionTracker.where(created_at: day_range)
      if @index_key.present?
        scope = scope.where("meta->>'index_key' = ?", @index_key)
      end
      scope
    end

    def count_hash(items, &)
      items.each_with_object(Hash.new(0)) do |item, memo|
        memo[yield(item)] += 1
      end
    end

    def sort_desc(counts)
      counts.sort_by { |_, count| -count }.to_h
    end

    def percentage(numerator, denominator)
      return 0.0 if denominator.to_i.zero?

      ((numerator.to_f / denominator) * 100).round(1)
    end

    def append_summary_lines(lines, summary)
      lines << "  Breakout arms (telemetry):     #{summary[:breakout_arms]}"
      lines << "  Signals created:               #{summary[:signals_created]}"
      lines << "  try_enter attempts:            #{summary[:try_enter_attempts]}"
      lines << "  Entered:                       #{summary[:entered]}"
      lines << "  Guard blocked:                 #{summary[:guard_blocked]}"
      lines << "  Signal skipped (pre-entry):    #{summary[:signal_skipped]}"
      lines << "  No outcome recorded:           #{summary[:no_outcome_recorded]}"
      lines << "  Positions opened:              #{summary[:positions_opened]}"
      lines << "  Enter rate (of attempts):      #{summary[:enter_rate_pct]}%"
      lines << "  Signal → enter conversion:     #{summary[:signal_to_enter_pct]}%"
    end

    def append_count_lines(lines, counts, empty:)
      if counts.empty?
        lines << "  #{empty}"
        return
      end

      counts.each { |label, count| lines << "  #{label}: #{count}" }
    end

    def append_signal_lines(lines, signals)
      append_count_lines(lines, signals[:by_outcome], empty: 'no signals')
      lines << ''
      lines << '  By index:'
      append_count_lines(lines, signals[:by_index], empty: 'n/a')
      lines << ''
      lines << '  By direction:'
      append_count_lines(lines, signals[:by_direction], empty: 'n/a')
    end

    def append_guard_lines(lines, guard_blocks)
      lines << "  Total blocked: #{guard_blocks[:total]}"
      lines << ''
      lines << '  By guard:'
      append_count_lines(lines, guard_blocks[:by_guard], empty: 'none')
      if guard_blocks[:breakout_by_index].any?
        lines << ''
        lines << '  BreakoutReadyGuard by index:'
        append_count_lines(lines, guard_blocks[:breakout_by_index], empty: 'none')
      end
      top_reasons = guard_blocks[:by_reason].first(8).to_h
      if top_reasons.any?
        lines << ''
        lines << '  Top block reasons:'
        append_count_lines(lines, top_reasons, empty: 'none')
      end
    end

    def append_skip_lines(lines, signal_skips)
      lines << "  Total skipped: #{signal_skips[:total]}"
      lines << ''
      lines << '  By skip code:'
      append_count_lines(lines, signal_skips[:by_code], empty: 'none')
      lines << ''
      lines << '  By stage:'
      append_count_lines(lines, signal_skips[:by_stage], empty: 'none')
    end

    def append_alignment_lines(lines, alignment)
      lines << "  CE arms:                    #{alignment[:breakout_armed_ce]}"
      lines << "  PE arms:                    #{alignment[:breakout_armed_pe]}"
      lines << "  Blocked on breakout guard:  #{alignment[:guard_blocked_breakout]}"
      lines << "  Entered (signal metadata):  #{alignment[:entered_after_signal]}"
      lines << "  Dominant guard block:       #{alignment[:dominant_block_guard] || 'n/a'}"
    end

    def append_live_state_lines(lines, live_state)
      if live_state[:error]
        lines << "  error: #{live_state[:error]}"
        return
      end

      live_state.each do |index, state|
        lines << "  #{index}: CE_ready=#{state[:bullish_ready]} PE_ready=#{state[:bearish_ready]} " \
                 "res=#{state[:resistance] || 'n/a'} sup=#{state[:support] || 'n/a'}"
      end
    end
  end
end
