# frozen_string_literal: true

module Entries
  module Guards
    class ExposureGuard
      class << self
        def call(context)
          index_cfg = context[:index_cfg]
          instrument = context[:instrument]
          direction = context[:direction]
          side = direction == :bullish ? 'long_ce' : 'long_pe'
          is_supertrend = context[:entry_metadata]&.dig(:entry_contract).to_s == EntryGuard::SUPERTREND_CONTRACT

          context[:side] = side
          context[:is_supertrend] = is_supertrend

          if is_supertrend
            return { blocked: "Supertrend: active position already exists for #{index_cfg[:key]}" } if active_supertrend_position?(index_cfg[:key])

            return EntryGuardPipeline::PASS
          end

          return EntryGuardPipeline::PASS if exposure_ok?(
            instrument: instrument,
            side: side,
            max_same_side: index_cfg[:max_same_side]
          )

          { blocked: "exposure limit for #{index_cfg[:key]} (#{side})" }
        end

        def exposure_ok?(instrument:, side:, max_same_side:)
          max_allowed = max_same_side.to_i
          max_allowed = 1 if max_allowed <= 0

          active_positions = PositionTracker.active.where(side: side).where(
            "(instrument_id = ? OR (watchable_type = 'Derivative' AND watchable_id IN (SELECT id FROM derivatives WHERE instrument_id = ?)))",
            instrument.id, instrument.id
          ).limit(max_allowed + 1)
          current_count = active_positions.count

          return false if current_count >= max_allowed

          if current_count == 1
            first_position = active_positions.first
            first_position.reload
            first_position.hydrate_pnl_from_cache!

            if (first_position.last_pnl_rupees.nil? || first_position.last_pnl_rupees.zero?) && first_position.entry_price.present? && first_position.quantity.present?
              calculate_current_pnl(first_position)
              first_position.reload
            end

            return false unless pyramiding_allowed?(first_position)
          end

          true
        end

        private

        def pyramiding_allowed?(first_position)
          return false unless first_position.last_pnl_rupees&.positive?
          min_profit_duration = 5.minutes
          first_position.updated_at < min_profit_duration.ago
        rescue StandardError
          false
        end

        def calculate_current_pnl(tracker)
          return unless tracker.entry_price.present? && tracker.quantity.present?

          if tracker.paper?
            ltp = get_paper_ltp_for_tracker(tracker)
            return unless ltp

            entry = BigDecimal(tracker.entry_price.to_s)
            exit_price = BigDecimal(ltp.to_s)
            qty = tracker.quantity.to_i
            gross_pnl = (exit_price - entry) * qty
            pnl = BrokerFeeCalculator.net_pnl(gross_pnl, is_exited: tracker.exited?)
            pnl_pct = entry.positive? ? ((exit_price - entry) / entry) : 0
            hwm = [tracker.high_water_mark_pnl || 0, pnl].max

            tracker.update!(last_pnl_rupees: pnl, last_pnl_pct: BigDecimal(pnl_pct.to_s), high_water_mark_pnl: hwm)
            return
          end

          pnl_cache = Live::RedisPnlCache.instance.fetch_pnl(tracker.id)
          if pnl_cache && pnl_cache[:pnl]
            tracker.update!(
              last_pnl_rupees: BigDecimal(pnl_cache[:pnl].to_s),
              last_pnl_pct: pnl_cache[:pnl_pct] ? BigDecimal(pnl_cache[:pnl_pct].to_s) : nil,
              high_water_mark_pnl: pnl_cache[:hwm_pnl] ? BigDecimal(pnl_cache[:hwm_pnl].to_s) : tracker.high_water_mark_pnl
            )
            return
          end

          tick = Live::TickQuery.for_security(
            segment: tracker.segment.presence || tracker.watchable&.exchange_segment || tracker.instrument&.exchange_segment,
            security_id: tracker.security_id
          )
          if tick
            ltp = tick.ltp
            entry = BigDecimal(tracker.entry_price.to_s)
            qty = tracker.quantity.to_i
            pnl = (ltp - entry) * qty
            pnl_pct = entry.positive? ? ((ltp - entry) / entry) : nil
            hwm = [tracker.high_water_mark_pnl || 0, pnl].max

            tracker.update!(last_pnl_rupees: pnl, last_pnl_pct: pnl_pct ? BigDecimal(pnl_pct.to_s) : nil, high_water_mark_pnl: hwm)
          end
        end

        def get_paper_ltp_for_tracker(tracker)
          segment = tracker.segment.presence || tracker.watchable&.exchange_segment || tracker.instrument&.exchange_segment
          security_id = tracker.security_id
          return nil unless segment.present? && security_id.present?

          tick = Live::TickQuery.for_security(segment: segment, security_id: security_id)
          return tick.ltp if tick

          tradable = tracker.tradable
          if tradable
            ltp = tradable.fetch_ltp_from_api_for_segment(segment: segment, security_id: security_id)
            return BigDecimal(ltp.to_s) if ltp
          end
          nil
        end

        def active_supertrend_position?(index_key)
          PositionTracker.active.where("(meta->>'index_key') = ?", index_key.to_s).exists?
        end
      end
    end
  end
end
