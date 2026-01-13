# frozen_string_literal: true

module Smc
  # AI-powered SMC analysis with pre-fetched data (no tool calling)
  # Optimized to fetch all required data upfront and perform single-pass analysis
  class AiAnalyzer
    def initialize(instrument, initial_data:)
      @instrument = instrument
      @initial_data = initial_data
      @ai_client = Services::Ai::OpenaiClient.instance
      @model = select_model
      @prefetched_data = {}
    end

    def analyze(stream: false, &)
      return nil unless ai_enabled?

      # Pre-fetch all required data upfront
      prefetch_all_data

      # Build comprehensive prompt with all data
      prompt = build_comprehensive_prompt

      # Single-pass AI analysis
      if stream && block_given?
        execute_streaming_analysis(prompt, &)
      else
        execute_single_pass_analysis(prompt)
      end
    rescue StandardError => e
      Rails.logger.error("[Smc::AiAnalyzer] Error: #{e.class} - #{e.message}")
      Rails.logger.debug { e.backtrace.first(5).join("\n") }
      nil
    end

    private

    def ai_enabled?
      AlgoConfig.fetch.dig(:ai, :enabled) == true && @ai_client.enabled?
    rescue StandardError
      false
    end

    def select_model
      if @ai_client.provider == :ollama
        @ai_client.selected_model || ENV['OLLAMA_MODEL'] || 'llama3.2:3b'
      else
        'gpt-4o'
      end
    end

    # Pre-fetch all required data upfront to avoid redundant API calls
    def prefetch_all_data
      Rails.logger.info("[Smc::AiAnalyzer] Pre-fetching all required data for #{@instrument.symbol_name}")

      # 1. Current LTP (already available, no API call)
      @prefetched_data[:ltp] = current_ltp
      ltp_value = @prefetched_data[:ltp][:ltp] || @prefetched_data[:ltp]['ltp'] || 0.0

      # 2. Trend analysis (uses existing candles, no API call)
      @prefetched_data[:trend_analysis] = compute_trend_analysis

      # 3. Option chain (only for indices, may make API call)
      if is_index?
        Rails.logger.debug('[Smc::AiAnalyzer] Pre-fetching option chain for index')
        @prefetched_data[:option_chain] = fetch_option_chain_data
      else
        @prefetched_data[:option_chain] = nil
      end

      # 4. Technical indicators (optional, can be expensive - fetch only if needed)
      # Skip by default to avoid expensive API calls unless explicitly needed
      @prefetched_data[:technical_indicators] = fetch_technical_indicators_if_needed

      # 5. Historical candles summary (already computed for trend, just format it)
      @prefetched_data[:candles_summary] = format_candles_summary

      Rails.logger.info("[Smc::AiAnalyzer] Data pre-fetch complete. Option chain: #{@prefetched_data[:option_chain].present? ? 'available' : 'N/A'}, Indicators: #{@prefetched_data[:technical_indicators].present? ? 'available' : 'N/A'}")
    end

    def is_index?
      segment = @instrument.exchange_segment
      segment.to_s.upcase == 'IDX_I'
    end

    def current_ltp
      ltp = @instrument.ltp || @instrument.latest_ltp
      { ltp: ltp.to_f, symbol: @instrument.symbol_name }
    end

    def fetch_option_chain_data
      return nil unless is_index?

      begin
        # Use the same logic as get_option_chain but without tool wrapper
        index_key = @instrument.symbol_name
        expiry_list = @instrument.expiry_list

        unless expiry_list&.any?
          Rails.logger.warn("[Smc::AiAnalyzer] No expiry list available for #{index_key}")
          return nil
        end

        # Parse and find nearest expiry
        today = Time.zone.today
        parsed_expiries = expiry_list.compact.filter_map do |raw|
          case raw
          when Date then raw
          when Time, DateTime, ActiveSupport::TimeWithZone then raw.to_date
          when String
            begin
              Date.parse(raw)
            rescue ArgumentError
              nil
            end
          end
        end

        valid_expiries = parsed_expiries.select { |date| date >= today }.sort
        unless valid_expiries.any?
          Rails.logger.warn("[Smc::AiAnalyzer] No future expiry dates found for #{index_key}")
          return nil
        end

        expiry = valid_expiries.min
        spot = @instrument.ltp&.to_f || @instrument.latest_ltp&.to_f

        unless spot&.positive?
          Rails.logger.warn("[Smc::AiAnalyzer] No valid spot LTP for #{index_key}")
          return nil
        end

        # Load chain using DerivativeChainAnalyzer
        analyzer = Options::DerivativeChainAnalyzer.new(index_key: index_key)
        chain = analyzer.load_chain_for_expiry(expiry, spot)

        # Filter to ATM±2 strikes
        strike_rounding = case index_key.to_s.upcase
                          when 'SENSEX', 'BANKNIFTY' then 100
                          else 50
                          end
        atm_strike = ((spot / strike_rounding).round * strike_rounding).to_i
        max_strike_distance = strike_rounding * 2

        filtered_chain = chain.select do |opt|
          strike = opt[:strike]&.to_f || opt['strike']&.to_f
          next false unless strike&.positive?

          (strike - atm_strike).abs <= max_strike_distance
        end

        lot_size = @instrument.lot_size_from_derivatives

        {
          index: index_key,
          expiry: expiry.to_s,
          spot: spot,
          lot_size: lot_size,
          available_expiries: valid_expiries.first(10).map(&:to_s),
          options: filtered_chain.first(20).map do |opt|
            raw_type = opt[:type] || opt[:option_type]
            normalized_type = case raw_type.to_s.upcase
                              when 'CE', 'CALL' then 'CE'
                              when 'PE', 'PUT' then 'PE'
                              else
                                opt[:delta]&.positive? ? 'CE' : 'PE'
                              end

            {
              strike: opt[:strike],
              option_type: normalized_type,
              ltp: opt[:ltp],
              premium: opt[:ltp],
              delta: opt[:delta],
              theta: opt[:theta],
              gamma: opt[:gamma],
              iv: opt[:iv],
              oi: opt[:oi],
              change: opt[:change],
              lot_size: opt[:lot_size] || lot_size
            }
          end
        }
      rescue StandardError => e
        Rails.logger.error("[Smc::AiAnalyzer] Failed to fetch option chain: #{e.class} - #{e.message}")
        nil
      end
    end

    def fetch_technical_indicators_if_needed
      # Skip by default to avoid expensive API calls
      # Only fetch if explicitly needed (can be enabled via config)
      return nil unless ENV['SMC_AI_FETCH_INDICATORS'] == 'true'

      begin
        symbol_name = @instrument.symbol_name.to_s.upcase
        index_symbol = case symbol_name
                       when 'NIFTY' then :nifty
                       when 'SENSEX' then :sensex
                       when 'BANKNIFTY' then :banknifty
                       else
                         symbol_name.downcase.to_sym
                       end

        analyzer = IndexTechnicalAnalyzer.new(index_symbol)
        result = analyzer.call(timeframes: [15]) # Use 15m timeframe

        return nil unless result[:success] && analyzer.indicators

        indicators_for_timeframe = analyzer.indicators[15] || analyzer.indicators['15']
        return nil unless indicators_for_timeframe

        {
          timeframe: '15m',
          rsi: indicators_for_timeframe[:rsi],
          macd: indicators_for_timeframe[:macd],
          adx: indicators_for_timeframe[:adx],
          atr: indicators_for_timeframe[:atr]
        }
      rescue StandardError => e
        Rails.logger.warn("[Smc::AiAnalyzer] Failed to fetch indicators: #{e.message}")
        nil
      end
    end

    def format_candles_summary
      # Get recent candles for summary (already computed in trend analysis)
      series = @instrument.candles(interval: '5')
      candles = series&.candles&.last(20) || []

      return nil if candles.empty?

      {
        count: candles.size,
        latest: {
          timestamp: candles.last.timestamp,
          open: candles.last.open,
          high: candles.last.high,
          low: candles.last.low,
          close: candles.last.close,
          volume: candles.last.volume
        },
        summary: {
          high: candles.map(&:high).max,
          low: candles.map(&:low).min,
          avg_volume: (candles.map(&:volume).sum.to_f / candles.size).round(2)
        }
      }
    end

    # Compute actual price trend analysis from OHLC data
    def compute_trend_analysis
      series = @instrument.candles(interval: '5')
      candles = series&.candles || []

      return 'Insufficient candle data for trend analysis' if candles.size < 10

      recent_candles = candles.last(225) # ~3 days
      daily_data = group_candles_by_day(recent_candles)

      current_price = candles.last.close
      first_price = recent_candles.first.close
      price_change = current_price - first_price
      price_change_pct = (price_change / first_price * 100).round(2)

      gap_analysis = detect_gaps(recent_candles)
      trend_direction = if price_change_pct < -0.5
                          'BEARISH'
                        elsif price_change_pct > 0.5
                          'BULLISH'
                        else
                          'SIDEWAYS'
                        end

      pattern = detect_swing_pattern(daily_data)

      <<~ANALYSIS
        **Overall Trend: #{trend_direction}**
        - Price change over period: #{'+' if price_change >= 0}#{price_change.round(2)} points (#{'+' if price_change_pct >= 0}#{price_change_pct}%)
        - First candle close: ₹#{first_price.round(2)}
        - Current price: ₹#{current_price.round(2)}

        **Gap Analysis:**
        #{gap_analysis}

        **Swing Pattern:**
        #{pattern}

        **Daily Summary:**
        #{format_daily_summary(daily_data)}

        **DIRECTION RECOMMENDATION:**
        #{direction_recommendation(trend_direction, gap_analysis, pattern)}
      ANALYSIS
    rescue StandardError => e
      Rails.logger.warn("[Smc::AiAnalyzer] Trend analysis error: #{e.message}")
      'Trend analysis unavailable - proceed with caution and analyze candle data manually'
    end

    def group_candles_by_day(candles)
      return {} if candles.empty?

      grouped = candles.group_by { |c| c.timestamp.to_date }
      grouped.transform_values do |day_candles|
        {
          open: day_candles.first.open,
          high: day_candles.map(&:high).max,
          low: day_candles.map(&:low).min,
          close: day_candles.last.close,
          date: day_candles.first.timestamp.to_date
        }
      end
    end

    def detect_gaps(candles)
      gaps = []
      prev_candle = nil

      candles.each do |candle|
        if prev_candle
          gap = candle.open - prev_candle.close
          gap_pct = (gap / prev_candle.close * 100).abs

          if gap_pct > 0.3
            gap_type = gap.positive? ? 'GAP UP' : 'GAP DOWN'
            gaps << {
              type: gap_type,
              size: gap.abs.round(2),
              pct: gap_pct.round(2),
              time: candle.timestamp
            }
          end
        end
        prev_candle = candle
      end

      if gaps.empty?
        '- No significant gaps detected'
      else
        recent_gaps = gaps.last(3)
        recent_gaps.map do |g|
          "- #{g[:type]}: #{g[:size]} points (#{g[:pct]}%) at #{g[:time]}"
        end.join("\n")
      end
    end

    def detect_swing_pattern(daily_data)
      return '- Insufficient daily data' if daily_data.size < 2

      dates = daily_data.keys.sort
      lows = dates.map { |d| daily_data[d][:low] }
      highs = dates.map { |d| daily_data[d][:high] }

      lower_lows = lows.each_cons(2).all? { |a, b| b < a }
      lower_highs = highs.each_cons(2).all? { |a, b| b < a }
      higher_lows = lows.each_cons(2).all? { |a, b| b > a }
      higher_highs = highs.each_cons(2).all? { |a, b| b > a }

      patterns = []
      patterns << '- LOWER LOWS detected (bearish)' if lower_lows
      patterns << '- LOWER HIGHS detected (bearish)' if lower_highs
      patterns << '- HIGHER LOWS detected (bullish)' if higher_lows
      patterns << '- HIGHER HIGHS detected (bullish)' if higher_highs

      if patterns.empty?
        '- Mixed pattern (no clear trend)'
      else
        patterns.join("\n")
      end
    end

    def format_daily_summary(daily_data)
      return '- No daily data available' if daily_data.empty?

      dates = daily_data.keys.sort.last(3)
      dates.map do |date|
        d = daily_data[date]
        "- #{date}: Open ₹#{d[:open].round(2)}, High ₹#{d[:high].round(2)}, Low ₹#{d[:low].round(2)}, Close ₹#{d[:close].round(2)}"
      end.join("\n")
    end

    def direction_recommendation(trend, gap_analysis, pattern)
      bearish_signals = 0
      bullish_signals = 0

      bearish_signals += 2 if trend == 'BEARISH'
      bullish_signals += 2 if trend == 'BULLISH'
      bearish_signals += 2 if gap_analysis.include?('GAP DOWN')
      bullish_signals += 2 if gap_analysis.include?('GAP UP')
      bearish_signals += 1 if pattern.include?('LOWER LOWS')
      bearish_signals += 1 if pattern.include?('LOWER HIGHS')
      bullish_signals += 1 if pattern.include?('HIGHER LOWS')
      bullish_signals += 1 if pattern.include?('HIGHER HIGHS')

      if bearish_signals > bullish_signals + 1
        <<~REC
          ⚠️ BEARISH BIAS DETECTED - DO NOT RECOMMEND BUY CE
          - If trading: Consider BUY PE or AVOID
          - Bearish signals: #{bearish_signals}, Bullish signals: #{bullish_signals}
        REC
      elsif bullish_signals > bearish_signals + 1
        <<~REC
          ✅ BULLISH BIAS DETECTED - BUY CE may be appropriate
          - If trading: Consider BUY CE
          - Bullish signals: #{bullish_signals}, Bearish signals: #{bearish_signals}
        REC
      else
        <<~REC
          ⚠️ MIXED SIGNALS - Consider AVOID TRADING
          - No clear directional bias
          - Bullish signals: #{bullish_signals}, Bearish signals: #{bearish_signals}
        REC
      end
    end

    def build_comprehensive_prompt
      symbol_name = @instrument.symbol_name.to_s.upcase
      decision = @initial_data[:decision]
      ltp_value = @prefetched_data[:ltp][:ltp] || @prefetched_data[:ltp]['ltp'] || 0.0

      strike_rounding = case symbol_name
                        when 'SENSEX', 'BANKNIFTY' then 100
                        else 50
                        end

      lot_size = @instrument.lot_size_from_derivatives
      atm_strike = ltp_value.positive? ? ((ltp_value / strike_rounding).round * strike_rounding).to_i : nil

      # Determine trend direction
      trend_direction = determine_trend_direction

      prompt_parts = []
      prompt_parts << system_prompt
      prompt_parts << ''
      prompt_parts << ('=' * 80)
      prompt_parts << 'COMPLETE MARKET DATA (ALL DATA PROVIDED - NO TOOLS NEEDED)'
      prompt_parts << ('=' * 80)
      prompt_parts << ''
      prompt_parts << "**INDEX:** #{symbol_name}"
      prompt_parts << "**CURRENT LTP:** ₹#{ltp_value.round(2)}"
      prompt_parts << "**ATM STRIKE:** ₹#{atm_strike || 'N/A'} (rounded to nearest #{strike_rounding})"
      prompt_parts << "**LOT SIZE:** #{lot_size || 'N/A'} (1 lot = #{lot_size || 'N/A'} shares)"
      prompt_parts << "**SMC DECISION:** #{decision}"
      prompt_parts << "**DETECTED TREND:** #{trend_direction.to_s.upcase}"
      prompt_parts << ''

      # Add trend-based recommendation
      case trend_direction
      when :bearish
        prompt_parts << '📉 **BEARISH TREND DETECTED** - This is a TRADING OPPORTUNITY for BUY PE!'
        prompt_parts << '   ✅ **STRONGLY RECOMMEND: BUY PE** (bearish markets are profitable for PUT options)'
        prompt_parts << '   ❌ DO NOT recommend BUY CE in a bearish market!'
        recommended_option = 'PE'
      when :bullish
        prompt_parts << '📈 **BULLISH TREND DETECTED** - This is a TRADING OPPORTUNITY for BUY CE!'
        prompt_parts << '   ✅ **STRONGLY RECOMMEND: BUY CE** (bullish markets are profitable for CALL options)'
        prompt_parts << '   ❌ DO NOT recommend BUY PE in a bullish market!'
        recommended_option = 'CE'
      else
        prompt_parts << '⚠️ **NEUTRAL/UNCLEAR TREND** - Recommend AVOID trading (no clear direction)'
        recommended_option = nil
      end
      prompt_parts << ''

      # Add trend analysis
      prompt_parts << '**PRICE TREND ANALYSIS:**'
      prompt_parts << @prefetched_data[:trend_analysis]
      prompt_parts << ''

      # Add market structure
      prompt_parts << '**MARKET STRUCTURE ANALYSIS (Multi-Timeframe):**'
      prompt_parts << JSON.pretty_generate(@initial_data[:timeframes])
      prompt_parts << ''

      # Add option chain data if available
      if @prefetched_data[:option_chain]&.dig(:options)&.any?
        prompt_parts << build_option_chain_section(@prefetched_data[:option_chain], atm_strike, symbol_name,
                                                   trend_direction)
        prompt_parts << ''
      end

      # Add technical indicators if available
      if @prefetched_data[:technical_indicators]
        prompt_parts << '**TECHNICAL INDICATORS:**'
        indicators = @prefetched_data[:technical_indicators]
        prompt_parts << "- RSI: #{indicators[:rsi]&.round(2) || 'N/A'}"
        prompt_parts << "- MACD: #{indicators[:macd]&.to_json || 'N/A'}"
        prompt_parts << "- ADX: #{indicators[:adx]&.round(2) || 'N/A'}"
        prompt_parts << "- ATR: #{indicators[:atr]&.round(2) || 'N/A'}"
        prompt_parts << ''
      end

      # Add analysis instructions
      prompt_parts << '**YOUR TASK:**'
      if recommended_option
        prompt_parts << "**STRONGLY PREFER: BUY #{recommended_option}** (this is a trading opportunity based on clear trend)"
        prompt_parts << 'Only recommend AVOID if there are SPECIFIC risk factors that make trading dangerous.'
        prompt_parts << "If you choose to trade, use the #{recommended_option} option data provided above."
      else
        prompt_parts << 'Given the unclear trend, recommend **AVOID TRADING**.'
      end
      prompt_parts << ''
      prompt_parts << initial_analysis_instructions

      prompt_parts.join("\n")
    end

    def determine_trend_direction
      htf_trend = @initial_data.dig(:timeframes, :htf, :trend)
      mtf_trend = @initial_data.dig(:timeframes, :mtf, :trend)
      ltf_trend = @initial_data.dig(:timeframes, :ltf, :trend)

      bearish_count = [htf_trend, mtf_trend, ltf_trend].count { |t| t.to_s == 'bearish' }
      bullish_count = [htf_trend, mtf_trend, ltf_trend].count { |t| t.to_s == 'bullish' }

      trend_analysis = @prefetched_data[:trend_analysis].to_s
      bearish_count += 2 if trend_analysis.include?('Overall Trend: BEARISH')
      bullish_count += 2 if trend_analysis.include?('Overall Trend: BULLISH')
      bearish_count += 1 if trend_analysis.include?('LOWER LOWS')
      bearish_count += 1 if trend_analysis.include?('LOWER HIGHS')
      bullish_count += 1 if trend_analysis.include?('HIGHER LOWS')
      bullish_count += 1 if trend_analysis.include?('HIGHER HIGHS')

      if bearish_count > bullish_count
        :bearish
      elsif bullish_count > bearish_count
        :bullish
      else
        :neutral
      end
    end

    def build_option_chain_section(option_chain_data, atm_strike, symbol_name, trend_direction)
      options = option_chain_data[:options]
      expiry = option_chain_data[:expiry]
      spot = option_chain_data[:spot]
      lot_size = option_chain_data[:lot_size]

      lines = []
      lines << '**OPTION CHAIN DATA (CRITICAL: Use ONLY these EXACT strikes and premiums):**'
      lines << "- Expiry: #{expiry}"
      lines << "- Current Spot (LTP): ₹#{spot&.round(2)}"
      lines << "- Calculated ATM Strike: ₹#{atm_strike || 'N/A'}"
      lines << "- Lot Size: #{lot_size} (1 lot = #{lot_size} shares)"
      lines << ''

      ce_options = options.select { |o| o[:option_type] == 'CE' }
      pe_options = options.select { |o| o[:option_type] == 'PE' }

      case trend_direction
      when :bearish
        lines << '**AVAILABLE PUT (PE) OPTIONS (use ONLY these strikes):**'
        pe_options.sort_by { |o| o[:strike].to_f }.each do |opt|
          strike = opt[:strike].to_i
          premium = opt[:ltp]&.to_f
          delta = opt[:delta]&.to_f
          is_atm = strike == atm_strike
          label = is_atm ? ' (ATM)' : ''
          lines << "- Strike ₹#{strike}#{label}: Premium ₹#{premium&.round(2) || 'N/A'}, Delta #{delta&.round(5) || 'N/A'}"
        end
      when :bullish
        lines << '**AVAILABLE CALL (CE) OPTIONS (use ONLY these strikes):**'
        ce_options.sort_by { |o| o[:strike].to_f }.each do |opt|
          strike = opt[:strike].to_i
          premium = opt[:ltp]&.to_f
          delta = opt[:delta]&.to_f
          is_atm = strike == atm_strike
          label = is_atm ? ' (ATM)' : ''
          lines << "- Strike ₹#{strike}#{label}: Premium ₹#{premium&.round(2) || 'N/A'}, Delta #{delta&.round(5) || 'N/A'}"
        end
      else
        lines << '**AVAILABLE OPTIONS (both CE and PE):**'
        lines << '**CALL (CE) OPTIONS:**'
        ce_options.sort_by { |o| o[:strike].to_f }.first(5).each do |opt|
          lines << "- Strike ₹#{opt[:strike].to_i}: Premium ₹#{opt[:ltp]&.to_f&.round(2) || 'N/A'}"
        end
        lines << '**PUT (PE) OPTIONS:**'
        pe_options.sort_by { |o| o[:strike].to_f }.first(5).each do |opt|
          lines << "- Strike ₹#{opt[:strike].to_i}: Premium ₹#{opt[:ltp]&.to_f&.round(2) || 'N/A'}"
        end
      end

      lines.join("\n")
    end

    def system_prompt
      <<~PROMPT
        You are an expert Smart Money Concepts (SMC) and market structure analyst specializing in Indian index options trading (NIFTY, BANKNIFTY, SENSEX).

        Your PRIMARY GOAL: Provide clear, actionable trading recommendations for options buyers.

        CRITICAL: This is an OPTIONS BUYING strategy ONLY. We ONLY BUY options (CALL or PUT) - we NEVER write/sell options.
        TERMINOLOGY: Always use "EXIT" or "exit the position" - NEVER use "sell options" (which implies options selling/writing).
        Exit strategy must use: SL (stop loss), TP1 (take profit 1), optionally TP2 (take profit 2).
        Always provide index spot levels (underlying index price) to watch for exit decisions.

        **CRITICAL: DIRECTION ACCURACY IS YOUR TOP PRIORITY**

        Before recommending BUY CE or BUY PE, you MUST:
        1. **Analyze the ACTUAL price trend from candle data** - NOT just SMC signals
        2. **Check for gap ups/downs** - Gap downs indicate bearish momentum, gap ups indicate bullish
        3. **Verify price direction over last 2-3 days** - Is price making lower lows (bearish) or higher highs (bullish)?
        4. **Match your recommendation to actual price movement** - DO NOT recommend BUY CE when price is declining

        **TREND DETECTION RULES:**
        - If price has declined >1% over 2-3 days AND making lower lows → BEARISH → **PREFER BUY PE** (bearish markets are profitable for PUT options)
        - If price has risen >1% over 2-3 days AND making higher highs → BULLISH → **PREFER BUY CE** (bullish markets are profitable for CALL options)
        - If there's a gap down at market open → BEARISH signal → **PREFER BUY PE** (NOT BUY CE)
        - If there's a gap up at market open → BULLISH signal → **PREFER BUY CE**
        - If SMC shows "no_trade" BUT price trend is clear (bearish/bullish) → **STILL RECOMMEND BUY PE/CE** based on trend (SMC "no_trade" just means no SMC signal, but clear price trend is enough)
        - **ONLY recommend AVOID if**: Extreme volatility, no clear structure, conflicting signals, or high risk conditions that make trading dangerous
        - **CRITICAL**: Bearish markets are OPPORTUNITIES for BUY PE trades - do NOT avoid just because market is bearish!

        **DO NOT:**
        - Recommend BUY CE when price is clearly declining (lower highs, lower lows)
        - Ignore gap downs/ups when making recommendations
        - Give bullish recommendations in a bearish trend
        - Override clear price action with SMC signals alone

        You analyze market structure, liquidity, premium/discount zones, order blocks, and AVRZ rejections to determine:
        - Whether to trade or avoid trading
        - If trading: Buy CE (CALL) or Buy PE (PUT) - MUST match actual price direction
        - Specific strike prices to select
        - Entry strategy (when and how to enter)
        - Exit strategy (when to take profit and stop loss)
        - Risk management guidelines

        CRITICAL: Always provide specific, actionable recommendations:
        - Use exact strike prices from the option chain data provided
        - ALWAYS use premium prices (LTP) from the option chain data - NEVER estimate or guess
        - Stop Loss (SL) and Take Profit (TP1, TP2) MUST be based on premium percentages, NOT underlying prices
        - Always provide index spot levels (underlying index price) to watch for exit decisions
        - CRITICAL: Calculate percentages correctly - if entry is ₹100, 30% loss = ₹70 (NOT ₹30), 50% gain = ₹150 (NOT ₹50)
        - CRITICAL: NEVER mix strike prices with premium prices in calculations
        - Use DELTA to calculate underlying levels CORRECTLY: Underlying move = Premium move / Delta
        - Consider THETA (time decay) and expiry date when setting targets
        - Intraday realistic expectations: TP 10-25% gain, SL 15-25% loss (NOT 50-100% for intraday)
        - Exit Strategy Format: "Entry premium: ₹X. SL at premium ₹Y (exit at index spot ₹ABC). TP1 at premium ₹W (exit at index spot ₹DEF). TP2 at premium ₹V (exit at index spot ₹GHI) - calculated using Delta"
        - Risk Management Format: "Position size: X lots. Risk per trade: ₹Y (premium loss × lot size × shares per lot). Maximum loss: ₹Z"
        - Never give vague recommendations - always be specific and actionable
      PROMPT
    end

    def initial_analysis_instructions
      <<~INSTRUCTIONS
        **MANDATORY SECTIONS:**

        1. **Trade Decision** (MANDATORY):
           - State clearly: "BUY CE" or "BUY PE" or "AVOID TRADING"
           - **CRITICAL**: Your decision MUST match the actual price trend provided above
           - If AVOID: Explain the SPECIFIC risk factors that make trading dangerous

        2. **Strike Selection** (MANDATORY if trading):
           - Use ONLY the strikes listed in the option chain data above
           - DO NOT calculate, invent, or guess strike prices
           - Label each strike (ATM, ATM+1, ATM-1, etc.) based on which strike is closest to the current LTP
           - Explain why these strikes were chosen based on SMC levels

        3. **Entry Strategy** (MANDATORY if trading):
           - Format: "Enter at premium ₹X (actual LTP from option chain for strike ₹Y)"
           - Entry timing (immediate, wait for pullback, wait for confirmation)
           - How to enter (market order, limit order, specific premium price level)
           - MUST use the exact premium (LTP) value from the option chain data

        4. **Exit Strategy** (MANDATORY if trading):
           - Stop Loss (SL): Provide premium level AND corresponding index spot level to watch
             * Format: "SL at premium ₹X (exit at index spot ₹Y)"
             * Calculate index spot level using DELTA from option chain
           - Take Profit: Use TP1, TP2 format for multiple targets
             * Format: "TP1 at premium ₹X (exit at index spot ₹Y)"
             * Format: "TP2 at premium ₹X (exit at index spot ₹Y)" (optional)
           - Index Spot Levels to Watch: Provide key underlying index price levels to monitor
           - Calculate using DELTA: Index level = Current spot ± (Premium move / Delta)
           - YOU MUST calculate SL/TP based on premium percentages, NOT underlying prices
           - Intraday realistic expectations: TP 10-25% gain, SL 15-25% loss

        5. **Risk Management** (MANDATORY if trading):
           - Position size recommendation: "Position size: N lots (X shares total)"
           - Risk per trade: "Risk per trade: ₹Y (premium loss ₹Z × lot size × N lots)"
           - Maximum loss: State the maximum acceptable loss for this trade
           - Risk-reward ratio: Calculate and state (e.g., "Risk-reward ratio: 1:2.5")
           - Time decay considerations: Expiry date impact on premium erosion

        6. **Market Structure Context** (Brief):
           - Overall trend and structure breaks
           - Key liquidity zones and order blocks
           - Premium/Discount position

        Focus on providing actionable, specific recommendations that a trader can execute immediately.
      INSTRUCTIONS
    end

    def execute_single_pass_analysis(prompt)
      Rails.logger.info('[Smc::AiAnalyzer] Executing single-pass AI analysis')

      response = @ai_client.chat(
        messages: [
          {
            role: 'system',
            content: system_prompt
          },
          {
            role: 'user',
            content: prompt
          }
        ],
        model: @model,
        temperature: 0.3
      )

      if response.is_a?(Hash)
        response[:content] || response['content'] || response.to_s
      else
        response.to_s
      end
    end

    def execute_streaming_analysis(prompt, &)
      Rails.logger.info('[Smc::AiAnalyzer] Executing streaming AI analysis')

      full_response = +''
      @ai_client.chat_stream(
        messages: [
          {
            role: 'system',
            content: system_prompt
          },
          {
            role: 'user',
            content: prompt
          }
        ],
        model: @model,
        temperature: 0.3
      ) do |chunk|
        full_response << chunk if chunk.present?
        yield(chunk) if block_given?
      end

      full_response.presence
    end
  end
end
