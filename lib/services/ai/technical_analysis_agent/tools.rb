# frozen_string_literal: true

module Services
  module Ai
    class TechnicalAnalysisAgent
      # All tool implementations
      module Tools
        # Ensure DhanhqErrorHandler is loaded before calling instrument methods
        # This is needed because instrument.candles() internally calls intraday_ohlc() which uses the error handler
        def ensure_dhanhq_error_handler_loaded
          return unless defined?(Rails)

          # Check if already loaded and methods are available
          return if defined?(DhanhqErrorHandler) && DhanhqErrorHandler.respond_to?(:handle_dhanhq_error)

          # Try to load the concern file directly
          file_path = Rails.root.join('app/services/concerns/dhanhq_error_handler.rb')
          require file_path.to_s if File.exist?(file_path)

          # Verify the method is available after loading
          return if defined?(DhanhqErrorHandler) && DhanhqErrorHandler.respond_to?(:handle_dhanhq_error)

          Rails.logger.warn('[TechnicalAnalysisAgent] DhanhqErrorHandler.handle_dhanhq_error not available - instrument methods may fail')
        end

        def tool_get_comprehensive_analysis(args)
          underlying_symbol = args['underlying_symbol'] || args['symbol_name'] # Support both for backward compatibility
          return { error: 'Missing underlying_symbol' } if underlying_symbol.blank?

          # Auto-detect exchange and segment
          exchange = detect_exchange_for_index(underlying_symbol, args['exchange'])
          segment = detect_segment_for_symbol(underlying_symbol, args['segment'])
          interval = args['interval'] || '5'
          max_candles = [args['max_candles']&.to_i || 200, 200].min # Cap at 200

          # Find instrument using scopes
          instrument = case exchange
                       when 'NSE'
                         case segment
                         when 'index'
                           Instrument.nse.segment_index.find_by(underlying_symbol: underlying_symbol.to_s)
                         when 'equity'
                           Instrument.nse.segment_equity.find_by(underlying_symbol: underlying_symbol.to_s)
                         when 'derivatives'
                           Instrument.nse.segment_derivatives.find_by(underlying_symbol: underlying_symbol.to_s)
                         else
                           Instrument.nse.find_by(underlying_symbol: underlying_symbol.to_s)
                         end
                       when 'BSE'
                         case segment
                         when 'index'
                           Instrument.bse.segment_index.find_by(underlying_symbol: underlying_symbol.to_s)
                         when 'equity'
                           Instrument.bse.segment_equity.find_by(underlying_symbol: underlying_symbol.to_s)
                         when 'derivatives'
                           Instrument.bse.segment_derivatives.find_by(underlying_symbol: underlying_symbol.to_s)
                         else
                           Instrument.bse.find_by(underlying_symbol: underlying_symbol.to_s)
                         end
                       else
                         return { error: "Invalid exchange: #{exchange}. Must be 'NSE' or 'BSE'" }
                       end

          return { error: "Instrument not found: #{underlying_symbol} (#{exchange}, #{segment})" } unless instrument

          # Ensure DhanhqErrorHandler is loaded before calling instrument methods
          ensure_dhanhq_error_handler_loaded

          # Fetch LTP
          ltp = instrument.ltp

          # Normalize interval format (remove 'm' suffix if present)
          normalized_interval = interval.to_s.gsub(/m$/i, '')

          # Fetch historical data (candles)
          # Note: instrument.candles() automatically handles date ranges and includes today's data
          begin
            series = instrument.candles(interval: normalized_interval)
            return { error: "No candle data available for #{underlying_symbol}" } unless series&.candles&.any?

            # Limit to max_candles (take the most recent candles)
            candles = series.candles.last(max_candles)
            candle_count = candles.length
            latest_candle = candles.last
          rescue StandardError => e
            Rails.logger.error("[TechnicalAnalysisAgent] Error fetching candles: #{e.class} - #{e.message}")
            return { error: "Failed to fetch candle data for #{underlying_symbol}: #{e.message}" }
          end

          # Calculate ALL available indicators with interpretations
          indicators = {}
          indicator_interpretations = {}

          begin
            # RSI (14 period)
            rsi_value = series.rsi(14)
            if rsi_value.present?
              indicators[:rsi] = rsi_value
              # Add interpretation
              rsi_interpretation = if rsi_value < 30
                                     'oversold'
                                   elsif rsi_value > 70
                                     'overbought'
                                   elsif rsi_value < 50
                                     'neutral_bearish'
                                   elsif rsi_value > 50
                                     'neutral_bullish'
                                   else
                                     'neutral'
                                   end
              indicator_interpretations[:rsi] = rsi_interpretation
            end

            # MACD (12, 26, 9)
            macd_result = series.macd(12, 26, 9)
            if macd_result
              macd_line = macd_result[0]
              signal_line = macd_result[1]
              histogram = macd_result[2]
              indicators[:macd] = {
                macd: macd_line,
                signal: signal_line,
                histogram: histogram
              }
              # Add interpretation
              macd_interpretation = if macd_line > signal_line && histogram.positive?
                                      'bullish'
                                    elsif macd_line < signal_line && histogram.negative?
                                      'bearish'
                                    elsif macd_line > signal_line && histogram.negative?
                                      'bullish_weakening'
                                    elsif macd_line < signal_line && histogram.positive?
                                      'bearish_weakening'
                                    else
                                      'neutral'
                                    end
              indicator_interpretations[:macd] = macd_interpretation
            end

            # ADX (14 period)
            adx_value = series.adx(14)
            if adx_value.present?
              indicators[:adx] = adx_value
              # Add interpretation
              adx_interpretation = if adx_value < 20
                                     'weak_trend'
                                   elsif adx_value < 40
                                     'moderate_trend'
                                   elsif adx_value < 50
                                     'strong_trend'
                                   else
                                     'very_strong_trend'
                                   end
              indicator_interpretations[:adx] = adx_interpretation
            end

            # Supertrend (uses default period: 7, multiplier: 3.0 from CandleSeries)
            supertrend_value = series.supertrend_signal
            if supertrend_value.present?
              indicators[:supertrend] = supertrend_value
              # Add interpretation
              supertrend_interpretation = case supertrend_value.to_s
                                          when 'long_entry', :long_entry
                                            'bullish'
                                          when 'short_entry', :short_entry
                                            'bearish'
                                          else
                                            'neutral'
                                          end
              indicator_interpretations[:supertrend] = supertrend_interpretation
            end

            # ATR (14 period)
            atr_value = series.atr(14)
            if atr_value.present?
              indicators[:atr] = atr_value
              # ATR interpretation requires context (current price), so we'll just note it's available
              indicator_interpretations[:atr] = 'volatility_measure'
            end

            # Bollinger Bands (20 period, 2.0 std dev)
            bb_result = series.bollinger_bands(period: 20, std_dev: 2.0)
            if bb_result && latest_candle
              indicators[:bollinger_bands] = {
                upper: bb_result[:upper],
                middle: bb_result[:middle],
                lower: bb_result[:lower]
              }
              # Add interpretation based on current price position
              current_price = latest_candle.close
              bb_position = if current_price >= bb_result[:upper]
                              'near_upper_band'
                            elsif current_price <= bb_result[:lower]
                              'near_lower_band'
                            elsif current_price > bb_result[:middle]
                              'above_middle'
                            elsif current_price < bb_result[:middle]
                              'below_middle'
                            else
                              'at_middle'
                            end
              indicator_interpretations[:bollinger_bands] = bb_position
            end
          rescue StandardError => e
            Rails.logger.warn("[TechnicalAnalysisAgent] Error calculating some indicators: #{e.class} - #{e.message}")
            # Continue even if some indicators fail
          end

          # Get latest OHLC (latest_candle already defined above)
          ohlc = if latest_candle
                   {
                     open: latest_candle.open,
                     high: latest_candle.high,
                     low: latest_candle.low,
                     close: latest_candle.close,
                     volume: latest_candle.volume
                   }
                 else
                   instrument.ohlc
                 end

          {
            underlying_symbol: underlying_symbol,
            exchange: exchange,
            segment: segment,
            security_id: instrument.security_id,
            ltp: ltp.to_f,
            ohlc: ohlc,
            interval: interval,
            candle_count: candle_count,
            indicators: indicators,
            indicator_interpretations: indicator_interpretations,
            timestamp: Time.current
          }
        end

        def tool_get_index_ltp(args)
          index_key = args['index_key']&.to_s&.upcase

          # Cache index configs to avoid repeated lookups
          @index_config_cache ||= IndexConfigLoader.load_indices

          index_cfg = @index_config_cache.find { |idx| idx[:key].to_s.upcase == index_key }
          return { error: "Unknown index: #{index_key}" } unless index_cfg

          security_id = index_cfg[:security_id] || index_cfg[:sid]
          segment = index_cfg[:segment]
          return { error: "Missing security_id or segment for #{index_key}" } unless security_id && segment

          instrument = Instrument.find_by_sid_and_segment(
            security_id: security_id,
            segment_code: segment,
            underlying_symbol: index_key
          )
          return { error: "Instrument not found for #{index_key} (SID: #{security_id}, Segment: #{segment})" } unless instrument

          ltp = instrument.ltp

          {
            index: index_key,
            ltp: ltp,
            timestamp: Time.current
          }
        end

        def tool_get_instrument_ltp(args)
          underlying_symbol = args['underlying_symbol'] || args['symbol_name'] # Support both for backward compatibility
          return { error: 'Missing underlying_symbol' } if underlying_symbol.blank?

          # Auto-detect exchange and segment
          exchange = detect_exchange_for_index(underlying_symbol, args['exchange'])
          segment = detect_segment_for_symbol(underlying_symbol, args['segment'])

          # Find instrument using scopes
          instrument = case exchange
                       when 'NSE'
                         case segment
                         when 'index'
                           Instrument.nse.segment_index.find_by(underlying_symbol: underlying_symbol.to_s)
                         when 'equity'
                           Instrument.nse.segment_equity.find_by(underlying_symbol: underlying_symbol.to_s)
                         when 'derivatives'
                           Instrument.nse.segment_derivatives.find_by(underlying_symbol: underlying_symbol.to_s)
                         else
                           Instrument.nse.find_by(underlying_symbol: underlying_symbol.to_s)
                         end
                       when 'BSE'
                         case segment
                         when 'index'
                           Instrument.bse.segment_index.find_by(underlying_symbol: underlying_symbol.to_s)
                         when 'equity'
                           Instrument.bse.segment_equity.find_by(underlying_symbol: underlying_symbol.to_s)
                         when 'derivatives'
                           Instrument.bse.segment_derivatives.find_by(underlying_symbol: underlying_symbol.to_s)
                         else
                           Instrument.bse.find_by(underlying_symbol: underlying_symbol.to_s)
                         end
                       else
                         return { error: "Invalid exchange: #{exchange}. Must be 'NSE' or 'BSE'" }
                       end

          return { error: "Instrument not found: #{underlying_symbol} (#{exchange}, #{segment})" } unless instrument

          ltp = instrument.ltp
          return { error: 'LTP not available' } unless ltp

          {
            underlying_symbol: underlying_symbol,
            exchange: exchange,
            segment: segment,
            security_id: instrument.security_id,
            ltp: ltp.to_f,
            timestamp: Time.current
          }
        end

        def tool_get_ohlc(args)
          underlying_symbol = args['underlying_symbol'] || args['symbol_name'] # Support both for backward compatibility
          return { error: 'Missing underlying_symbol' } if underlying_symbol.blank?

          # Auto-detect exchange and segment
          exchange = detect_exchange_for_index(underlying_symbol, args['exchange'])
          segment = detect_segment_for_symbol(underlying_symbol, args['segment'])

          # Find instrument using scopes
          instrument = case exchange
                       when 'NSE'
                         case segment
                         when 'index'
                           Instrument.nse.segment_index.find_by(underlying_symbol: underlying_symbol.to_s)
                         when 'equity'
                           Instrument.nse.segment_equity.find_by(underlying_symbol: underlying_symbol.to_s)
                         when 'derivatives'
                           Instrument.nse.segment_derivatives.find_by(underlying_symbol: underlying_symbol.to_s)
                         else
                           Instrument.nse.find_by(underlying_symbol: underlying_symbol.to_s)
                         end
                       when 'BSE'
                         case segment
                         when 'index'
                           Instrument.bse.segment_index.find_by(underlying_symbol: underlying_symbol.to_s)
                         when 'equity'
                           Instrument.bse.segment_equity.find_by(underlying_symbol: underlying_symbol.to_s)
                         when 'derivatives'
                           Instrument.bse.segment_derivatives.find_by(underlying_symbol: underlying_symbol.to_s)
                         else
                           Instrument.bse.find_by(underlying_symbol: underlying_symbol.to_s)
                         end
                       else
                         return { error: "Invalid exchange: #{exchange}. Must be 'NSE' or 'BSE'" }
                       end

          return { error: "Instrument not found: #{underlying_symbol} (#{exchange}, #{segment})" } unless instrument

          ohlc_data = instrument.ohlc
          return { error: 'OHLC data not available' } unless ohlc_data

          {
            underlying_symbol: underlying_symbol,
            exchange: exchange,
            segment: segment,
            security_id: instrument.security_id,
            ohlc: ohlc_data,
            timestamp: Time.current
          }
        end

        def tool_calculate_indicator(args)
          index_key = args['index_key']&.to_s&.upcase
          indicator_name = args['indicator']&.to_s&.downcase
          period = args['period']&.to_i
          interval = args['interval'] || '1'

          index_cfg = IndexConfigLoader.load_indices.find { |idx| idx[:key].to_s.upcase == index_key }
          return { error: "Unknown index: #{index_key}" } unless index_cfg

          security_id = index_cfg[:security_id] || index_cfg[:sid]
          segment = index_cfg[:segment]
          return { error: "Missing security_id or segment for #{index_key}" } unless security_id && segment

          # Get instrument and candle series using both security_id and segment
          instrument = Instrument.find_by_sid_and_segment(
            security_id: security_id,
            segment_code: segment,
            underlying_symbol: index_key
          )
          return { error: "Instrument not found for #{index_key} (SID: #{security_id}, Segment: #{segment})" } unless instrument

          # Ensure DhanhqErrorHandler is loaded before calling instrument methods
          ensure_dhanhq_error_handler_loaded

          # Normalize interval format (remove 'm' suffix if present, e.g., "1m" -> "1")
          normalized_interval = interval.to_s.gsub(/m$/i, '')

          begin
            series = instrument.candles(interval: normalized_interval)
            return { error: "No candle data available for #{index_key}" } unless series&.candles&.any?
          rescue StandardError => e
            Rails.logger.error("[TechnicalAnalysisAgent] Error fetching candles: #{e.class} - #{e.message}")
            return { error: "Failed to fetch candle data for #{index_key}: #{e.message}" }
          end

          # Calculate indicator using CandleSeries methods
          result = case indicator_name
                   when 'rsi'
                     rsi_period = period || 14
                     series.rsi(rsi_period)
                   when 'macd'
                     fast = period || 12
                     slow = period ? period * 2 : 26
                     signal = period ? (period * 0.75).to_i : 9
                     macd_result = series.macd(fast, slow, signal)
                     macd_result ? { macd: macd_result[0], signal: macd_result[1], histogram: macd_result[2] } : nil
                   when 'adx'
                     adx_period = period || 14
                     series.adx(adx_period)
                   when 'supertrend'
                     st_period = period || 7
                     multiplier = args['multiplier']&.to_f || 3.0
                     series.supertrend_signal(period: st_period, multiplier: multiplier)
                   when 'atr'
                     atr_period = period || 14
                     series.atr(atr_period)
                   when 'bollinger', 'bollingerbands', 'bb'
                     bb_period = period || 20
                     std_dev = args['std_dev']&.to_f || 2.0
                     bb_result = series.bollinger_bands(period: bb_period, std_dev: std_dev)
                     if bb_result
                       { upper: bb_result[:upper], middle: bb_result[:middle],
                         lower: bb_result[:lower] }
                     end
                   else
                     return { error: "Unknown indicator: #{indicator_name}. Available: RSI, MACD, ADX, Supertrend, ATR, BollingerBands" }
                   end

          {
            index: index_key,
            indicator: indicator_name,
            period: period,
            interval: interval,
            value: result,
            timestamp: Time.current
          }
        end

        def tool_get_historical_data(args)
          underlying_symbol = args['underlying_symbol'] || args['symbol_name'] # Support both for backward compatibility
          return { error: 'Missing underlying_symbol' } if underlying_symbol.blank?

          # Auto-detect exchange and segment
          exchange = detect_exchange_for_index(underlying_symbol, args['exchange'])
          segment = detect_segment_for_symbol(underlying_symbol, args['segment'])
          interval = args['interval'] || '5'
          days = args['days']&.to_i || 3

          # Parse and validate dates
          to_date = if args['to_date'].present?
                      Date.parse(args['to_date'].to_s)
                    else
                      Time.zone.today
                    end

          from_date = if args['from_date'].present?
                        Date.parse(args['from_date'].to_s)
                      else
                        to_date - days.days
                      end

          # Ensure from_date is at least 1 day before to_date
          from_date = to_date - 1.day if from_date >= to_date

          # Find instrument using scopes
          # Map segment string to enum value for Instrument model
          segment_enum = case segment
                         when 'index' then 'index'
                         when 'equity' then 'equity'
                         when 'derivatives' then 'derivatives'
                         when 'currency' then 'currency'
                         when 'commodity' then 'commodity'
                         else segment # fallback
                         end

          instrument = case exchange
                       when 'NSE'
                         case segment_enum
                         when 'index'
                           Instrument.nse.segment_index.find_by(underlying_symbol: underlying_symbol.to_s)
                         when 'equity'
                           Instrument.nse.segment_equity.find_by(underlying_symbol: underlying_symbol.to_s)
                         when 'derivatives'
                           Instrument.nse.segment_derivatives.find_by(underlying_symbol: underlying_symbol.to_s)
                         else
                           Instrument.nse.find_by(underlying_symbol: underlying_symbol.to_s)
                         end
                       when 'BSE'
                         case segment_enum
                         when 'index'
                           Instrument.bse.segment_index.find_by(underlying_symbol: underlying_symbol.to_s)
                         when 'equity'
                           Instrument.bse.segment_equity.find_by(underlying_symbol: underlying_symbol.to_s)
                         when 'derivatives'
                           Instrument.bse.segment_derivatives.find_by(underlying_symbol: underlying_symbol.to_s)
                         else
                           Instrument.bse.find_by(underlying_symbol: underlying_symbol.to_s)
                         end
                       else
                         return { error: "Invalid exchange: #{exchange}. Must be 'NSE' or 'BSE'" }
                       end

          return { error: "Instrument not found: #{underlying_symbol} (#{exchange}, #{segment})" } unless instrument

          # Ensure DhanhqErrorHandler is loaded before calling instrument methods
          ensure_dhanhq_error_handler_loaded

          # Normalize interval format (remove 'm' suffix if present, e.g., "15m" -> "15")
          # DhanHQ expects: "1", "5", "15", "25", "60" (not "1m", "15m", etc.)
          normalized_interval = interval.to_s.gsub(/m$/i, '')

          # Validate interval is one of the allowed values
          allowed_intervals = %w[1 5 15 25 60]
          unless allowed_intervals.include?(normalized_interval)
            return { error: "Invalid interval: #{interval}. Must be one of: #{allowed_intervals.join(', ')}" }
          end

          begin
            # Convert Date objects to strings in YYYY-MM-DD format for API call
            from_date_str = from_date.strftime('%Y-%m-%d')
            to_date_str = to_date.strftime('%Y-%m-%d')

            # Use instrument helper method - it handles all the complexity internally
            # This includes: resolve_instrument_code, exchange_segment, error handling, date defaults
            data = instrument.intraday_ohlc(
              interval: normalized_interval,
              from_date: from_date_str,
              to_date: to_date_str,
              days: days
            )

            return { error: 'No historical data available' } if data.blank?

            {
              underlying_symbol: underlying_symbol,
              exchange: exchange,
              segment: segment,
              security_id: instrument.security_id,
              exchange_segment: instrument.exchange_segment,
              interval: normalized_interval,
              from_date: from_date_str,
              to_date: to_date_str,
              candles: data.is_a?(Array) ? data.first(100) : [], # Limit to 100 candles
              count: data.is_a?(Array) ? data.size : 0
            }
          rescue StandardError => e
            Rails.logger.error("[TechnicalAnalysisAgent] Historical data error: #{e.class} - #{e.message}")
            { error: "#{e.class}: #{e.message}" }
          end
        end

        def tool_analyze_option_chain(args)
          index_key = args['index_key']&.to_s&.upcase
          direction = (args['direction'] || 'bullish').to_sym
          limit = args['limit']&.to_i || 5

          # Cache analyzer instance to avoid repeated initialization
          cache_key = "analyzer:#{index_key}"
          @analyzer_cache ||= {}
          analyzer = @analyzer_cache[cache_key] ||= Options::DerivativeChainAnalyzer.new(index_key: index_key)

          candidates = analyzer.select_candidates(limit: limit, direction: direction)

          {
            index: index_key,
            direction: direction,
            candidates: candidates.map do |c|
              {
                strike: c[:strike],
                type: c[:type],
                ltp: c[:ltp],
                premium: c[:premium],
                score: c[:score]
              }
            end
          }
        end

        def tool_get_trading_stats(args)
          date = args['date'] ? Date.parse(args['date']) : Time.zone.today
          stats = PositionTracker.paper_trading_stats_with_pct(date: date)

          {
            date: date.to_s,
            total_trades: stats[:total_trades],
            winners: stats[:winners],
            losers: stats[:losers],
            win_rate: stats[:win_rate],
            realized_pnl: stats[:realized_pnl_rupees],
            realized_pnl_pct: stats[:realized_pnl_pct]
          }
        end

        def tool_get_active_positions(_args)
          positions = PositionTracker.paper.active

          {
            count: positions.count,
            positions: positions.map do |p|
              {
                symbol: p.symbol,
                entry_price: p.entry_price,
                quantity: p.quantity,
                current_pnl: p.last_pnl_rupees,
                current_pnl_pct: (p.last_pnl_pct || 0) * 100
              }
            end
          }
        end

        def tool_calculate_advanced_indicator(args)
          index_key = args['index_key']&.to_s&.upcase
          indicator_name = args['indicator']&.to_s&.downcase
          interval = args['interval'] || '5'
          config = args['config'] || {}

          # Cache index configs
          @index_config_cache ||= IndexConfigLoader.load_indices

          index_cfg = @index_config_cache.find { |idx| idx[:key].to_s.upcase == index_key }
          return { error: "Unknown index: #{index_key}" } unless index_cfg

          security_id = index_cfg[:security_id] || index_cfg[:sid]
          segment = index_cfg[:segment]
          return { error: "Missing security_id or segment for #{index_key}" } unless security_id && segment

          instrument = Instrument.find_by_sid_and_segment(
            security_id: security_id,
            segment_code: segment,
            underlying_symbol: index_key
          )
          return { error: "Instrument not found for #{index_key}" } unless instrument

          # Ensure DhanhqErrorHandler is loaded before calling instrument methods
          ensure_dhanhq_error_handler_loaded

          # Normalize interval
          normalized_interval = interval.to_s.gsub(/m$/i, '')

          begin
            series = instrument.candles(interval: normalized_interval)
            return { error: "No candle data available for #{index_key}" } unless series&.candles&.any?

            result = case indicator_name
                     when 'holygrail', 'holy_grail'
                       holy_grail_result = Indicators::HolyGrail.new(
                         candles: series.candles,
                         config: config.deep_symbolize_keys
                       ).call
                       {
                         bias: holy_grail_result.bias,
                         adx: holy_grail_result.adx,
                         momentum: holy_grail_result.momentum,
                         proceed: holy_grail_result.proceed?,
                         sma50: holy_grail_result.sma50,
                         ema200: holy_grail_result.ema200,
                         rsi14: holy_grail_result.rsi14,
                         atr14: holy_grail_result.atr14,
                         macd: holy_grail_result.macd,
                         trend: holy_grail_result.trend
                       }
                     when 'trendduration', 'trend_duration'
                       indicator = Indicators::TrendDurationIndicator.new(
                         series: series,
                         config: config.deep_symbolize_keys
                       )
                       last_result = indicator.calculate_at(series.candles.size - 1)
                       {
                         trend_direction: last_result[:trend_direction],
                         duration: last_result[:duration],
                         confidence: last_result[:confidence],
                         probable_duration: last_result[:probable_duration]
                       }
                     else
                       return { error: "Unknown advanced indicator: #{indicator_name}. Available: HolyGrail, TrendDuration" }
                     end

            {
              index: index_key,
              indicator: indicator_name,
              interval: normalized_interval,
              result: result,
              timestamp: Time.current
            }
          rescue StandardError => e
            Rails.logger.error("[TechnicalAnalysisAgent] Advanced indicator error: #{e.class} - #{e.message}")
            { error: "#{e.class}: #{e.message}" }
          end
        end

        def tool_run_backtest(args)
          index_key = args['index_key']&.to_s&.upcase
          interval = args['interval'] || '5'
          days_back = args['days_back']&.to_i || 90
          supertrend_cfg = args['supertrend_cfg'] || {}
          adx_min_strength = args['adx_min_strength']&.to_f || 0

          # Cache index configs
          @index_config_cache ||= IndexConfigLoader.load_indices

          index_cfg = @index_config_cache.find { |idx| idx[:key].to_s.upcase == index_key }
          return { error: "Unknown index: #{index_key}" } unless index_cfg

          symbol = index_key # BacktestService expects symbol name

          begin
            # Use BacktestServiceWithNoTradeEngine for comprehensive backtesting
            service = BacktestServiceWithNoTradeEngine.run(
              symbol: symbol,
              interval_1m: '1',
              interval_5m: interval,
              days_back: days_back,
              supertrend_cfg: supertrend_cfg.deep_symbolize_keys,
              adx_min_strength: adx_min_strength
            )

            summary = service.summary
            {
              index: index_key,
              interval: interval,
              days_back: days_back,
              summary: {
                total_trades: summary[:total_trades],
                winning_trades: summary[:winning_trades],
                losing_trades: summary[:losing_trades],
                win_rate: summary[:win_rate],
                avg_win_percent: summary[:avg_win_percent],
                avg_loss_percent: summary[:avg_loss_percent],
                total_pnl_percent: summary[:total_pnl_percent],
                expectancy: summary[:expectancy],
                max_win: summary[:max_win],
                max_loss: summary[:max_loss]
              },
              no_trade_stats: service.no_trade_stats,
              timestamp: Time.current
            }
          rescue StandardError => e
            Rails.logger.error("[TechnicalAnalysisAgent] Backtest error: #{e.class} - #{e.message}")
            { error: "#{e.class}: #{e.message}" }
          end
        end

        def tool_optimize_indicator(args)
          index_key = args['index_key']&.to_s&.upcase
          interval = args['interval'] || '5'
          lookback_days = args['lookback_days']&.to_i || 45
          test_mode = args['test_mode'] == true

          # Cache index configs
          @index_config_cache ||= IndexConfigLoader.load_indices

          index_cfg = @index_config_cache.find { |idx| idx[:key].to_s.upcase == index_key }
          return { error: "Unknown index: #{index_key}" } unless index_cfg

          security_id = index_cfg[:security_id] || index_cfg[:sid]
          segment = index_cfg[:segment]
          return { error: "Missing security_id or segment for #{index_key}" } unless security_id && segment

          instrument = Instrument.find_by_sid_and_segment(
            security_id: security_id,
            segment_code: segment,
            underlying_symbol: index_key
          )
          return { error: "Instrument not found for #{index_key}" } unless instrument

          begin
            optimizer = Optimization::IndicatorOptimizer.new(
              instrument: instrument,
              interval: interval,
              lookback_days: lookback_days,
              test_mode: test_mode
            )

            result = optimizer.run

            return { error: result[:error] } if result[:error]

            {
              index: index_key,
              interval: interval,
              lookback_days: lookback_days,
              test_mode: test_mode,
              best_params: result[:params],
              best_score: result[:score],
              best_metrics: result[:metrics],
              timestamp: Time.current
            }
          rescue StandardError => e
            Rails.logger.error("[TechnicalAnalysisAgent] Optimization error: #{e.class} - #{e.message}")
            { error: "#{e.class}: #{e.message}" }
          end
        end

        # ==========================================
        # NEW WRAPPER METHODS (Orchestration Layer)
        # These wrap existing tools with narrowing logic
        # ==========================================

        # Wrapper: Resolve instrument deterministically (Rails-controlled)
        def tool_resolve_instrument(args)
          symbol = args['symbol'] || args[:symbol]
          return { error: 'Missing symbol' } unless symbol

          # Use DecisionEngine to resolve deterministically
          # Create temporary context for resolution
          temp_context = AgentContext.new(
            intent: :general,
            underlying_symbol: symbol,
            confidence: 0.5,
            derivatives_needed: false,
            timeframe_hint: '15m'
          )

          instrument = resolve_instrument_deterministically(temp_context)

          return { error: "Instrument not found: #{symbol}" } unless instrument

          {
            instrument_id: instrument.id,
            symbol: instrument.symbol_name,
            segment: instrument.segment,
            exchange: instrument.exchange,
            underlying_symbol: instrument.underlying_symbol
          }
        end

        # Wrapper: Get LTP for resolved instrument
        def tool_get_ltp(args)
          instrument_id = args['instrument_id'] || args[:instrument_id]
          return { error: 'Missing instrument_id' } unless instrument_id

          instrument = Instrument.find_by(id: instrument_id)
          return { error: "Instrument not found: #{instrument_id}" } unless instrument

          # Ensure DhanhqErrorHandler is loaded
          ensure_dhanhq_error_handler_loaded

          # Get LTP using existing method
          ltp = instrument.ltp

          return { error: "Failed to fetch LTP for #{instrument.symbol_name}" } unless ltp

          { ltp: ltp.to_f }
        end

        # Wrapper: Fetch candles (automatically narrowed to last 50)
        def tool_fetch_candles(args)
          instrument_id = args['instrument_id'] || args[:instrument_id]
          interval = args['interval'] || '15m'
          return { error: 'Missing instrument_id' } unless instrument_id

          instrument = Instrument.find_by(id: instrument_id)
          return { error: "Instrument not found: #{instrument_id}" } unless instrument

          # Ensure DhanhqErrorHandler is loaded
          ensure_dhanhq_error_handler_loaded

          normalized_interval = interval.to_s.gsub(/m$/i, '')

          begin
            series = instrument.candles(interval: normalized_interval)
            return { error: "No candle data available for #{instrument.symbol_name}" } unless series&.candles&.any?

            # Narrow to last 50 candles
            candles = series.candles.last(50)
            {
              instrument_id: instrument_id,
              interval: interval,
              candle_count: candles.length,
              latest_candle: candles.last,
              candles: candles # Keep for now, will be filtered by AdaptiveController
            }
          rescue StandardError => e
            Rails.logger.error("[TechnicalAnalysisAgent] Error fetching candles: #{e.class} - #{e.message}")
            { error: "Failed to fetch candle data: #{e.message}" }
          end
        end

        # NEW: Aggregate indicators (coarse-grained)
        def tool_compute_indicators(args)
          instrument_id = args['instrument_id'] || args[:instrument_id]
          timeframes = args['timeframes'] || ['15m']
          return { error: 'Missing instrument_id' } unless instrument_id

          instrument = Instrument.find_by(id: instrument_id)
          return { error: "Instrument not found: #{instrument_id}" } unless instrument

          # Ensure DhanhqErrorHandler is loaded
          ensure_dhanhq_error_handler_loaded

          indicators = {}
          timeframes.each do |tf|
            normalized_tf = tf.to_s.gsub(/m$/i, '')
            begin
              series = instrument.candles(interval: normalized_tf)

              # Handle case where candles() returns nil (DhanHQ error)
              unless series&.candles&.any?
                Rails.logger.warn("[TechnicalAnalysisAgent] No candle data available for #{instrument.symbol_name} @ #{tf}")
                indicators[tf] = { error: "No candle data available for #{tf}" }
                next
              end

              indicators[tf] = {
                rsi: series.rsi(14),
                macd: series.macd(12, 26, 9),
                adx: series.adx(14),
                supertrend: series.supertrend_signal,
                atr: series.atr(14),
                bollinger: series.bollinger_bands(period: 20)
              }
            rescue StandardError => e
              Rails.logger.error("[TechnicalAnalysisAgent] Error computing indicators for #{tf}: #{e.class} - #{e.message}")
              indicators[tf] = { error: e.message }
            end
          end

          { indicators: indicators }
        end

        # Wrapper: Fetch option chain (automatically filtered to ATM ±1 ±2)
        def tool_fetch_option_chain(args)
          instrument_id = args['instrument_id'] || args[:instrument_id]
          return { error: 'Missing instrument_id' } unless instrument_id

          instrument = Instrument.find_by(id: instrument_id)
          return { error: "Instrument not found: #{instrument_id}" } unless instrument

          # Resolve index_key from instrument
          # For index instruments, use symbol_name; for derivatives, use underlying_symbol
          segment_upcase = instrument.segment.to_s.upcase
          index_key = if %w[IDX_I INDEX].include?(segment_upcase)
                        instrument.symbol_name
                      else
                        instrument.underlying_symbol || instrument.symbol_name
                      end

          return { error: "Could not resolve index_key for instrument #{instrument_id}" } if index_key.blank?

          # Verify index_key exists in config
          @index_config_cache ||= IndexConfigLoader.load_indices
          index_cfg = @index_config_cache.find { |idx| idx[:key].to_s.upcase == index_key.to_s.upcase }
          # rubocop:disable Rails/Pluck
          return { error: "Unknown index: #{index_key}. Available indices: #{@index_config_cache.map { |c| c[:key] }.join(', ')}" } unless index_cfg
          # rubocop:enable Rails/Pluck

          # Use analyzer directly to get full chain data
          cache_key = "analyzer:#{index_key}"
          @analyzer_cache ||= {}
          analyzer = @analyzer_cache[cache_key] ||= Options::DerivativeChainAnalyzer.new(index_key: index_key)

          # Get spot price
          spot = analyzer.spot_ltp
          return { error: "Could not get spot price for #{index_key}" } unless spot&.positive?

          # Get nearest expiry
          expiry_date = analyzer.nearest_expiry
          return { error: "Could not determine expiry for #{index_key}" } unless expiry_date

          # Load chain for expiry (returns array of option data hashes)
          chain = analyzer.load_chain_for_expiry(expiry_date, spot)
          return { error: "No option chain data available for #{index_key}" } unless chain.is_a?(Array) && chain.any?

          # Calculate ATM strike
          round_to = if %w[NIFTY BANKNIFTY SENSEX].include?(index_key.to_s.upcase)
                       50
                     else
                       5
                     end
          atm_strike = (spot.to_f / round_to).round * round_to

          # Filter to ATM ±1 ±2 only (each option data hash has a :strike key)
          filtered = chain.select do |option_data|
            strike_value = option_data[:strike] || option_data['strike']
            next false unless strike_value

            strike_diff = (strike_value.to_f - atm_strike).abs
            strike_diff <= (round_to * 2) # ATM, ATM±1, ATM±2
          end

          # Extract unique strikes (since we have both CE and PE for each strike)
          unique_strikes = filtered.filter_map { |o| o[:strike] || o['strike'] }.uniq.sort.first(5)

          # Build strikes array in format expected by context
          strikes = unique_strikes.map do |strike_val|
            # Find CE and PE for this strike
            ce_option = filtered.find do |o|
              (o[:strike] || o['strike']) == strike_val && (o[:type] || o['type'])&.upcase == 'CE'
            end
            pe_option = filtered.find do |o|
              (o[:strike] || o['strike']) == strike_val && (o[:type] || o['type'])&.upcase == 'PE'
            end

            {
              strike: strike_val,
              ce: if ce_option
                    { ltp: ce_option[:ltp] || ce_option['ltp'],
                      premium: ce_option[:ltp] || ce_option['ltp'] }
                  end,
              pe: if pe_option
                    { ltp: pe_option[:ltp] || pe_option['ltp'],
                      premium: pe_option[:ltp] || pe_option['ltp'] }
                  end
            }
          end

          {
            spot: spot,
            atm_strike: atm_strike,
            strikes: strikes
          }
        end

        # NEW: Check data availability
        def tool_check_data_availability(_args)
          # This is a placeholder - actual check is done in AgentContext#ready_for_analysis?
          { available: true, message: 'Data availability check' }
        end
      end
    end
  end
end
