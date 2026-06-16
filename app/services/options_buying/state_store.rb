# frozen_string_literal: true

module OptionsBuying
  class StateStore
    PREFIX = 'options_buying'
    DEFAULT_BREAKOUT_TTL = 300
    METRICS_TTL = 86_400
    DEFAULT_STREAM_MAXLEN = 1000
    STREAM_GROUP = 'options_buying_evaluators'

    class << self
      def set_breakout_ready!(index_key, direction: :bullish, ttl_seconds: nil)
        ttl = ttl_seconds || breakout_ttl
        redis.set(breakout_key(index_key, direction), Time.current.to_i, ex: ttl)
      end

      def breakout_ready?(index_key, direction: :bullish)
        redis.exists?(breakout_key(index_key, direction))
      end

      def set_compression_arm!(index_key)
        redis.set(compression_arm_key(index_key), Time.current.to_i, ex: METRICS_TTL)
      end

      def compression_armed?(index_key)
        redis.exists?(compression_arm_key(index_key))
      end

      def set_daily_atr(index_key, atr)
        return unless atr.to_f.positive?

        redis.set(daily_atr_key(index_key), atr.to_f, ex: METRICS_TTL)
      end

      def daily_atr(index_key)
        val = redis.get(daily_atr_key(index_key))
        val&.to_f
      end

      def set_resistance(index_key, level)
        redis.set(resistance_key(index_key), level.to_f, ex: METRICS_TTL)
      end

      def resistance(index_key)
        val = redis.get(resistance_key(index_key))
        val&.to_f
      end

      def set_support(index_key, level)
        redis.set(support_key(index_key), level.to_f, ex: METRICS_TTL)
      end

      def support(index_key)
        val = redis.get(support_key(index_key))
        val&.to_f
      end

      def set_radar_strikes(index_key, strikes)
        redis.set(radar_key(index_key), strikes.to_json, ex: METRICS_TTL)
      end

      def radar_strikes(index_key)
        raw = redis.get(radar_key(index_key))
        return [] if raw.blank?

        JSON.parse(raw, symbolize_names: true)
      rescue JSON::ParserError
        []
      end

      def set_volume_rate_baseline(security_id, rate_per_minute)
        return unless rate_per_minute.to_f.positive?

        redis.set(volume_rate_baseline_key(security_id), rate_per_minute.to_f, ex: METRICS_TTL)
      end

      def volume_rate_baseline(security_id)
        val = redis.get(volume_rate_baseline_key(security_id))
        val&.to_f
      end

      def volume_threshold_baseline(security_id)
        rolling = rolling_volume_delta_avg(security_id)
        return rolling if rolling&.positive?

        volume_rate_baseline(security_id)
      end

      def rolling_volume_delta_avg(security_id, window_seconds: nil, min_samples: 3)
        window = window_seconds || (stream_window_seconds * 20)
        ticks = stream_window(security_id, window_seconds: window)
        TickMetrics.mean_interval_volume_delta(ticks, min_samples: min_samples)
      end

      def set_volume_avg(security_id, avg)
        redis.set(volume_avg_key(security_id), avg.to_f, ex: METRICS_TTL)
      end

      def volume_avg(security_id)
        val = redis.get(volume_avg_key(security_id))
        val&.to_f
      end

      def set_rsi_bias(index_key, bias)
        redis.set(rsi_bias_key(index_key), bias.to_s, ex: METRICS_TTL)
      end

      def rsi_bias(index_key)
        redis.get(rsi_bias_key(index_key))&.to_sym
      end

      def append_minute_tick(security_id, bucket, payload)
        key = minute_ticks_key(security_id, bucket)
        redis.zadd(key, payload[:ts].to_i, payload.to_json)
        redis.expire(key, 3600)
      end

      def minute_ticks(security_id, bucket)
        redis.zrange(minute_ticks_key(security_id, bucket), 0, -1).map do |raw|
          JSON.parse(raw, symbolize_names: true)
        end
      rescue JSON::ParserError
        []
      end

      def xadd_tick(security_id, payload)
        fields = stream_fields(payload)
        redis.xadd(
          stream_key(security_id),
          fields,
          maxlen: stream_maxlen,
          approximate: true
        )
      end

      def cache_tick_snapshot(security_id, payload)
        redis.hset(cache_key(security_id), stream_fields(payload))
        redis.expire(cache_key(security_id), METRICS_TTL)
      end

      def track_monitored_strike(security_id)
        redis.sadd(monitored_strikes_key, security_id.to_s)
        redis.expire(monitored_strikes_key, METRICS_TTL)
      end

      def monitored_strikes
        redis.smembers(monitored_strikes_key)
      end

      def ensure_stream_group!(security_id, group_name: stream_group_name)
        redis.xgroup(:create, stream_key(security_id), group_name, '$', mkstream: true)
      rescue Redis::CommandError => e
        raise unless e.message.include?('BUSYGROUP')
      end

      def xreadgroup(security_id, group_name: stream_group_name, consumer_name: 'processor_1', count: 10,
                     block_ms: stream_block_ms)
        redis.xreadgroup(
          group_name,
          consumer_name,
          stream_key(security_id),
          '>',
          count: count,
          block: block_ms
        )
      end

      def xack(security_id, message_id, group_name: stream_group_name)
        redis.xack(stream_key(security_id), group_name, message_id)
      end

      def stream_window(security_id, window_seconds: nil)
        window = window_seconds || stream_window_seconds
        cutoff_ms = (Time.current.to_i - window) * 1000
        min_id = "#{cutoff_ms}-0"
        entries = redis.xrange(stream_key(security_id), min_id, '+')
        entries.filter_map do |_id, fields|
          parse_stream_entry(fields)
        end
      rescue StandardError => e
        Rails.logger.warn("[StateStore] stream_window failed sec=#{security_id} #{e.class} - #{e.message}")
        []
      end

      def parse_stream_message(fields)
        parse_stream_entry(fields)
      end

      def stream_key_for(security_id)
        stream_key(security_id)
      end

      def cache_snapshot(security_id)
        raw = redis.hgetall(cache_key(security_id))
        return nil if raw.blank?

        parse_stream_entry(raw)
      end

      # Most liquid strike for the index. With type: 'CE'/'PE' restricts to that
      # option type (used to arm bullish vs bearish breakouts independently).
      def primary_radar_strike(index_key, type: nil)
        strikes = radar_strikes(index_key)
        strikes = strikes.select { |s| s[:type].to_s.upcase == type.to_s.upcase } if type
        return nil if strikes.blank?

        strikes.max_by { |s| s[:volume].to_i }
      end

      private

      def stream_fields(payload)
        {
          'ltp' => payload[:ltp].to_f,
          'oi' => payload[:oi].to_i,
          'volume' => (payload[:volume] || payload[:vol]).to_i,
          'ts' => payload[:ts].to_i,
          'bucket' => payload[:bucket].to_i
        }
      end

      def parse_stream_entry(fields)
        normalized = fields.transform_keys(&:to_sym)
        {
          ltp: normalized[:ltp].to_f,
          oi: normalized[:oi].to_i,
          vol: normalized[:volume].to_i,
          volume: normalized[:volume].to_i,
          ts: normalized[:ts].to_i,
          bucket: normalized[:bucket].to_i
        }
      end

      def stream_maxlen
        (Mode.config.dig(:streams, :maxlen) || DEFAULT_STREAM_MAXLEN).to_i
      end

      def stream_group_name
        Mode.config.dig(:streams, :consumer_group).presence || STREAM_GROUP
      end

      def stream_block_ms
        (Mode.config.dig(:streams, :consumer_block_ms) || 1000).to_i
      end

      def stream_window_seconds
        (Mode.config.dig(:streams, :window_seconds) || 60).to_i
      end

      def stream_key(security_id) = "#{PREFIX}:stream:#{security_id}"
      def cache_key(security_id) = "#{PREFIX}:cache:#{security_id}"
      def monitored_strikes_key = "#{PREFIX}:monitored_strikes"

      # Per-thread connection. StreamConsumer (own thread), the BreakoutWatcher
      # tick callback thread, and Solid Queue job threads all reach StateStore
      # concurrently; a redis-rb client is not safe to share across threads.
      def redis
        Thread.current[:options_buying_redis] ||=
          Redis.new(url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379/0'))
      end

      def breakout_ttl
        (Mode.config.dig(:breakout, :ready_ttl_seconds) || DEFAULT_BREAKOUT_TTL).to_i
      end

      def breakout_key(index_key, direction = :bullish) = "#{PREFIX}:breakout_ready:#{direction}:#{index_key}"
      def compression_arm_key(index_key) = "#{PREFIX}:compression_arm:#{index_key}"
      def daily_atr_key(index_key) = "#{PREFIX}:daily_atr:#{index_key}"
      def resistance_key(index_key) = "#{PREFIX}:resistance:#{index_key}"
      def support_key(index_key) = "#{PREFIX}:support:#{index_key}"
      def radar_key(index_key) = "#{PREFIX}:radar:#{index_key}"
      def volume_avg_key(security_id) = "#{PREFIX}:volume_avg:#{security_id}"
      def volume_rate_baseline_key(security_id) = "#{PREFIX}:volume_rate_baseline:#{security_id}"
      def rsi_bias_key(index_key) = "#{PREFIX}:rsi_bias:#{index_key}"
      def minute_ticks_key(security_id, bucket) = "#{PREFIX}:ticks:#{security_id}:#{bucket}"
    end
  end
end
