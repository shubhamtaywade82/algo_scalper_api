# frozen_string_literal: true

module OptionsBuying
  # TradeScoringEngine compiles a weighted composite score (0–100) from various Engines
  # (Context, Regime, Structure, Momentum, Liquidity, Greeks) to authorize entry execution.
  class TradeScoringEngine
    DEFAULT_THRESHOLD = 80.0
    DEFAULT_WEIGHTS = {
      market_context: 0.30,
      momentum: 0.20,
      liquidity: 0.20,
      greeks_flow: 0.30
    }.freeze

    def self.score!(index_key:, direction:, option_security_id:, strategy_name:, spot_ltp:)
      new(
        index_key: index_key,
        direction: direction,
        option_security_id: option_security_id,
        strategy_name: strategy_name,
        spot_ltp: spot_ltp
      ).score!
    end

    def initialize(index_key:, direction:, option_security_id:, strategy_name:, spot_ltp:)
      @index_key = index_key.to_s.upcase
      @direction = direction.to_sym
      @option_security_id = option_security_id.to_s
      @strategy_name = strategy_name.to_s
      @spot_ltp = spot_ltp.to_f
    end

    def score!
      # 1. Market Context Score (up to 100 points, weighted at 30%)
      context_score = compute_context_score

      # 2. Momentum Score (up to 100 points, weighted at 20%)
      momentum_score = compute_momentum_score

      # 3. Liquidity Score (up to 100 points, weighted at 20%)
      liquidity_score = compute_liquidity_score

      # 4. Greeks & Flow Score (up to 100 points, weighted at 30%)
      greeks_score = compute_greeks_score

      # Weighted aggregate score
      w = weights
      total_score = (
        (context_score * w[:market_context]) +
        (momentum_score * w[:momentum]) +
        (liquidity_score * w[:liquidity]) +
        (greeks_score * w[:greeks_flow])
      ).round(2)

      passed = total_score >= threshold

      breakdown = {
        context_score: context_score,
        momentum_score: momentum_score,
        liquidity_score: liquidity_score,
        greeks_score: greeks_score,
        total_score: total_score,
        threshold: threshold,
        passed: passed
      }

      persist_score_event!(breakdown)

      Rails.logger.info(
        "[TradeScoringEngine] #{@index_key} strategy=#{@strategy_name} score=#{total_score} passed=#{passed} breakdown=#{breakdown.inspect}"
      )

      { passed: passed, score: total_score, breakdown: breakdown }
    rescue StandardError => e
      Rails.logger.error("[TradeScoringEngine] scoring failed: #{e.class} - #{e.message}\n#{e.backtrace&.first(10)&.join("\n")}")
      # Fallback to failure
      { passed: false, score: 0.0, error: e.message }
    end

    private

    def threshold
      (Mode.config.dig(:scoring, :threshold) || DEFAULT_THRESHOLD).to_f
    end

    def weights
      config_weights = Mode.config.dig(:scoring, :weights) || {}
      DEFAULT_WEIGHTS.merge(config_weights.symbolize_keys)
    end

    def compute_context_score
      instrument = index_instrument
      return 50.0 unless instrument

      series = instrument.candle_series(interval: '5')
      return 50.0 if series.blank? || series.candles.empty?

      composer = MarketContext::RegimeComposer.new(series: series, index_key: @index_key)
      composer.call.conviction_score.to_f
    rescue StandardError => e
      Rails.logger.warn("[TradeScoringEngine] Context score calculation failed: #{e.message}")
      50.0
    end

    def compute_momentum_score
      instrument = index_instrument
      return 50.0 unless instrument

      adx_val = instrument.adx(14, interval: '5').to_f
      rsi_val = instrument.rsi(14, interval: '5').to_f

      adx_points = case adx_val
                   when 40.. then 80.0
                   when 25...40 then 60.0
                   when 18...25 then 40.0
                   else 20.0
                   end

      rsi_points = 50.0
      if @direction == :bullish
        rsi_points = rsi_val >= 60.0 ? 80.0 : (rsi_val >= 50.0 ? 60.0 : 30.0)
      elsif @direction == :bearish
        rsi_points = rsi_val <= 40.0 ? 80.0 : (rsi_val <= 50.0 ? 60.0 : 30.0)
      end

      (adx_points * 0.5) + (rsi_points * 0.5)
    rescue StandardError => e
      Rails.logger.warn("[TradeScoringEngine] Momentum score calculation failed: #{e.message}")
      50.0
    end

    def compute_liquidity_score
      # Spread evaluation similar to BidAskSpreadGuard
      snap = StateStore.cache_snapshot(@option_security_id)
      spread_pct = 1.0 # default massive spread if unavailable

      if snap && snap[:bid].to_f.positive? && snap[:ask].to_f.positive?
        bid = snap[:bid].to_f
        ask = snap[:ask].to_f
        spread_pct = (ask - bid) / bid
      end

      spread_points = if spread_pct <= 0.005
                        100.0
                      elsif spread_pct <= 0.015
                        80.0
                      elsif spread_pct <= 0.03
                        50.0
                      else
                        10.0
                      end

      # Add volume rate baseline factor
      vol_rate = StateStore.volume_rate_baseline(@option_security_id).to_f
      vol_points = if vol_rate > 500.0
                     100.0
                   elsif vol_rate > 100.0
                     70.0
                   elsif vol_rate > 10.0
                     40.0
                   else
                     20.0
                   end

      (spread_points * 0.7) + (vol_points * 0.3)
    rescue StandardError => e
      Rails.logger.warn("[TradeScoringEngine] Liquidity score calculation failed: #{e.message}")
      50.0
    end

    def compute_greeks_score
      gamma_points = 50.0
      begin
        # If GammaWall checks out OK, award 100, else award 0
        is_safe = GammaWallDetector.new(@index_key).safe_to_enter?(@spot_ltp, @direction)
        gamma_points = is_safe ? 100.0 : 0.0
      rescue StandardError => e
        Rails.logger.warn("[TradeScoringEngine] Gamma wall check error: #{e.message}")
      end

      vol_vel_points = 50.0
      begin
        ticks = StateStore.stream_window(@option_security_id)
        if ticks.size >= 5
          volume_delta = TickMetrics.volume_delta(ticks.last(5))
          volume_baseline = StateStore.volume_threshold_baseline(@option_security_id).to_f
          if volume_baseline.positive?
            ratio = volume_delta.to_f / volume_baseline
            vol_vel_points = if ratio >= 1.5
                               100.0
                             elsif ratio >= 1.0
                               70.0
                             else
                               40.0
                             end
          end
        end
      rescue StandardError => e
        Rails.logger.warn("[TradeScoringEngine] Option volume velocity check failed: #{e.message}")
      end

      (gamma_points * 0.6) + (vol_vel_points * 0.4)
    end

    def index_instrument
      index_cfg = IndexConfigLoader.load_indices.find { |c| c[:key].to_s.upcase == @index_key }
      return nil unless index_cfg

      IndexInstrumentCache.instance.get_or_fetch(index_cfg)
    end

    def persist_score_event!(breakdown)
      return unless defined?(OptionsBuyingSignalEvent)

      OptionsBuyingSignalEvent.create!(
        event_type: 'scoring_decision',
        index_key: @index_key,
        security_id: @option_security_id,
        occurred_at: Time.current,
        metadata: breakdown.merge(strategy: @strategy_name, direction: @direction)
      )
    rescue StandardError => e
      Rails.logger.warn("[TradeScoringEngine] Failed to persist score event: #{e.message}")
    end
  end
end
