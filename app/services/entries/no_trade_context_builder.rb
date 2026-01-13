# frozen_string_literal: true

require 'technical_analysis'

module Entries
  # Builds context for No-Trade Engine validation
  class NoTradeContextBuilder
    class << self
      # Build context from market data
      # @param index [String] Index key (e.g., "NIFTY", "BANKNIFTY")
      # @param bars_1m [Array<Candle>] 1-minute candles
      # @param bars_5m [Array<Candle>] 5-minute candles
      # @param option_chain [Hash, OptionChainWrapper] Option chain data
      # @param time [String, Time] Current time (format: "HH:MM" or Time object)
      # @return [OpenStruct] Context object with all validation fields
      def build(index:, bars_1m:, bars_5m:, option_chain:, time:)
        index_key = index.to_s.upcase
        current_time = normalize_time(time)

        # Get index-specific thresholds
        thresholds = NoTradeThresholds.for_index(index_key)

        # Wrap option chain if needed
        chain_wrapper = if option_chain.is_a?(OptionChainWrapper)
                          option_chain
                        else
                          OptionChainWrapper.new(chain_data: option_chain, index_key: index_key)
                        end

        # Calculate ADX and DI values from 5m bars
        adx_data = calculate_adx_data(bars_5m)

        # Calculate range for OI trap check
        range_10m_pct = RangeUtils.range_pct(bars_1m.last(10))

        OpenStruct.new(
          # Index key for threshold lookups
          index_key: index_key,
          thresholds: thresholds,

          # Trend indicators
          adx_5m: adx_data[:adx] || 0,
          plus_di_5m: adx_data[:plus_di] || 0,
          minus_di_5m: adx_data[:minus_di] || 0,

          # Structure indicators
          bos_present: StructureDetector.bos?(bars_1m),
          in_opposite_ob: StructureDetector.inside_opposite_ob?(bars_1m),
          inside_fvg: StructureDetector.inside_fvg?(bars_1m),

          # VWAP indicators (with index-specific thresholds)
          near_vwap: VWAPUtils.near_vwap?(bars_1m, threshold_pct: thresholds[:vwap_chop_pct]),
          vwap_chop: VWAPUtils.vwap_chop?(
            bars_1m,
            threshold_pct: thresholds[:vwap_chop_pct],
            min_candles: thresholds[:vwap_chop_candles]
          ),
          trapped_between_vwap: VWAPUtils.trapped_between_vwap_avwap?(bars_1m),

          # Volatility indicators (with index-specific thresholds)
          range_10m_pct: range_10m_pct,
          atr_downtrend: ATRUtils.atr_downtrend?(
            bars_1m,
            min_downtrend_bars: thresholds[:atr_downtrend_bars]
          ),

          # Option chain indicators (with index-specific thresholds)
          ce_oi_up: chain_wrapper.ce_oi_rising?,
          pe_oi_up: chain_wrapper.pe_oi_rising?,
          iv: chain_wrapper.atm_iv || 0,
          iv_falling: chain_wrapper.iv_falling?,
          min_iv_threshold: thresholds[:iv_hard_reject],
          oi_trap: chain_wrapper.ce_oi_rising? && chain_wrapper.pe_oi_rising? && range_10m_pct < thresholds[:oi_trap_range_pct],
          spread_wide: chain_wrapper.spread_wide?(hard_reject_threshold: thresholds[:spread_hard_reject]),

          # Candle behavior (with index-specific thresholds)
          avg_wick_ratio: CandleUtils.avg_wick_ratio(bars_1m.last(5)),

          # Timing
          time: current_time,

          # Helper method
          time_between: ->(start_t, end_t) { time_between?(current_time, start_t, end_t) }
        )
      end

      private

      def normalize_time(time)
        case time
        when Time, DateTime, ActiveSupport::TimeWithZone
          time.strftime('%H:%M')
        when String
          time
        else
          Time.current.strftime('%H:%M')
        end
      end

      def time_between?(current_time_str, start_str, end_str)
        current = time_to_minutes(current_time_str)
        start_min = time_to_minutes(start_str)
        end_min = time_to_minutes(end_str)

        return false unless current && start_min && end_min

        if start_min <= end_min
          current.between?(start_min, end_min)
        else
          # Handles overnight ranges (e.g., 23:00 to 02:00)
          current >= start_min || current <= end_min
        end
      end

      def time_to_minutes(time_str)
        return nil unless time_str.is_a?(String)

        parts = time_str.split(':')
        return nil unless parts.size == 2

        hour = parts[0].to_i
        minute = parts[1].to_i

        (hour * 60) + minute
      end

      def calculate_adx_data(bars)
        return { adx: 0, plus_di: 0, minus_di: 0 } if bars.size < 15

        # Use CandleSeries to get ADX and DI values
        series = build_candle_series(bars)
        return { adx: 0, plus_di: 0, minus_di: 0 } unless series

        # Get full ADX result (includes DI+ and DI-)
        adx_result = extract_adx_with_di(series)
        {
          adx: adx_result[:adx] || 0,
          plus_di: adx_result[:plus_di] || 0,
          minus_di: adx_result[:minus_di] || 0
        }
      end

      def build_candle_series(bars)
        return nil if bars.empty? || !bars.first.is_a?(Candle)

        series = CandleSeries.new(symbol: 'temp', interval: '5')
        bars.each { |c| series.add_candle(c) }
        series
      end

      def extract_adx_with_di(series)
        return { adx: 0, plus_di: 0, minus_di: 0 } if series.candles.size < 15

        # Use TechnicalAnalysis gem directly to get full ADX result
        hlc = series.hlc
        result = TechnicalAnalysis::Adx.calculate(hlc, period: 14)
        return { adx: 0, plus_di: 0, minus_di: 0 } if result.empty?

        # Get last result (most recent)
        last_result = result.last

        # Handle different property naming (adx/adx, plus_di/plusDi, minus_di/minusDi)
        adx_value = if last_result.respond_to?(:adx)
                      last_result.adx
                    else
                      (last_result.respond_to?(:adx_value) ? last_result.adx_value : 0)
                    end
        plus_di_value = if last_result.respond_to?(:plus_di)
                          last_result.plus_di
                        elsif last_result.respond_to?(:plusDi)
                          last_result.plusDi
                        else
                          0
                        end
        minus_di_value = if last_result.respond_to?(:minus_di)
                           last_result.minus_di
                         elsif last_result.respond_to?(:minusDi)
                           last_result.minusDi
                         else
                           0
                         end

        {
          adx: adx_value || 0,
          plus_di: plus_di_value || 0,
          minus_di: minus_di_value || 0
        }
      rescue StandardError => e
        Rails.logger.warn("[NoTradeContextBuilder] ADX calculation failed: #{e.message}")
        # Fallback to simple ADX value (DI values will be 0)
        adx_value = series.adx(14) || 0
        { adx: adx_value, plus_di: 0, minus_di: 0 }
      end
    end
  end
end
