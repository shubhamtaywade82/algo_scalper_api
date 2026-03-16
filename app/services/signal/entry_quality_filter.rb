# frozen_string_literal: true

module Signal
  class EntryQualityFilter
    DEFAULTS = {
      enforce: false,
      min_score: 40,
      gates: {
        min_adx: 20,
        block_choppy_regime: true,
        min_body_ratio: 0.40,
        require_momentum_confirm: true
      },
      scoring: {
        candle_body_weight: 25,
        adx_strength_weight: 20,
        bos_weight: 20,
        range_expansion_weight: 20,
        momentum_weight: 15
      },
      index_overrides: {}
    }.freeze

    class << self
      def evaluate(series:, supertrend_result:, adx_value:, direction:, regime:, index_key:)
        config = load_config(index_key)
        enforce = config[:enforce]
        candles = series&.candles || []

        # Edge case: no data
        if candles.empty?
          result = reject_result('no_candle_data')
          return enforce ? result : result.merge(pass: true)
        end
        if supertrend_result.nil?
          result = reject_result('no_supertrend_data')
          return enforce ? result : result.merge(pass: true)
        end

        # Phase 1: Hard gates
        gate_result = check_gates(candles, supertrend_result, adx_value, direction, regime, config)
        unless gate_result[:pass]
          log_result(index_key, direction, gate_result, nil, false)
          return enforce ? gate_result : gate_result.merge(pass: true)
        end

        # Phase 2: Scoring
        score_result = calculate_score(candles, supertrend_result, adx_value, direction, series, config)

        pass = score_result[:score] >= config[:min_score]
        log_result(index_key, direction, gate_result, score_result, pass)

        result = {
          pass: pass,
          score: score_result[:score],
          gates: gate_result[:gates],
          breakdown: score_result[:breakdown],
          reject_reason: pass ? nil : "score_below_threshold (#{score_result[:score]} < #{config[:min_score]})"
        }

        enforce ? result : result.merge(pass: true)
      end

      private

      def load_config(index_key)
        raw = AlgoConfig.fetch[:entry_quality] || {}
        config = deep_symbolize(DEFAULTS.deep_merge(raw))

        apply_session_overrides!(config)

        # Apply index-specific overrides (check Symbol and String keys)
        overrides = config.dig(:index_overrides, index_key.to_sym) ||
                    config.dig(:index_overrides, index_key.to_s) || {}
        overrides = deep_symbolize(overrides)

        if overrides[:min_adx]
          config[:gates] = config[:gates].merge(min_adx: overrides[:min_adx])
        end

        config
      end

      def apply_session_overrides!(config)
        session_overrides = config[:session_overrides]
        return unless session_overrides.is_a?(Hash)

        current_session = detect_current_session
        return unless current_session

        override = session_overrides[current_session.to_sym]
        return unless override.is_a?(Hash)

        override = deep_symbolize(override)

        config[:min_score] = override[:min_score] if override[:min_score]

        if override[:gates].is_a?(Hash)
          config[:gates] = config[:gates].merge(override[:gates])
        end
      end

      def detect_current_session
        time_regimes = AlgoConfig.fetch.dig(:risk, :time_regimes)
        return nil unless time_regimes.is_a?(Hash)

        now = Time.current.in_time_zone('Asia/Kolkata')
        current_hhmm = now.strftime('%H:%M')

        time_regimes.each do |name, cfg|
          next unless cfg.is_a?(Hash)

          start_time = cfg[:start] || cfg['start']
          end_time = cfg[:end] || cfg['end']
          next unless start_time && end_time

          return name.to_sym if current_hhmm >= start_time.to_s && current_hhmm < end_time.to_s
        end

        nil
      end

      def deep_symbolize(hash)
        return hash unless hash.is_a?(Hash)

        hash.each_with_object({}) do |(k, v), result|
          result[k.to_sym] = v.is_a?(Hash) ? deep_symbolize(v) : v
        end
      end

      def check_gates(candles, supertrend_result, adx_value, direction, regime, config)
        gates = {}
        gate_cfg = config[:gates]

        # Gate 1: ADX minimum
        gates[:adx] = adx_value.to_f >= gate_cfg[:min_adx].to_f
        unless gates[:adx]
          return { pass: false, score: 0, gates: gates, breakdown: {}, reject_reason: 'min_adx' }
        end

        # Gate 2: Regime not CHOPPY (configurable via block_choppy_regime)
        if gate_cfg.fetch(:block_choppy_regime, true)
          gates[:regime] = regime.to_s.upcase != 'CHOPPY'
        else
          gates[:regime] = true
        end
        unless gates[:regime]
          return { pass: false, score: 0, gates: gates, breakdown: {}, reject_reason: 'regime' }
        end

        # Gate 3: Candle body ratio
        candle = candles.last
        range = candle.high - candle.low
        body_ratio = range.positive? ? (candle.close - candle.open).abs / range : 0.0
        gates[:body_ratio] = body_ratio >= gate_cfg[:min_body_ratio].to_f
        unless gates[:body_ratio]
          return { pass: false, score: 0, gates: gates, breakdown: {}, reject_reason: 'body_ratio' }
        end

        # Gate 4: Momentum confirmation (configurable via require_momentum_confirm)
        if gate_cfg.fetch(:require_momentum_confirm, true)
          st_value = supertrend_result[:last_value].to_f
          gates[:momentum] = direction == :bullish ? candle.close > st_value : candle.close < st_value
        else
          gates[:momentum] = true
        end
        unless gates[:momentum]
          return { pass: false, score: 0, gates: gates, breakdown: {}, reject_reason: 'momentum' }
        end

        { pass: true, gates: gates }
      end

      def calculate_score(candles, supertrend_result, adx_value, direction, series, config)
        scoring = config[:scoring]
        breakdown = {}

        candle = candles.last
        range = candle.high - candle.low
        body_ratio = range.positive? ? (candle.close - candle.open).abs / range : 0.0

        # Component 1: Candle body strength (0 - candle_body_weight)
        max_body = scoring[:candle_body_weight]
        breakdown[:candle_body] = if body_ratio >= 0.70
                                    max_body
                                  elsif body_ratio >= 0.55
                                    (max_body * 0.72).round
                                  elsif body_ratio >= 0.40
                                    (max_body * 0.40).round
                                  else
                                    0
                                  end

        # Component 2: ADX strength bonus (0 - adx_strength_weight)
        max_adx = scoring[:adx_strength_weight]
        adx = adx_value.to_f
        breakdown[:adx_strength] = if adx >= 35
                                      max_adx
                                   elsif adx >= 25
                                      (max_adx * 0.60).round
                                   elsif adx >= 20
                                      (max_adx * 0.25).round
                                   else
                                      0
                                   end

        # Component 3: Break of structure (0 - bos_weight)
        max_bos = scoring[:bos_weight]
        breakdown[:bos] = score_bos(series, direction, candles, max_bos)

        # Component 4: Range expansion (0 - range_expansion_weight)
        max_range = scoring[:range_expansion_weight]
        atr_value = current_atr(supertrend_result)
        breakdown[:range_expansion] = if atr_value.nil? || atr_value <= 0
                                        0
                                      elsif range >= 1.5 * atr_value
                                        max_range
                                      elsif range >= 1.2 * atr_value
                                        (max_range * 0.60).round
                                      elsif range >= 1.0 * atr_value
                                        (max_range * 0.25).round
                                      else
                                        0
                                      end

        # Component 5: Momentum confirmation strength (0 - momentum_weight)
        max_momentum = scoring[:momentum_weight]
        breakdown[:momentum] = score_momentum(candle, supertrend_result, direction, atr_value, max_momentum)

        total = breakdown.values.sum
        { score: total, breakdown: breakdown }
      end

      def score_bos(series, direction, candles, max_points)
        bos = begin
          Entries::BosExtractor.last_confirmed_bos(series)
        rescue StandardError
          nil
        end

        return max_points if bos && bos[:direction] == direction

        # Fallback: simple structure check (last 3 candles)
        if candles.length >= 3
          last3 = candles.last(3)
          if direction == :bullish
            return (max_points * 0.50).round if last3[0].high < last3[1].high && last3[1].high < last3[2].high
          elsif last3[0].low > last3[1].low && last3[1].low > last3[2].low
            return (max_points * 0.50).round
          end
        end

        0
      end

      def score_momentum(candle, supertrend_result, direction, atr_value, max_points)
        if atr_value.nil? || atr_value <= 0
          return (max_points * 0.20).round
        end

        st_value = supertrend_result[:last_value].to_f
        distance = if direction == :bullish
                     (candle.close - st_value) / atr_value
                   else
                     (st_value - candle.close) / atr_value
                   end

        if distance >= 0.5
          max_points
        elsif distance >= 0.25
          (max_points * 0.67).round
        else
          (max_points * 0.20).round
        end
      end

      def current_atr(supertrend_result)
        atr_array = supertrend_result[:atr]
        return nil unless atr_array.is_a?(Array)

        atr_array.compact.last
      end

      def reject_result(reason)
        { pass: false, score: 0, gates: {}, breakdown: {}, reject_reason: reason }
      end

      def log_result(index_key, direction, gate_result, score_result, pass)
        score = score_result ? score_result[:score] : 0
        breakdown = score_result ? score_result[:breakdown] : {}
        status = pass ? 'PASS' : 'REJECT'
        reason = gate_result[:reject_reason]

        Rails.logger.info(
          "[EntryQualityFilter] #{status} #{index_key} #{direction} | " \
          "score=#{score} gates=#{gate_result[:gates]} breakdown=#{breakdown}" \
          "#{" reason=#{reason}" if reason}"
        )
      end
    end
  end
end
