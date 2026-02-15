# frozen_string_literal: true

module Entries
  class BosEntryEngine
    BOS_SWING_LOOKBACK = 5
    BOS_MAX_AGE_CANDLES = 8
    BOS_MAX_ENTRY_DELAY_CANDLES = 3
    HTF_MAX_AGE_CANDLES = 20
    PULLBACK_MIN_RETRACE_PCT = 0.35
    PULLBACK_MAX_CANDLES = 5
    CONTINUATION_BODY_POSITION_MIN = 0.6

    class << self
      def run_for(index_cfg:, instrument:, direction:, picks:, entry_metadata:, permission:)
        timeframe = effective_timeframe(entry_metadata)
        return false unless timeframe

        interval = timeframe_to_interval(timeframe)
        return false unless interval

        series = instrument.candle_series(interval: interval)
        return false unless series&.candles&.any?

        state = load_state(index_cfg[:key], timeframe)

        bos = Entries::BosExtractor.last_confirmed_bos(series, lookback: BOS_SWING_LOOKBACK)
        return reset_state(index_cfg[:key], timeframe) unless bos

        bos_id = Entries::BosExtractor.bos_id(timeframe: timeframe, confirmed_at: bos[:confirmed_at], direction: bos[:direction])

        if state.nil? || state[:bos_id] != bos_id
          state = init_bos_state(bos, bos_id)
          store_state(index_cfg[:key], timeframe, state)
        end

        return reset_state(index_cfg[:key], timeframe) if bos_stale?(series, state)
        return reset_state(index_cfg[:key], timeframe) if opposite_direction?(state, direction)

        case state[:state]
        when 'bos_confirmed'
          next_state = handle_pullback_detection(series, state)
          store_state(index_cfg[:key], timeframe, next_state)
        when 'pullback'
          outcome = handle_continuation(series, state, index_cfg, instrument, direction, picks, entry_metadata, permission, timeframe)
          return outcome if outcome == true
        end

        false
      rescue StandardError => e
        Rails.logger.error("[BosEntryEngine] #{index_cfg[:key]} failed: #{e.class} - #{e.message}")
        false
      end

      private

      def handle_pullback_detection(series, state)
        candles = series.candles
        confirmed_index = state[:confirmed_index]
        return state unless confirmed_index

        slice = candles[confirmed_index..]
        return state if slice.blank?

        origin_price = state[:origin_price].to_f
        bos_level = state[:bos_level].to_f
        leg = (bos_level - origin_price).abs
        return state if leg <= 0

        retrace_pct = pullback_retrace_pct(state[:direction], bos_level, origin_price, slice)
        opposite_close = opposite_close_found?(state[:direction], slice)

        lowest_low = slice.map(&:low).min
        highest_high = slice.map(&:high).max
        origin_broken = origin_broken?(state[:direction], origin_price, lowest_low, highest_high)
        return reset_pullback_state(state) if origin_broken

        return state unless retrace_pct >= PULLBACK_MIN_RETRACE_PCT && opposite_close

        pullback_high =
          if state[:direction] == :bullish
            slice.map(&:high).max
          else
            slice.map(&:low).min
          end
        state.merge(
          state: 'pullback',
          pullback_started_at_index: candles.size - 1,
          pullback_high: pullback_high,
          pullback_retrace_pct: retrace_pct
        )
      end

      def handle_continuation(series, state, index_cfg, instrument, direction, picks, entry_metadata, permission, timeframe)
        candles = series.candles
        current_idx = candles.size - 1

        pullback_started_at = state[:pullback_started_at_index]
        return reset_state(index_cfg[:key], timeframe) if pullback_started_at.nil?

        if (current_idx - pullback_started_at) > PULLBACK_MAX_CANDLES
          return reset_state(index_cfg[:key], timeframe)
        end

        origin_price = state[:origin_price].to_f
        current_candle = candles.last

        origin_broken = origin_broken?(state[:direction], origin_price, current_candle.low, current_candle.high)
        return reset_state(index_cfg[:key], timeframe) if origin_broken

        pullback_level = state[:pullback_high].to_f
        body_position = candle_body_position(current_candle)

        if continuation_triggered?(state[:direction], current_candle.close, pullback_level, body_position)
          bias_ok = htf_bias_allows?(instrument: instrument, entry_timeframe: timeframe, direction: direction)
          unless bias_ok
            consume_bos(index_cfg[:key], state[:bos_id])
            reset_state(index_cfg[:key], timeframe)
            return false
          end

          entry_metadata = enrich_entry_metadata(
            entry_metadata,
            state,
            series,
            current_idx,
            current_candle,
            timeframe
          )

          entered = attempt_entry(index_cfg, direction, picks, entry_metadata, permission)
          consume_bos(index_cfg[:key], state[:bos_id])
          reset_state(index_cfg[:key], timeframe)
          return entered
        end

        updated_level = update_pullback_level(state[:direction], pullback_level, current_candle)
        updated = state.merge(pullback_high: updated_level)
        store_state(index_cfg[:key], timeframe, updated)
        false
      end

      def attempt_entry(index_cfg, direction, picks, entry_metadata, permission)
        picks.each do |pick|
          result = Entries::EntryGuard.try_enter(
            index_cfg: index_cfg,
            pick: pick,
            direction: direction,
            scale_multiplier: 1,
            entry_metadata: entry_metadata,
            permission: permission
          )
          return true if result
        end
        false
      end

      def init_bos_state(bos, bos_id)
        {
          state: 'bos_confirmed',
          bos_id: bos_id,
          direction: bos[:direction],
          bos_level: bos[:broken_swing][:price],
          origin_price: bos[:origin_swing][:price],
          confirmed_index: bos[:confirmed_index],
          confirmed_at: bos[:confirmed_at],
          pullback_started_at_index: nil,
          pullback_high: nil,
          pullback_retrace_pct: nil
        }
      end

      def bos_stale?(series, state)
        last_idx = series.candles.size - 1
        confirmed_index = state[:confirmed_index]
        return true if confirmed_index.nil?

        (last_idx - confirmed_index) > BOS_MAX_AGE_CANDLES
      end

      def opposite_direction?(state, direction)
        state[:direction] && direction && state[:direction].to_sym != direction.to_sym
      end

      def pullback_retrace_pct(direction, bos_level, origin_price, candles)
        if direction == :bullish
          lowest_low = candles.map(&:low).min.to_f
          retrace = bos_level.to_f - lowest_low
        else
          highest_high = candles.map(&:high).max.to_f
          retrace = highest_high - bos_level.to_f
        end

        leg = (bos_level.to_f - origin_price.to_f).abs
        return 0 if leg <= 0

        retrace / leg
      end

      def enrich_entry_metadata(entry_metadata, state, series, current_idx, current_candle, timeframe)
        data = entry_metadata.is_a?(Hash) ? entry_metadata.dup : {}

        bos_age = current_idx - state[:confirmed_index].to_i
        pullback_candles = current_idx - state[:pullback_started_at_index].to_i
        bos_level = state[:bos_level].to_f
        origin_price = state[:origin_price].to_f
        leg = (bos_level - origin_price).abs
        entry_distance_r = leg.positive? ? ((current_candle.close.to_f - origin_price).abs / leg) : nil

        time_from_bos = nil
        if state[:confirmed_at].respond_to?(:to_i) && current_candle.timestamp
          time_from_bos = (current_candle.timestamp.to_i - state[:confirmed_at].to_i)
        end

        data[:bos_age_at_entry] = bos_age
        data[:retrace_pct] = state[:pullback_retrace_pct]
        data[:pullback_candles] = pullback_candles
        data[:entry_distance_r] = entry_distance_r
        data[:continuation_body_position] = candle_body_position(current_candle)
        data[:time_from_bos_to_entry] = time_from_bos
        data[:entry_tf] = timeframe
        data[:htf_tf] = htf_timeframe_for(timeframe)

        data
      end

      def opposite_close_found?(direction, candles)
        candles.each_cons(2).any? do |prev, curr|
          if direction == :bullish
            curr.close.to_f < prev.close.to_f
          else
            curr.close.to_f > prev.close.to_f
          end
        end
      end

      def origin_broken?(direction, origin_price, low, high)
        if direction == :bullish
          low.to_f <= origin_price.to_f
        else
          high.to_f >= origin_price.to_f
        end
      end

      def candle_body_position(candle)
        range = candle.high.to_f - candle.low.to_f
        return 0.5 if range <= 0

        (candle.close.to_f - candle.low.to_f) / range
      end

      def continuation_triggered?(direction, close, pullback_level, body_position)
        if direction == :bullish
          close.to_f > pullback_level.to_f && body_position >= CONTINUATION_BODY_POSITION_MIN
        else
          close.to_f < pullback_level.to_f && body_position <= (1 - CONTINUATION_BODY_POSITION_MIN)
        end
      end

      def update_pullback_level(direction, current_level, candle)
        if direction == :bullish
          [current_level.to_f, candle.high.to_f].max
        else
          [current_level.to_f, candle.low.to_f].min
        end
      end

      def reset_state(index_key, timeframe)
        Rails.cache.delete(state_key(index_key, timeframe))
        false
      end

      def reset_pullback_state(state)
        state.merge(state: 'bos_confirmed', pullback_started_at_index: nil, pullback_high: nil)
      end

      def load_state(index_key, timeframe)
        Rails.cache.read(state_key(index_key, timeframe))
      rescue StandardError
        nil
      end

      def store_state(index_key, timeframe, state)
        Rails.cache.write(state_key(index_key, timeframe), state, expires_in: 2.hours)
        state
      rescue StandardError
        state
      end

      def state_key(index_key, timeframe)
        "bos_machine:#{index_key}:#{timeframe}"
      end

      def consume_bos(index_key, bos_id)
        return unless bos_id

        Rails.cache.write("bos:consumed:#{index_key}:#{bos_id}", true, expires_in: 2.hours)
      rescue StandardError => e
        Rails.logger.error("[BosEntryEngine] Failed to consume BOS for #{index_key}: #{e.class} - #{e.message}")
      end

      def effective_timeframe(entry_metadata)
        return nil unless entry_metadata.is_a?(Hash)

        entry_metadata[:effective_timeframe] || entry_metadata[:primary_timeframe]
      end

      def timeframe_to_interval(timeframe)
        return nil if timeframe.blank?

        minutes = timeframe_to_minutes(timeframe)
        return nil unless minutes

        minutes.to_s
      end

      def timeframe_to_minutes(timeframe)
        str = timeframe.to_s.strip.downcase
        return nil if str.empty?

        if str.end_with?('h')
          hours = str.gsub(/[^0-9]/, '').to_i
          return nil if hours <= 0

          hours * 60
        else
          minutes = str.gsub(/[^0-9]/, '').to_i
          return nil if minutes <= 0

          minutes
        end
      end

      def htf_timeframe_for(timeframe)
        minutes = timeframe_to_minutes(timeframe)
        return nil unless minutes

        htf_minutes = case minutes
                      when 1 then 5
                      when 5 then 15
                      when 15 then 60
                      else minutes * 3
                      end

        if (htf_minutes % 60).zero?
          "#{htf_minutes / 60}h"
        else
          "#{htf_minutes}m"
        end
      end

      def htf_bias_allows?(instrument:, entry_timeframe:, direction:)
        htf_tf = htf_timeframe_for(entry_timeframe)
        return false unless htf_tf

        interval = timeframe_to_interval(htf_tf)
        return false unless interval

        series = instrument.candle_series(interval: interval)
        return false unless series&.candles&.any?

        bos = Entries::BosExtractor.last_confirmed_bos(series, lookback: BOS_SWING_LOOKBACK)
        return false unless bos

        last_idx = series.candles.size - 1
        age = last_idx - bos[:confirmed_index].to_i
        return false if age > HTF_MAX_AGE_CANDLES

        bos[:direction].to_sym == direction.to_sym
      rescue StandardError => e
        Rails.logger.error("[BosEntryEngine] HTF bias check failed: #{e.class} - #{e.message}")
        false
      end
    end
  end
end
