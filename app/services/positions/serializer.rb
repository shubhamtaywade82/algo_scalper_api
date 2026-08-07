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

      base_attributes(tracker).merge(
        entry_price: entry.round(2),
        ltp: ltp.round(2),
        pnl: net_pnl.round(2),
        pnl_pct: net_pnl_pct(net_pnl, entry, qty),
        hwm_pnl: (cache[:hwm_pnl] || tracker.high_water_mark_pnl.to_f).round(2),
        sl_price: sl_price(tracker, entry),
        tp_price: tp_price(tracker, entry),
        entry_strategy: tracker.entry_strategy,
        time_in_position_sec: cache[:time_in_position_sec]
      )
    end

    def closed(tracker)
      entry = tracker.entry_price.to_f
      exit_p = tracker.exit_price.to_f
      qty = tracker.quantity.to_i
      net_pnl = tracker.last_pnl_rupees.to_f

      execution_meta = tracker.execution.is_a?(Hash) ? tracker.execution : {}
      classification = execution_meta['classified_as']

      base_attributes(tracker).merge(
        entry_price: entry.round(2),
        exit_price: exit_p.round(2),
        pnl: net_pnl.round(2),
        pnl_pct: net_pnl_pct(net_pnl, entry, qty),
        hwm_pnl: tracker.high_water_mark_pnl.to_f.round(2),
        exit_reason: tracker.exit_reason,
        exit_path: tracker.exit_path,
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
        config_snapshot: (tracker.respond_to?(:meta_snapshot) ? tracker.meta_snapshot&.config_snapshot&.deep_symbolize_keys : nil),
        config_version_hash: (tracker.respond_to?(:meta_snapshot) ? tracker.meta_snapshot&.config_version_hash : nil),
        strategy_signal: strategy_signal_block(tracker),
        meta: tracker.meta
      )
    end

    def entry_context(tracker)
      meta = tracker.meta.is_a?(Hash) ? tracker.meta : {}
      inst = tracker.instrument

      deriv = if tracker.watchable.is_a?(Derivative)
                tracker.watchable
              elsif tracker.security_id.present?
                Derivative.find_by(security_id: tracker.security_id, segment: tracker.segment) || Derivative.find_by(security_id: tracker.security_id)
              end

      expiry = if meta.key?('expiry_date')
                 meta['expiry_date']
               elsif tracker.respond_to?(:expiry_date) && tracker.expiry_date.present?
                 tracker.expiry_date
               else
                 deriv&.expiry_date
               end
      expiry_date_obj = expiry.present? && expiry.respond_to?(:to_date) ? expiry.to_date : nil
      expiry_str = (expiry_date_obj && expiry_date_obj.year > 2000) ? expiry_date_obj.to_s : nil

      dte = (tracker.respond_to?(:dte_at_entry) ? tracker.dte_at_entry : nil) || meta['dte_at_entry']
      if dte.nil? && expiry_date_obj && tracker.created_at && expiry_date_obj.year > 2000
        dte = (expiry_date_obj - tracker.created_at.to_date).to_i
      end

      atm_strike = (tracker.respond_to?(:atm_strike) ? tracker.atm_strike : nil) || meta['atm_strike'] || deriv&.strike_price || inst&.strike_price
      if atm_strike.blank? && tracker.symbol.present?
        match = tracker.symbol.match(/(\d{4,6})/)
        atm_strike = match[1].to_f if match
      end

      iv_val  = (tracker.respond_to?(:iv_at_entry) ? tracker.iv_at_entry : nil) || meta['iv_at_entry'] || meta['iv']
      iv_val ||= 16.5

      vix_val = (tracker.respond_to?(:vix_at_entry) ? tracker.vix_at_entry : nil) || meta['vix_at_entry'] || meta['vix']
      vix_val ||= (defined?(Live::TickCache) ? Live::TickCache.ltp('IDX_I', '26009') : nil) || 13.5

      alpha_src = (tracker.respond_to?(:alpha_source) ? tracker.alpha_source : nil).presence || meta['alpha_source'] || 'AdaptiveSupertrendKnn'
      path_src  = (tracker.respond_to?(:entry_path) ? tracker.entry_path : nil).presence || meta['entry_path'] || 'BOS / Structure Break'
      tf_src    = (tracker.respond_to?(:entry_tf) ? tracker.entry_tf : nil).presence || meta['entry_tf'] || meta['bos_timeframe'] || '1m'

      {
        iv_at_entry: iv_val&.to_f,
        vix_at_entry: vix_val&.to_f,
        dte_at_entry: dte,
        atm_strike: atm_strike&.to_f,
        expiry_date: expiry_str,
        entry_underlying_price: ((tracker.respond_to?(:entry_underlying_price) ? tracker.entry_underlying_price : nil) || meta['entry_underlying_price'])&.to_f,
        entry_tf: tf_src,
        alpha_source: alpha_src,
        entry_path: path_src,
        signal_confidence: ((tracker.respond_to?(:signal_confidence) ? tracker.signal_confidence : nil) || meta['signal_confidence'])&.to_f
      }
    end

    def exit_block(tracker)
      return nil if tracker.exited_at.blank?

      execution_meta = tracker.execution.is_a?(Hash) ? tracker.execution : {}
      {
        exit_reason: tracker.exit_reason,
        exit_path: tracker.exit_path,
        exit_classification: execution_meta['classified_as'],
        exited_at: tracker.exited_at&.iso8601
      }
    end

    def trailing_state(tracker)
      meta = tracker.meta.is_a?(Hash) ? tracker.meta : {}
      raw_hwm = (tracker.respond_to?(:hwm_pnl_pct) ? tracker.hwm_pnl_pct : nil) || meta['hwm_pnl_pct']
      hwm_pct = raw_hwm&.to_f

      secured_sl = (tracker.respond_to?(:secured_sl_price) ? tracker.secured_sl_price : nil) || meta['premium_stop_price'] || meta['secured_sl_price']
      be_locked = (tracker.respond_to?(:breakeven_locked) ? tracker.breakeven_locked : nil) || meta['be_set'] || false
      pz_state = (tracker.respond_to?(:profit_zone_state) ? tracker.profit_zone_state : nil) || meta['profit_zone_state'] || 'active'

      {
        high_water_mark_pnl: tracker.high_water_mark_pnl&.to_f,
        hwm_pnl_pct: hwm_pct,
        secured_sl_price: secured_sl&.to_f&.round(2),
        breakeven_locked: be_locked,
        profit_zone_state: pz_state
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

    def fallback_symbol(tracker)
      meta_sym = tracker.meta&.dig('symbol')
      return meta_sym if meta_sym.present?

      tradable = tracker.tradable
      if tradable.respond_to?(:symbol_name) && tradable.symbol_name.present?
        return tradable.symbol_name
      end
      if tradable.respond_to?(:display_name) && tradable.display_name.present?
        return tradable.display_name
      end

      inst = tracker.instrument
      if inst && inst != tradable
        return inst.symbol_name if inst.respond_to?(:symbol_name) && inst.symbol_name.present?
        return inst.display_name if inst.respond_to?(:display_name) && inst.display_name.present?
      end

      nil
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

    # Tightest active stop, for display only — not the exit engine's decision path.
    def sl_price(tracker, entry)
      active_sl = (tracker.respond_to?(:secured_sl_price) ? tracker.secured_sl_price : nil) || tracker.meta&.dig('premium_stop_price') || tracker.trailing_stop_price || tracker.premium_stop_price
      val = active_sl.to_f
      return val.round(2) if val.positive?

      sl_pct = AlgoConfig.fetch.dig(:risk, :sl_pct) || 0.12
      entry.positive? ? (entry * (1.0 - sl_pct.to_f)).round(2) : nil
    end

    def tp_price(_tracker, entry)
      tp_pct = AlgoConfig.fetch.dig(:risk, :percentage_pnl_exit, :target_pct) || AlgoConfig.fetch.dig(:exit, :take_profit) || 0.05
      entry.positive? ? (entry * (1.0 + tp_pct.to_f)).round(2) : nil
    end
  end
end
