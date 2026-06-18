# frozen_string_literal: true

module OptionsBuying
  class BreakoutEvaluator
    MIN_STREAM_TICKS = 5

    def self.evaluate!(index_key:, security_id:, bucket:)
      new(index_key: index_key, security_id: security_id, bucket: bucket).evaluate!
    end

    def self.evaluate_stream_tick!(index_key:, security_id:, current_tick:)
      new(index_key: index_key, security_id: security_id, bucket: nil, current_tick: current_tick).evaluate_stream_tick!
    end

    def initialize(index_key:, security_id:, bucket: nil, current_tick: nil)
      @index_key = index_key.to_s.upcase
      @security_id = security_id.to_s
      @bucket = bucket&.to_i
      @current_tick = current_tick
    end

    def evaluate!
      return unless Mode.breakout_enabled?

      ticks = StateStore.minute_ticks(@security_id, @bucket)
      evaluate_ticks!(ticks)
    rescue StandardError => e
      Rails.logger.warn("[BreakoutEvaluator] #{@index_key} #{e.class} - #{e.message}")
      nil
    end

    def evaluate_stream_tick!
      return unless Mode.breakout_enabled?
      return unless Mode.streams_enabled?

      ticks = StateStore.stream_window(@security_id)
      ticks << @current_tick if @current_tick
      evaluate_ticks!(ticks.uniq { |t| t[:ts] })
    rescue StandardError => e
      Rails.logger.warn("[BreakoutEvaluator] stream #{@index_key} #{e.class} - #{e.message}")
      nil
    end

    private

    def evaluate_ticks!(trigger_ticks)
      directions_for_trigger.each { |direction| evaluate_direction!(trigger_ticks, direction) }
    end

    # Bullish breakout = spot breaks ABOVE the CE call-wall resistance (long CE).
    # Bearish breakdown = spot breaks BELOW the PE put-wall support (long PE).
    # When the trigger is the index itself we evaluate both; when it is a specific
    # option strike we evaluate only the direction matching that strike's type.
    def directions_for_trigger
      if index_security?
        %i[bullish bearish]
      else
        case strike_type(@security_id)
        when 'PE' then %i[bearish]
        else %i[bullish]
        end
      end
    end

    def evaluate_direction!(trigger_ticks, direction)
      option_type = direction == :bullish ? 'CE' : 'PE'
      level = direction == :bullish ? StateStore.resistance(@index_key) : StateStore.support(@index_key)
      option_sid = option_security_id(option_type)
      return unless level&.positive? && option_sid.present?

      volume_baseline = StateStore.volume_threshold_baseline(option_sid)
      return unless volume_baseline&.positive?

      spot_ltp = spot_price(trigger_ticks)
      return unless spot_ltp.positive?

      option_ticks = option_metric_ticks(trigger_ticks, option_sid)
      min_ticks = stream_path? ? MIN_STREAM_TICKS : 2
      return if option_ticks.size < min_ticks

      volume_delta = TickMetrics.volume_delta(option_ticks)
      oi_delta = TickMetrics.oi_delta(option_ticks)
      volume_multiplier = (Mode.config.dig(:breakout, :volume_multiplier) || 2.0).to_f
      level_broken = direction == :bullish ? spot_ltp > level : spot_ltp < level
      return unless level_broken && volume_delta > (volume_baseline * volume_multiplier)
      return if require_oi_unwind? && !oi_delta.negative?

      arm_breakout!(
        direction: direction,
        option_security_id: option_sid,
        metrics: {
          direction: direction,
          spot_ltp: spot_ltp,
          volume_delta: volume_delta,
          volume_baseline: volume_baseline,
          oi_delta: oi_delta,
          level: level,
          volume_multiplier: volume_multiplier,
          option_tick_count: option_ticks.size
        }
      )
    end

    def strike_type(security_id)
      StateStore.radar_strikes(@index_key)
                .find { |s| s[:security_id].to_s == security_id.to_s }
                &.dig(:type).to_s.upcase.presence
    end

    def spot_price(trigger_ticks)
      if index_security?
        TickMetrics.close_price(trigger_ticks)
      else
        cached_spot_ltp.positive? ? cached_spot_ltp : live_index_spot_ltp
      end
    end

    def cached_spot_ltp
      StateStore.cache_snapshot(index_security_id)&.dig(:ltp).to_f
    end

    def live_index_spot_ltp
      idx = IndexConfigLoader.load_indices.find { |c| c[:key].to_s.upcase == @index_key }
      return 0.0 unless idx

      tick = Live::TickQuery.for_security(segment: idx[:segment], security_id: idx[:sid])
      tick ? tick.ltp.to_f : 0.0
    end

    def index_security?
      @security_id == index_security_id
    end

    def index_security_id
      @index_security_id ||= begin
        idx = IndexConfigLoader.load_indices.find { |c| c[:key].to_s.upcase == @index_key }
        idx&.dig(:sid).to_s
      end
    end

    def option_security_id(option_type)
      return @security_id unless index_security?

      StateStore.primary_radar_strike(@index_key, type: option_type)&.dig(:security_id).to_s.presence
    end

    def option_metric_ticks(trigger_ticks, option_sid)
      if @security_id == option_sid
        trigger_ticks
      elsif stream_path?
        StateStore.stream_window(option_sid)
      else
        []
      end
    end

    def stream_path?
      @bucket.nil?
    end

    def require_oi_unwind?
      Mode.config.dig(:breakout, :require_oi_unwind) != false
    end

    def arm_breakout!(direction:, option_security_id:, metrics:)
      if compression_arm_required? && !StateStore.compression_armed?(@index_key)
        return
      end

      already_armed = StateStore.breakout_ready?(@index_key, direction: direction)
      StateStore.set_breakout_ready!(@index_key, direction: direction)
      sink_telemetry!(direction: direction, option_security_id: option_security_id, metrics: metrics) unless already_armed
      Rails.logger.info(
        "[BreakoutEvaluator] breakout_ready #{direction} #{@index_key} spot=#{metrics[:spot_ltp].round(2)} " \
        "level=#{metrics[:level]} sec=#{option_security_id} " \
        "vol_delta=#{metrics[:volume_delta]} oi_delta=#{metrics[:oi_delta]}"
      )
    end

    def sink_telemetry!(direction:, option_security_id:, metrics:)
      return unless Mode.telemetry_sink_enabled?

      OptionsBuying::TelemetrySinkJob.perform_later(
        index_key: @index_key,
        security_id: option_security_id,
        event_type: direction == :bullish ? 'breakout_armed_ce' : 'breakout_armed_pe',
        occurred_at: Time.current.iso8601,
        metadata: metrics
      )
    rescue StandardError => e
      Rails.logger.warn("[BreakoutEvaluator] telemetry enqueue failed #{e.class} - #{e.message}")
    end

    def compression_arm_required?
      Mode.intraday? && Mode.config.dig(:breakout, :compression_arm) == true
    end
  end
end
