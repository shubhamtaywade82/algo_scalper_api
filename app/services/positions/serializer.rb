# frozen_string_literal: true

module Positions
  module Serializer
    module_function

    def open(tracker)
      cache = Live::RedisPnlCache.instance.fetch_pnl(tracker.id) || {}
      ltp = (cache[:ltp] || tracker.avg_price.to_f).to_f
      entry = tracker.entry_price.to_f
      qty = tracker.quantity.to_i
      net_pnl = (cache[:pnl] || tracker.last_pnl_rupees.to_f).to_f

      sl_price = cache[:sl_price] || (entry.positive? ? entry * 0.70 : nil)
      tp_price = cache[:tp_price] || (entry.positive? ? entry * 1.60 : nil)

      base_attributes(tracker).merge(
        entry_price: entry.round(2),
        ltp: ltp.round(2),
        pnl: net_pnl.round(2),
        pnl_pct: net_pnl_pct(net_pnl, entry, qty),
        hwm_pnl: (cache[:hwm_pnl] || tracker.high_water_mark_pnl.to_f).round(2),
        sl_price: sl_price&.to_f&.round(2),
        tp_price: tp_price&.to_f&.round(2),
        entry_strategy: tracker.entry_strategy,
        time_in_position_sec: cache[:time_in_position_sec]
      )
    end

    def closed(tracker)
      entry = tracker.entry_price.to_f
      exit_p = tracker.exit_price.to_f
      qty = tracker.quantity.to_i
      net_pnl = tracker.last_pnl_rupees.to_f
      meta = tracker.meta.is_a?(Hash) ? tracker.meta : {}
      execution_meta = meta['execution'].is_a?(Hash) ? meta['execution'] : {}
      classification = execution_meta['classified_as']

      base_attributes(tracker).merge(
        entry_price: entry.round(2),
        exit_price: exit_p.round(2),
        pnl: net_pnl.round(2),
        pnl_pct: net_pnl_pct(net_pnl, entry, qty),
        hwm_pnl: tracker.high_water_mark_pnl.to_f.round(2),
        exit_reason: tracker.exit_reason || meta['exit_reason'],
        exit_path: meta['exit_path'],
        exit_classification: classification,
        exited_at: tracker.exited_at&.iso8601
      )
    end

    def detail(tracker)
      base = tracker.exited_at.present? ? closed(tracker) : open(tracker)

      base.merge(
        entry_context: entry_context(tracker),
        exit_block: exit_block(tracker),
        trailing_state: trailing_state(tracker),
        config_snapshot: tracker.meta_snapshot&.config_snapshot&.deep_symbolize_keys,
        config_version_hash: tracker.meta_snapshot&.config_version_hash,
        strategy_signal: strategy_signal_block(tracker),
        meta: tracker.meta
      )
    end

    def entry_context(tracker)
      {
        iv_at_entry: tracker.iv_at_entry&.to_f,
        vix_at_entry: tracker.vix_at_entry&.to_f,
        dte_at_entry: tracker.dte_at_entry,
        atm_strike: tracker.atm_strike&.to_f,
        expiry_date: tracker.expiry_date&.iso8601,
        entry_underlying_price: tracker.entry_underlying_price&.to_f,
        entry_tf: tracker.entry_tf,
        alpha_source: tracker.alpha_source,
        entry_path: tracker.entry_path,
        signal_confidence: tracker.signal_confidence&.to_f
      }
    end

    def exit_block(tracker)
      return nil unless tracker.exited_at.present?

      execution_meta = tracker.execution.is_a?(Hash) ? tracker.execution : {}
      {
        exit_reason: tracker.exit_reason,
        exit_path: tracker.exit_path,
        exit_classification: execution_meta['classified_as'],
        exited_at: tracker.exited_at&.iso8601
      }
    end

    def trailing_state(tracker)
      {
        high_water_mark_pnl: tracker.high_water_mark_pnl&.to_f,
        hwm_pnl_pct: tracker.hwm_pnl_pct&.to_f,
        secured_sl_price: tracker.secured_sl_price&.to_f,
        breakeven_locked: tracker.breakeven_locked,
        profit_zone_state: tracker.profit_zone_state
      }
    end

    def strategy_signal_block(tracker)
      signal = Strategies::Signal.find_by(position_tracker_id: tracker.id)
      return nil unless signal

      {
        strategy_slug: signal.strategy_record.slug,
        action: signal.action,
        confidence: signal.confidence&.to_f,
        outcome: signal.outcome,
        reason: signal.reason,
        entry_result_reason: signal.metadata['entry_result_reason'],
        guard_results: signal.metadata['guard_results']
      }
    end

    def base_attributes(tracker)
      {
        id: tracker.id,
        order_no: tracker.order_no,
        symbol: tracker.symbol.presence || fallback_symbol(tracker),
        side: tracker.side,
        quantity: tracker.quantity.to_i,
        index_key: tracker.index_key,
        direction: tracker.direction,
        segment: tracker.segment,
        paper: tracker.paper?,
        created_at: tracker.created_at.iso8601
      }
    end

    def net_pnl_pct(net_pnl, entry, qty)
      capital = entry * qty
      return 0.0 unless capital.positive?

      ((net_pnl / capital) * 100).round(2)
    end

    def pnl_pct(entry, current)
      return 0.0 unless entry.positive? && current.positive?

      (((current - entry) / entry) * 100).round(2)
    end
  end
end

