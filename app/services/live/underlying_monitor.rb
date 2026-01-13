# frozen_string_literal: true

require 'ostruct'
require 'concurrent/map'

module Live
  class UnderlyingMonitor
    CACHE_TTL = 0.25 # seconds

    class << self
      def evaluate(position_data)
        return default_state unless position_data

        key = cache_key_for(position_data)
        now = monotonic_now
        cached = cache[key]
        return cached[:state] if cached && (now - cached[:at]) < CACHE_TTL

        state = compute_state(position_data)
        cache[key] = { state: state, at: now }
        state
      rescue StandardError => e
        Rails.logger.error("[UnderlyingMonitor] evaluate failed: #{e.class} - #{e.message}")
        default_state
      end

      def reset_cache!
        cache.clear
      end

      private

      def compute_state(position_data)
        index_cfg = determine_index_cfg(position_data)
        instrument = index_cfg ? IndexInstrumentCache.instance.get_or_fetch(index_cfg) : nil
        candles = instrument&.candle_series(interval: primary_timeframe_interval)
        ltp = latest_underlying_ltp(index_cfg, position_data)

        trend_result = trend_direction(index_cfg)
        trend_score = trend_result[:trend_score]
        mtf_confirm = mtf_confirmed?(trend_result)

        bos_state, bos_direction = structure_state(candles, normalized_direction(position_data))
        _atr_value, atr_ratio, atr_trend = atr_snapshot(candles)

        OpenStruct.new(
          trend_score: trend_score,
          bos_state: bos_state,
          bos_direction: bos_direction,
          atr_trend: atr_trend,
          atr_ratio: atr_ratio,
          mtf_confirm: mtf_confirm,
          ltp: ltp
        )
      rescue StandardError => e
        Rails.logger.error("[UnderlyingMonitor] compute_state failed: #{e.class} - #{e.message}")
        default_state
      end

      def default_state
        OpenStruct.new(
          trend_score: nil,
          bos_state: :unknown,
          bos_direction: :neutral,
          atr_trend: :unknown,
          atr_ratio: nil,
          mtf_confirm: false,
          ltp: nil
        )
      end

      def cache
        @cache ||= Concurrent::Map.new
      end

      def cache_key_for(position_data)
        [
          position_data.tracker_id,
          position_data.underlying_segment,
          position_data.underlying_security_id
        ].compact.join(':')
      end

      def monotonic_now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def determine_index_cfg(position_data)
        sid = position_data.underlying_security_id
        segment = position_data.underlying_segment
        index_key = position_data.index_key || position_data.underlying_symbol

        return { key: index_key, segment: segment, sid: sid } if sid.present? && segment.present? && index_key.present?

        cfg = Positions::MetadataResolver.index_config_for_key(index_key)
        return unless cfg

        {
          key: cfg[:key] || cfg['key'],
          segment: segment.presence || cfg[:segment] || cfg['segment'],
          sid: sid.presence || cfg[:sid] || cfg['sid']
        }
      rescue StandardError => e
        Rails.logger.error("[UnderlyingMonitor] determine_index_cfg failed: #{e.class} - #{e.message}")
        nil
      end

      def trend_direction(index_cfg)
        return default_trend_result unless index_cfg

        Signal::TrendScorer.compute_direction(
          index_cfg: index_cfg.symbolize_keys,
          primary_tf: primary_timeframe,
          confirmation_tf: confirmation_timeframe
        )
      rescue StandardError => e
        Rails.logger.error("[UnderlyingMonitor] trend_direction failed: #{e.class} - #{e.message}")
        default_trend_result
      end

      def default_trend_result
        { trend_score: nil, breakdown: { mtf: 0 } }
      end

      def mtf_confirmed?(trend_result)
        breakdown = trend_result[:breakdown] || {}
        breakdown[:mtf].to_f >= 3.0
      end

      def structure_state(candles, direction)
        return %i[unknown neutral] unless candles.respond_to?(:candles) && candles.candles.any?

        last_close = candles.candles.last.close
        case direction
        when :bearish
          swing_high = candles.respond_to?(:previous_swing_high) ? candles.previous_swing_high : nil
          if swing_high && last_close > swing_high
            %i[broken bullish]
          else
            %i[intact neutral]
          end
        else
          swing_low = candles.respond_to?(:previous_swing_low) ? candles.previous_swing_low : nil
          if swing_low && last_close < swing_low
            %i[broken bearish]
          else
            %i[intact neutral]
          end
        end
      rescue StandardError => e
        Rails.logger.error("[UnderlyingMonitor] structure_state failed: #{e.class} - #{e.message}")
        %i[unknown neutral]
      end

      def atr_snapshot(candles, period = 14)
        return [nil, nil, :unknown] unless candles.respond_to?(:candles)

        data = candles.candles
        return [nil, nil, :unknown] if data.size < (period * 2)

        recent = data.last(period + 1)
        previous = data.slice(-((2 * period) + 1), period + 1)
        atr_now = average_true_range(recent)
        atr_prev = average_true_range(previous)
        ratio = (atr_now.to_f / atr_prev if atr_prev.to_f.positive?)
        trend =
          if ratio && ratio < 0.85
            :falling
          elsif ratio && ratio > 1.1
            :rising
          else
            :flat
          end
        [atr_now, ratio, trend]
      rescue StandardError => e
        Rails.logger.error("[UnderlyingMonitor] atr_snapshot failed: #{e.class} - #{e.message}")
        [nil, nil, :unknown]
      end

      def average_true_range(candles)
        return nil unless candles&.size&.>=(2)

        trs = []
        candles.each_cons(2) do |prev, curr|
          next unless prev && curr

          high_low = curr.high.to_f - curr.low.to_f
          high_close = (curr.high.to_f - prev.close.to_f).abs
          low_close = (curr.low.to_f - prev.close.to_f).abs
          trs << [high_low, high_close, low_close].max
        end
        return nil if trs.empty?

        trs.sum / trs.size.to_f
      end

      def latest_underlying_ltp(index_cfg, position_data)
        return position_data.underlying_ltp if position_data.underlying_ltp.to_f.positive?
        return nil unless index_cfg

        Live::TickCache.ltp(index_cfg[:segment], index_cfg[:sid])
      rescue StandardError
        nil
      end

      def normalized_direction(position_data)
        (position_data.position_direction || :bullish).to_sym
      end

      def primary_timeframe
        signals_cfg[:primary_timeframe] || '1m'
      end

      def primary_timeframe_interval
        primary_timeframe.gsub(/[^0-9]/, '').presence || '1'
      end

      def confirmation_timeframe
        signals_cfg[:confirmation_timeframe] || '5m'
      end

      def signals_cfg
        AlgoConfig.fetch[:signals] || {}
      rescue StandardError
        {}
      end
    end
  end
end
