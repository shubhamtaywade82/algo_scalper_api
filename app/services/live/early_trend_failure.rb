# frozen_string_literal: true

module Live
  module EarlyTrendFailure
    module_function

    def etf_cfg
      @etf_cfg ||= begin
        AlgoConfig.fetch[:risk] && AlgoConfig.fetch[:risk][:etf] || {}
      rescue StandardError
        {}
      end
    end

    # Check if early trend failure conditions are met
    # position_data: Hash or object with trend metrics (trend_score, adx, atr_ratio, etc.)
    # Returns true if ETF exit should be triggered
    def early_trend_failure?(position_data)
      return false unless etf_cfg[:enabled]

      # 1. Trend score collapse
      if position_data.respond_to?(:peak_trend_score) && position_data.respond_to?(:trend_score)
        peak_score = position_data.peak_trend_score.to_f
        current_score = position_data.trend_score.to_f

        if peak_score.positive? && current_score < peak_score
          drop_pct = ((peak_score - current_score) / peak_score) * 100.0
          if drop_pct >= etf_cfg[:trend_score_drop_pct].to_f
            Rails.logger.info("[EarlyTrendFailure] Trend score collapse detected: #{peak_score.round(2)} -> #{current_score.round(2)} (drop: #{drop_pct.round(2)}%)")
            return true
          end
        end
      end

      # 2. ADX collapse (weak trend strength)
      if position_data.respond_to?(:adx) && position_data.adx
        adx_value = position_data.adx.to_f
        threshold = etf_cfg[:adx_collapse_threshold].to_i
        if threshold.positive? && adx_value < threshold
          Rails.logger.info("[EarlyTrendFailure] ADX collapse detected: #{adx_value.round(2)} < #{threshold}")
          return true
        end
      end

      # 3. ATR ratio collapse (volatility compression)
      if position_data.respond_to?(:atr_ratio) && position_data.atr_ratio
        atr_ratio = position_data.atr_ratio.to_f
        threshold = etf_cfg[:atr_ratio_threshold].to_f
        if threshold.positive? && atr_ratio < threshold
          Rails.logger.info("[EarlyTrendFailure] ATR ratio collapse detected: #{atr_ratio.round(3)} < #{threshold}")
          return true
        end
      end

      # 4. VWAP rejection (price moved back below/above VWAP)
      if position_data.respond_to?(:underlying_price) && position_data.respond_to?(:vwap)
        underlying_price = position_data.underlying_price.to_f
        vwap = position_data.vwap.to_f

        if underlying_price.positive? && vwap.positive?
          is_long = position_data.respond_to?(:is_long?) ? position_data.is_long? : true

          if is_long && underlying_price < vwap
            Rails.logger.info("[EarlyTrendFailure] VWAP rejection (long): price #{underlying_price.round(2)} < VWAP #{vwap.round(2)}")
            return true
          elsif !is_long && underlying_price > vwap
            Rails.logger.info("[EarlyTrendFailure] VWAP rejection (short): price #{underlying_price.round(2)} > VWAP #{vwap.round(2)}")
            return true
          end
        end
      end

      false
    rescue StandardError => e
      Rails.logger.error("[EarlyTrendFailure] Error checking ETF: #{e.class} - #{e.message}")
      false
    end

    # Check if ETF checks are applicable (before trailing activation)
    def applicable?(pnl_pct, activation_profit_pct: nil)
      activation = activation_profit_pct || etf_cfg[:activation_profit_pct].to_f
      return false if activation.zero?

      pnl_pct.to_f < activation
    end
  end
end
