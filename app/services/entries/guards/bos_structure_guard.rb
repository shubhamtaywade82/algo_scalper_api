# frozen_string_literal: true

module Entries
  module Guards
    class BosStructureGuard
      include BaseGuard

      # Constants from EntryGuard (temporary duplicate or move to a common location)
      BOS_SWING_LOOKBACK = 5
      BOS_MAX_AGE_CANDLES = 8
      BOS_MAX_ENTRY_DELAY_CANDLES = 3
      BOS_MAX_ENTRY_DISTANCE_R = 0.5
      SUPERTREND_CONTRACT = 'supertrend_machine_v1'

      def self.call(context)
        new(context).call
      end

      def self.enforce_structure_gate(index_cfg:, instrument:, direction:, entry_price:, entry_metadata:)
        context = {
          index_cfg: index_cfg,
          instrument: instrument,
          direction: direction,
          ltp: entry_price,
          entry_metadata: entry_metadata
        }
        new(context).send(:enforce_structure_gate)
      end

      def initialize(context)
        @context = context
        @index_cfg = context[:index_cfg]
        @instrument = context[:instrument]
        @direction = context[:direction]
        @ltp = context[:ltp]
        @entry_metadata = context[:entry_metadata]
      end

      def call
        return PASS if supertrend_mode?

        bos_context = enforce_structure_gate
        if bos_context
          @context[:bos_context] = bos_context
          PASS
        else
          { blocked: 'bos_structure_gate' }
        end
      end

      private

      def supertrend_mode?
        @entry_metadata&.dig(:entry_contract).to_s == SUPERTREND_CONTRACT
      end

      def enforce_structure_gate
        timeframe = effective_timeframe
        return nil unless timeframe

        interval = timeframe_to_interval(timeframe)
        return nil unless interval

        series = @instrument.candle_series(interval: interval)
        return nil unless series&.candles&.any?

        bos = Entries::BosExtractor.last_confirmed_bos(series, lookback: BOS_SWING_LOOKBACK)
        return nil unless bos && bos[:direction] == @direction

        last_idx = series.candles.size - 1
        bos_age = last_idx - bos[:confirmed_index]
        return nil if bos_age > BOS_MAX_AGE_CANDLES || bos_age > BOS_MAX_ENTRY_DELAY_CANDLES

        origin_price = bos[:origin_swing][:price].to_f
        broken_price = bos[:broken_swing][:price].to_f
        risk_points = (broken_price - origin_price).abs
        return nil if risk_points <= 0

        entry_underlying_price = series.candles.last&.close
        return nil unless entry_underlying_price

        entry_distance_r = (entry_underlying_price.to_f - origin_price).abs / risk_points
        return nil if entry_distance_r > BOS_MAX_ENTRY_DISTANCE_R

        bos_id = Entries::BosExtractor.bos_id(timeframe: timeframe, confirmed_at: bos[:confirmed_at], direction: bos[:direction])
        return nil if bos_consumed?(bos_id)

        bos.merge(
          timeframe: timeframe,
          bos_id: bos_id,
          entry_distance_r: entry_distance_r,
          risk_points: risk_points,
          entry_underlying_price: entry_underlying_price
        )
      end

      def effective_timeframe
        return nil unless @entry_metadata.is_a?(Hash)
        @entry_metadata[:effective_timeframe] || @entry_metadata[:primary_timeframe]
      end

      def timeframe_to_interval(timeframe)
        Entries::EntryGuard.timeframe_to_interval(timeframe)
      end

      def bos_consumed?(bos_id)
        Rails.cache.read("bos:consumed:#{@index_cfg[:key]}:#{bos_id}") == true
      end
    end
  end
end
