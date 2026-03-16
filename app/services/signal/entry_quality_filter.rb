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
        raw = AlgoConfig.fetch.dig(:entry_quality) || {}
        config = deep_symbolize(DEFAULTS.deep_merge(raw))

        # Apply index-specific overrides (check Symbol and String keys)
        overrides = config.dig(:index_overrides, index_key.to_sym) ||
                    config.dig(:index_overrides, index_key.to_s) || {}
        overrides = deep_symbolize(overrides)

        if overrides[:min_adx]
          config[:gates] = config[:gates].merge(min_adx: overrides[:min_adx])
        end

        config
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
        body_ratio = range > 0 ? (candle.close - candle.open).abs / range : 0.0
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

      def calculate_score(_candles, _supertrend_result, _adx_value, _direction, _series, config)
        # Placeholder — returns minimum passing score. Replaced in Task 5.
        { score: config[:min_score], breakdown: {} }
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
          "#{reason ? " reason=#{reason}" : ''}"
        )
      end
    end
  end
end
