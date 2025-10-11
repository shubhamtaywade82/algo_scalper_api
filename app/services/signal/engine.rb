# frozen_string_literal: true

module Signal
  class Engine
    class << self
      def run_for(index_cfg)
        Rails.logger.info("[Signal] Starting analysis for #{index_cfg[:key]} (#{index_cfg[:segment]})")

        timeframe = AlgoConfig.fetch.dig(:signals, :timeframe)
        Rails.logger.debug("[Signal] Using timeframe: #{timeframe}")

        # Calculate trading dates using Market::Calendar
        to_date = Market::Calendar.today_or_last_trading_day.strftime("%Y-%m-%d")
        from_date = Market::Calendar.trading_days_ago(1).strftime("%Y-%m-%d")
        Rails.logger.debug("[Signal] Fetching data from #{from_date} to #{to_date}")

        candles = DhanHQ::Models::HistoricalData.intraday(
          exchange_segment: index_cfg[:segment],
          security_id: index_cfg[:sid],
          instrument: "INDEX",
          interval: timeframe.gsub("m", ""), # Convert "5m" to "5"
          from_date: from_date,
          to_date: to_date
        )

        if candles.blank?
          Rails.logger.warn("[Signal] No candle data available for #{index_cfg[:key]}")
          return
        end

        Rails.logger.info("[Signal] Fetched #{candles.size} candles for #{index_cfg[:key]}")

        supertrend_cfg = AlgoConfig.fetch.dig(:signals, :supertrend)
        unless supertrend_cfg
          Rails.logger.error("[Signal] Supertrend configuration missing for #{index_cfg[:key]}")
          return
        end

        Rails.logger.debug("[Signal] Supertrend config: #{supertrend_cfg}")

        # Convert candles to CandleSeries format expected by Supertrend
        series = CandleSeries.new(symbol: index_cfg[:key], interval: timeframe.gsub("m", ""))
        series.load_from_raw(candles)

        st = Indicators::Supertrend.new(series: series, **supertrend_cfg).call
        Rails.logger.info("[Signal] Supertrend result for #{index_cfg[:key]}: trend=#{st[:trend]}, last_value=#{st[:last_value]}")

        adx_calculator = Indicators::Calculator.new(series)
        adx_value = adx_calculator.adx
        adx = { value: adx_value }
        Rails.logger.info("[Signal] ADX value for #{index_cfg[:key]}: #{adx_value}")

        direction = decide_direction(st, adx)
        Rails.logger.info("[Signal] Direction decision for #{index_cfg[:key]}: #{direction}")

        if direction == :avoid
          Rails.logger.info("[Signal] Avoiding trade for #{index_cfg[:key]} - conditions not met")
          return
        end

        Rails.logger.info("[Signal] Proceeding with #{direction} signal for #{index_cfg[:key]}")

        picks = Options::ChainAnalyzer.pick_strikes(index_cfg: index_cfg, direction: direction)

        if picks.blank?
          Rails.logger.warn("[Signal] No suitable option strikes found for #{index_cfg[:key]} #{direction}")
          return
        end

        Rails.logger.info("[Signal] Found #{picks.size} option picks for #{index_cfg[:key]}: #{picks.map { |p| "#{p[:symbol]}@#{p[:strike]}" }.join(', ')}")

        picks.each_with_index do |pick, index|
          Rails.logger.info("[Signal] Attempting entry #{index + 1}/#{picks.size} for #{index_cfg[:key]}: #{pick[:symbol]}")
          result = Entries::EntryGuard.try_enter(index_cfg: index_cfg, pick: pick, direction: direction)

          if result
            Rails.logger.info("[Signal] Entry successful for #{index_cfg[:key]}: #{pick[:symbol]}")
          else
            Rails.logger.warn("[Signal] Entry failed for #{index_cfg[:key]}: #{pick[:symbol]}")
          end
        end

        Rails.logger.info("[Signal] Completed analysis for #{index_cfg[:key]}")
      rescue StandardError => e
        Rails.logger.error("[Signal] #{index_cfg[:key]} #{e.class} #{e.message}")
        Rails.logger.error("[Signal] Backtrace: #{e.backtrace.first(5).join(', ')}")
      end

      def decide_direction(supertrend_result, adx)
        min_strength = AlgoConfig.fetch.dig(:signals, :adx, :min_strength).to_f
        adx_value = adx[:value].to_f

        Rails.logger.debug("[Signal] ADX check: value=#{adx_value}, min_required=#{min_strength}")

        if adx_value < min_strength
          Rails.logger.info("[Signal] ADX too weak: #{adx_value} < #{min_strength}")
          return :avoid
        end

        if supertrend_result.blank? || supertrend_result[:trend].nil?
          Rails.logger.warn("[Signal] Supertrend result invalid: #{supertrend_result}")
          return :avoid
        end

        trend = supertrend_result[:trend]
        Rails.logger.debug("[Signal] Supertrend trend: #{trend}")

        # Use the trend from Supertrend calculation
        case trend
        when :bullish
          Rails.logger.info("[Signal] Bullish signal confirmed: ADX=#{adx_value}, Supertrend=#{trend}")
          :bullish
        when :bearish
          Rails.logger.info("[Signal] Bearish signal confirmed: ADX=#{adx_value}, Supertrend=#{trend}")
          :bearish
        else
          Rails.logger.info("[Signal] Neutral/unknown trend: #{trend}")
          :avoid
        end
      end
    end
  end
end
