# frozen_string_literal: true

module Smc
  # AI-powered SMC analysis using chat completion with history and tool calling
  class AiAnalyzer
    # Reduced from 10 to 5 - if model hasn't provided analysis by iteration 5, force output
    MAX_ITERATIONS = ENV.fetch('SMC_AI_MAX_ITERATIONS', '5').to_i
    MAX_MESSAGE_HISTORY = ENV.fetch('SMC_AI_MAX_MESSAGE_HISTORY', '12').to_i

    # Circuit breaker: After this many duplicate tool calls, skip straight to forced analysis
    MAX_DUPLICATE_TOOL_CALLS = 2

    def initialize(instrument, initial_data:)
      @instrument = instrument
      @initial_data = initial_data
      @messages = []
      @tool_cache = {}
      @ai_client = Services::Ai::OpenaiClient.instance
      @model = select_model
    end

    def analyze(stream: false, &)
      return nil unless ai_enabled?

      initialize_conversation

      if stream && block_given?
        execute_conversation_stream(&)
      else
        execute_conversation
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

    def initialize_conversation
      # Get current LTP first and include it in the initial prompt
      ltp_data = current_ltp
      ltp_value = ltp_data[:ltp] || ltp_data['ltp'] || 0.0
      symbol_name = @instrument.symbol_name.to_s.upcase

      # Calculate strike rounding based on index
      strike_rounding = case symbol_name
                        when 'SENSEX', 'BANKNIFTY' then 100
                        else 50 # Default for NIFTY and others
                        end

      # Get lot size from nearest future expiry derivative
      lot_size = @instrument.lot_size_from_derivatives

      @messages = [
        {
          role: 'system',
          content: system_prompt
        },
        {
          role: 'user',
          content: initial_analysis_prompt
        },
        {
          role: 'tool',
          tool_call_id: 'initial_ltp',
          name: 'get_current_ltp',
          content: JSON.pretty_generate(ltp_data)
        },
        {
          role: 'user',
          content: build_initial_context_message(symbol_name, ltp_value, strike_rounding, lot_size)
        }
      ]
    end

    def build_initial_context_message(symbol_name, ltp_value, strike_rounding, lot_size)
      message = "Current LTP for #{symbol_name}: ₹#{ltp_value.round(2)}. Use this exact price to calculate strikes. Round to nearest #{strike_rounding} for #{symbol_name}. DO NOT use strikes from other indices."

      if lot_size&.positive?
        message += " Lot size for #{symbol_name} options: #{lot_size} (1 lot = #{lot_size} shares). Use this for position sizing calculations."
      end

      message
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

        You have access to tools to fetch additional market data if needed. Use them when you need:
        - Current LTP (last traded price) - for strike calculation
        - Historical candle data - for deeper structure analysis
        - Technical indicators (RSI, MACD, ADX, Supertrend) - for confirmation
        - Option chain data - for strike selection with premiums

        CRITICAL: Always provide specific, actionable recommendations:
        - Use exact strike prices (e.g., "₹26,300" for NIFTY, "₹85,500" for SENSEX, "₹52,000" for BANKNIFTY)
        - ALWAYS use get_current_ltp tool FIRST to get the current price before calculating strikes
        - For NIFTY: Round strikes to nearest 50 (e.g., 26,300, 26,350, 26,400)
        - For SENSEX: Round strikes to nearest 100 (e.g., 85,500, 85,600, 85,700)
        - For BANKNIFTY: Round strikes to nearest 100 (e.g., 52,000, 52,100, 52,200)
        - NEVER guess strike prices - ALWAYS calculate from actual LTP
        - ALWAYS use get_option_chain tool to get ACTUAL premium prices (LTP), DELTA, THETA, and expiry date for selected strikes
        - NEVER use estimated or hallucinated premium values - ONLY use values from get_option_chain tool response
        - Stop Loss (SL) and Take Profit (TP1, TP2) MUST be based on premium percentages, NOT underlying prices
        - Always provide index spot levels (underlying index price) to watch for exit decisions
        - CRITICAL: Calculate percentages correctly - if entry is ₹100, 30% loss = ₹70 (NOT ₹30), 50% gain = ₹150 (NOT ₹50)
        - CRITICAL: NEVER mix strike prices with premium prices in calculations
          * Strike price (e.g., ₹25900) is the exercise price - DO NOT use this for premium calculations
          * Premium price (e.g., ₹100) is the option price - use this for SL/TP calculations
          * WRONG: "SL at ₹25900 - ₹70 = ₹25330" (mixing strike with premium)
          * CORRECT: "SL at premium ₹70 (30% loss from entry premium ₹100)"
        - Use DELTA to calculate underlying levels CORRECTLY:
          * Formula: Underlying move = Premium move / Delta
          * Example: If entry premium is ₹100, SL premium is ₹70 (₹30 loss), and Delta is 0.5:
            - Premium loss = ₹100 - ₹70 = ₹30
            - Underlying move needed = ₹30 / 0.5 = ₹60
            - SL underlying level = Current spot - ₹60
          * WRONG: "₹25876.85 + (₹150/0.70) = ₹26351.21" (incorrect formula)
          * CORRECT: "Premium gain = ₹150 - ₹100 = ₹50, Underlying move = ₹50 / 0.70 = ₹71.43, TP underlying = ₹25876.85 + ₹71.43 = ₹25948.28"
        - Consider THETA (time decay) and expiry date when setting targets
        - Intraday realistic expectations: TP 10-25% gain, SL 15-25% loss (NOT 50-100% for intraday)
        - Exit Strategy Format: "Entry premium: ₹X. SL at premium ₹Y (exit at index spot ₹ABC). TP1 at premium ₹W (exit at index spot ₹DEF). TP2 at premium ₹V (exit at index spot ₹GHI) - calculated using Delta"
        - Risk Management Format: "Position size: X lots. Risk per trade: ₹Y (premium loss × lot size × shares per lot). Maximum loss: ₹Z"
        - Never give vague recommendations - always be specific and actionable
      PROMPT
    end

    def initial_analysis_prompt
      symbol_name = @instrument.symbol_name || 'UNKNOWN'
      decision = @initial_data[:decision]
      trend_analysis = compute_trend_analysis

      <<~PROMPT
        Analyze the following SMC/AVRZ market structure data for #{symbol_name}:

        Trading Decision from SMC Engine: #{decision}

        **CRITICAL: PRICE TREND ANALYSIS (USE THIS FOR DIRECTION DECISION)**
        #{trend_analysis}

        Market Structure Analysis (Multi-Timeframe):

        #{JSON.pretty_generate(@initial_data[:timeframes])}

        Provide a complete trading action plan for options buyers:

        **MANDATORY SECTIONS:**

        0. **Trend Confirmation** (MANDATORY - DO THIS FIRST):
           - Look at the Price Trend Analysis above
           - Is the overall trend BULLISH or BEARISH?
           - Are there any gap downs/ups?
           - What is the multi-day price movement direction?
           - YOUR TRADE DIRECTION MUST ALIGN WITH THE ACTUAL PRICE TREND

        1. **Trade Decision** (MANDATORY):
           - State clearly: "BUY CE" or "BUY PE" or "AVOID TRADING"
           - **CRITICAL**: Your decision MUST match the actual price trend:
             * If trend is BEARISH (declining prices, lower lows) → **STRONGLY PREFER BUY PE** (bearish markets are profitable for PUT options - this is an OPPORTUNITY, not a reason to avoid!)
             * If trend is BULLISH (rising prices, higher highs) → **STRONGLY PREFER BUY CE** (bullish markets are profitable for CALL options)
             * If there was a gap down → BEARISH bias → **STRONGLY PREFER BUY PE** (gap downs create bearish momentum - perfect for PUT options)
             * If there was a gap up → BULLISH bias → **STRONGLY PREFER BUY CE** (gap ups create bullish momentum - perfect for CALL options)
           - **IMPORTANT**: SMC "no_trade" decision does NOT mean "avoid all trading" - it just means SMC doesn't have a clear signal. If the price trend is clear (bearish/bullish), you SHOULD recommend BUY PE/CE based on the trend.
           - **ONLY recommend AVOID if**: There are specific risk factors like extreme volatility, no clear structure, conflicting signals, or dangerous market conditions. Do NOT avoid just because the market is bearish or bullish - those are trading opportunities!
           - If AVOID: Explain the SPECIFIC risk factors that make trading dangerous (not just "bearish market" or "bullish market")
           - If BUY: Validate that your direction matches the price trend analysis above

        2. **Strike Selection** (MANDATORY if trading):
           - CRITICAL: You MUST use ONLY the strikes that are provided in the option chain data from get_option_chain tool
           - DO NOT calculate, invent, or guess strike prices - ONLY use strikes from the option chain tool response
           - If option chain data shows strikes ₹25,700, ₹25,750, ₹25,650, you MUST use one of these - DO NOT use ₹26,150 or any other value
           - If you have called get_option_chain tool, look at the "strike" field values in the "options" array - these are the ONLY valid strikes
           - If you have NOT called get_option_chain tool yet, you MUST call it FIRST before selecting strikes
           - After calling get_option_chain, extract the actual strike values from the tool response and use ONLY those
           - Label each strike (ATM, ATM+1, ATM-1, etc.) based on which strike is closest to the current LTP
           - Explain why these strikes were chosen based on SMC levels (order blocks, liquidity zones, structure)
           - NEVER invent strike prices that don't exist in the option chain data

        3. **Entry Strategy** (MANDATORY if trading):
           - CRITICAL: YOU MUST call get_option_chain tool BEFORE providing ANY premium values
           - DO NOT provide premium values (₹100, ₹150, ₹255, etc.) unless you have called get_option_chain tool
           - DO NOT estimate or guess premium prices - ONLY use actual LTP from get_option_chain tool response
           - HOW TO EXTRACT ENTRY PREMIUM:
             * After calling get_option_chain, look at the tool response JSON
             * Find the option object with your selected strike and option_type (e.g., strike: 25900, option_type: "CE")
             * Extract the "ltp" field value - THIS is your entry premium
             * Example: If tool response shows {"strike": 25900, "option_type": "CE", "ltp": 94.45}
               - Entry premium = ₹94.45 (write exactly: "Enter at premium ₹94.45")
               - DO NOT use ₹255, ₹100, or any other value
           - Format: "Enter at premium ₹X (actual LTP from option chain for strike ₹Y)"
           - Entry timing (immediate, wait for pullback, wait for confirmation)
           - How to enter (market order, limit order, specific premium price level)
           - If you haven't called get_option_chain yet, DO NOT provide entry strategy - call the tool first

        4. **Exit Strategy** (MANDATORY if trading):
           - CRITICAL: YOU MUST call get_option_chain tool FIRST to get actual premium, DELTA, and THETA values
           - DO NOT provide SL/TP values unless you have called get_option_chain tool and received actual data
           - YOU MUST use ACTUAL premium prices from get_option_chain tool - NEVER estimate, guess, or use placeholder values like ₹100 or ₹255
           - TERMINOLOGY: Always use "EXIT" or "exit the position" - NEVER use "sell options" (we only buy options, never write/sell them)
           - Stop Loss (SL): Provide premium level AND corresponding index spot level to watch
             * Format: "SL at premium ₹X (exit at index spot ₹Y)"
             * Calculate index spot level using DELTA from option chain
           - Take Profit: Use TP1, TP2 format for multiple targets
             * Format: "TP1 at premium ₹X (exit at index spot ₹Y)"
             * Format: "TP2 at premium ₹X (exit at index spot ₹Y)" (optional, for partial exits)
             * Always provide at least TP1, optionally TP2 for partial profit booking
           - Index Spot Levels to Watch: Provide key underlying index price levels to monitor
             * These are the NIFTY/SENSEX/BANKNIFTY spot prices to watch for exit decisions
             * Format: "Watch index spot ₹X for TP1", "Watch index spot ₹Y for SL"
             * Calculate using DELTA: Index level = Current spot ± (Premium move / Delta)
           - HOW TO EXTRACT VALUES FROM OPTION CHAIN TOOL RESPONSE:
             * The tool response is a JSON object with an "options" array
             * Find the option object where "strike" matches your selected strike AND "option_type" matches your direction ("CE" or "PE")
             * Extract these exact field values from that option object:
               - "ltp" field = Entry premium (e.g., if "ltp": 94.45, then entry premium is ₹94.45)
               - "delta" field = DELTA value for calculations (e.g., if "delta": 0.51093, use 0.51093, NOT 0.5)
               - "lot_size" field = Lot size for risk calculations (e.g., if "lot_size": 65, use 65, NOT 50)
             * Example: If tool response contains {"strike": 25900, "option_type": "CE", "ltp": 94.45, "delta": 0.51093, "lot_size": 65}
               - Entry premium MUST be ₹94.45 (NOT ₹255, NOT ₹100, NOT any estimate)
               - DELTA MUST be 0.51093 (NOT 0.5, NOT estimated)
               - Lot size MUST be 65 (NOT 50, NOT estimated)
           - If you provide premium values that don't match the "ltp" field from option chain, your analysis is INVALID
           - YOU MUST calculate SL/TP based on premium percentages, NOT underlying prices
           - CRITICAL: NEVER mix strike prices with premium prices:
             * Strike price (e.g., ₹25900) is the exercise price - separate from premium
             * Premium price (e.g., ₹100) is the option price - use this for all SL/TP calculations
             * WRONG: "Set stop-loss order at ₹25900 - ₹70 = ₹25330" (mixing strike with premium)
             * CORRECT: "Entry premium: ₹100. SL at premium ₹70 (exit at index spot ₹25,822). TP1 at premium ₹150 (exit at index spot ₹26,000). TP2 at premium ₹200 (exit at index spot ₹26,200)"
           - CRITICAL: Calculate percentages correctly:
             * If entry premium is ₹100 and you want 30% loss: SL = ₹100 × (1 - 0.30) = ₹70 (NOT ₹30)
             * If entry premium is ₹100 and you want 50% gain: TP = ₹100 × (1 + 0.50) = ₹150 (NOT ₹50)
             * Formula: SL = Entry × (1 - Loss%), TP = Entry × (1 + Gain%)
           - Use DELTA from option chain to calculate underlying levels CORRECTLY:
             * Delta tells you how much option price moves per ₹1 move in underlying
             * Formula: Underlying move = Premium move / Delta
             * CRITICAL ERRORS TO AVOID:
               - DO NOT divide SL premium by delta (e.g., "₹66.55 / 0.51093" is WRONG)
               - DO NOT divide TP premium by delta (e.g., "₹127.35 / 0.51093" is WRONG)
               - You MUST calculate premium move FIRST, then divide by delta
             * CRITICAL: Premium move = Target premium - Entry premium (NOT the other way)
             * CRITICAL: For SL, underlying moves DOWN (use MINUS). For TP, underlying moves UP (use PLUS)
             * Step-by-step calculation for SL:
               1. Calculate premium loss: Premium loss = Entry premium - SL premium
               2. Calculate underlying move: Underlying move = Premium loss / Delta
               3. Calculate underlying level: Underlying level = Current spot - Underlying move (MINUS for SL)
               * Example: Entry premium: ₹94.45, SL premium: ₹66.55, Delta: 0.51093, Current spot: ₹25876.85
                 - Premium loss = ₹94.45 - ₹66.55 = ₹27.90 (NOT ₹66.55)
                 - Underlying move = ₹27.90 / 0.51093 = ₹54.60 (NOT ₹66.55 / 0.51093)
                 - SL underlying level = ₹25876.85 - ₹54.60 = ₹25822.25 (MINUS, not PLUS)
               * WRONG: "Underlying move = ₹66.55 / 0.51093" (dividing SL premium by delta - incorrect!)
               * CORRECT: "Premium loss = ₹94.45 - ₹66.55 = ₹27.90, Underlying move = ₹27.90 / 0.51093 = ₹54.60"
             * Step-by-step calculation for TP:
               1. Calculate premium gain: Premium gain = TP premium - Entry premium
               2. Calculate underlying move: Underlying move = Premium gain / Delta
               3. Calculate underlying level: Underlying level = Current spot + Underlying move (PLUS for TP)
               * Example: Entry premium: ₹94.45, TP premium: ₹127.35, Delta: 0.51093, Current spot: ₹25876.85
                 - Premium gain = ₹127.35 - ₹94.45 = ₹32.90 (NOT ₹37.90, NOT ₹127.35)
                 - Underlying move = ₹32.90 / 0.51093 = ₹64.40 (NOT ₹127.35 / 0.51093, NOT ₹37.90 / 0.51093)
                 - TP underlying level = ₹25876.85 + ₹64.40 = ₹25941.25 (PLUS, not MINUS)
               * WRONG: "Underlying move = ₹127.35 / 0.51093" or "Underlying move = ₹37.90 / 0.51093" (wrong premium gain)
               * CORRECT: "Premium gain = ₹127.35 - ₹94.45 = ₹32.90, Underlying move = ₹32.90 / 0.51093 = ₹64.40"
           - Consider THETA (time decay) and expiry date:
             * For intraday: Use conservative targets (10-25% gain, 15-25% loss)
             * For weekly expiry: Adjust based on days remaining (more days = more time decay risk)
             * Near expiry (< 3 days): Use tighter targets (10-20% gain, 15-20% loss)
             * Far expiry (> 7 days): Can use wider targets (20-40% gain, 20-30% loss)
           - Take Profit Format (USE TP1, TP2 - SHOW FULL CALCULATION):
             * Format: "TP1 at premium ₹X (exit at index spot ₹ABC)" or "TP2 at premium ₹Y (exit at index spot ₹DEF)"
             * Always provide TP1 (mandatory), optionally TP2 for partial profit booking
             * Calculation format: "Premium gain = TP1 premium - Entry premium = ₹X - ₹Z = ₹W, Underlying move = Premium gain / Delta = ₹W / Delta = ₹V, TP1 index spot = Current spot + Underlying move = ₹ABC"
             * CRITICAL: Show Premium gain calculation FIRST, then divide by delta
             * CRITICAL: DO NOT write "Underlying move = TP premium / Delta" - that's WRONG
             * Example format: "TP1 at premium ₹127.35 (exit at index spot ₹25,941). Calculation: Premium gain = ₹127.35 - ₹94.45 = ₹32.90, Underlying move = ₹32.90 / 0.51093 = ₹64.40, TP1 index spot = ₹25876.85 + ₹64.40 = ₹25941.25"
             * Example with TP2: "TP2 at premium ₹150.00 (exit at index spot ₹26,000). Calculation: Premium gain = ₹150.00 - ₹94.45 = ₹55.55, Underlying move = ₹55.55 / 0.51093 = ₹108.80, TP2 index spot = ₹25876.85 + ₹108.80 = ₹25985.65"
             * Intraday realistic TP1: 10-25% premium gain, TP2: 25-40% premium gain (NOT 50-100% for intraday)
           - Stop Loss (SL) Format (SHOW FULL CALCULATION):
             * "SL at premium ₹X (exit at index spot ₹ABC)"
             * Calculation format: "Premium loss = Entry premium - SL premium = ₹Z - ₹X = ₹W, Underlying move = Premium loss / Delta = ₹W / Delta = ₹V, SL index spot = Current spot - Underlying move = ₹ABC"
             * CRITICAL: Show Premium loss calculation FIRST, then divide by delta
             * CRITICAL: DO NOT write "Underlying move = SL premium / Delta" or "Underlying move needed = SL premium / Delta" - that's WRONG
             * Example format: "SL at premium ₹66.55 (exit at index spot ₹25,822). Calculation: Premium loss = ₹94.45 - ₹66.55 = ₹27.90, Underlying move = ₹27.90 / 0.51093 = ₹54.60, SL index spot = ₹25876.85 - ₹54.60 = ₹25822.25"
             * Intraday realistic SL: 15-25% premium loss (NOT 30%+ for intraday)
           - NEVER use underlying prices directly for SL/TP1/TP2 (e.g., "SL at ₹84800" is WRONG - use premium prices, then calculate index spot levels)
           - NEVER calculate percentages incorrectly (e.g., "30% loss = ₹22.69 from ₹113.45" is WRONG - correct is ₹79.42)
           - Exit timing: When to exit (time-based, premium-based, or signal-based)

        5. **Risk Management** (MANDATORY if trading):
           - Position sizing: How much capital to allocate (consider lot size - 1 lot = X shares)
           - Risk per trade calculation (CRITICAL - use actual values from option chain):
             * Formula: Risk per trade = Premium loss per share × Lot size × Number of lots
             * Step-by-step:
               1. Calculate premium loss: Premium loss = Entry premium - SL premium
                  - This MUST match the premium loss you calculated for SL
                  - Example: If entry is ₹94.45 and SL is ₹66.55, then premium loss = ₹94.45 - ₹66.55 = ₹27.90
               2. Get lot size from option chain data (extract "lot_size" field, e.g., 65)
               3. Calculate: Risk = Premium loss × Lot size × Number of lots
             * Example using actual values: Entry premium ₹94.45, SL premium ₹66.55, lot size 65, 1 lot:
               - Premium loss = ₹94.45 - ₹66.55 = ₹27.90 (NOT ₹66.55, NOT any other value)
               - Risk per trade = ₹27.90 × 65 × 1 = ₹1,813.50 (NOT ₹6,098.55 or any other value)
             * Format: "Risk per trade: ₹X (premium loss ₹Y × lot size Z × N lots)"
             * CRITICAL: Premium loss MUST be Entry premium - SL premium. DO NOT use SL premium directly.
             * CRITICAL: Verify your calculation - if premium loss is ₹27.90 and lot size is 65, risk = ₹27.90 × 65 = ₹1,813.50
           - Maximum loss: State the maximum acceptable loss for this trade (should match risk per trade)
           - Position size recommendation:
             * Format: "Position size: N lots (X shares total)"
             * Use lot size from option chain data (extract "lot_size" field), NOT estimated values
             * Example: If lot_size is 65, use 65 (NOT 50, NOT estimated)
           - Time decay considerations: Expiry date impact on premium erosion
           - Risk-reward ratio: Calculate and state (e.g., "Risk-reward ratio: 1:2.5")
           - NEVER use vague statements like "risk per unit is ₹10" - always calculate total risk per trade
           - NEVER use wrong premium loss values - calculate it as Entry premium - SL premium

        6. **Market Structure Context** (Brief):
           - Overall trend and structure breaks
           - Key liquidity zones and order blocks
           - Premium/Discount position

        If you need additional data (current price, indicators, option chain), use the available tools.
        Focus on providing actionable, specific recommendations that a trader can execute immediately.
      PROMPT
    end

    def execute_conversation
      iteration = 0
      full_response = ''
      failed_tools = [] # Track failed tool calls to prevent infinite loops
      successful_tools = [] # Track successful tool calls to prevent duplicate calls
      consecutive_errors = 0 # Track consecutive errors
      duplicate_tool_calls = 0 # Circuit breaker: track duplicate tool calls
      cached_option_chain_data = nil # Pre-cache option chain data for final prompt

      while iteration < MAX_ITERATIONS
        Rails.logger.debug { "[Smc::AiAnalyzer] Iteration #{iteration + 1}/#{MAX_ITERATIONS}" }

        # Prepare tools for this request
        tools = build_tools_definition

        # Make chat request with tools
        begin
          response = @ai_client.chat(
            messages: limit_message_history(@messages),
            model: @model,
            temperature: 0.3,
            tools: tools,
            tool_choice: 'auto'
          )
        rescue StandardError => e
          Rails.logger.error("[Smc::AiAnalyzer] Chat API error: #{e.class} - #{e.message}")
          Rails.logger.debug { "[Smc::AiAnalyzer] Messages: #{@messages.inspect}" }
          Rails.logger.debug { "[Smc::AiAnalyzer] Tools: #{tools.inspect}" }
          raise
        end

        unless response
          Rails.logger.warn('[Smc::AiAnalyzer] No response from AI client')
          break
        end

        # Extract content and tool_calls from response
        # Response format depends on whether tools were used
        if response.is_a?(Hash)
          # When tools are used, response is a hash with content and tool_calls
          content = response[:content] || response['content']
          tool_calls = response[:tool_calls] || response['tool_calls']
        elsif response.is_a?(String)
          # When no tools, response is just content string
          content = response
          tool_calls = nil
        else
          # Try to extract from response object
          content = response.respond_to?(:content) ? response.content : response.to_s
          tool_calls = response.respond_to?(:tool_calls) ? response.tool_calls : nil
        end

        # Check if response contains tool calls (native format)
        if tool_calls&.any?
          tool_names = tool_calls.map do |tc|
            tc_hash = tc.is_a?(Hash) ? tc : tc.to_h
            func = tc_hash['function'] || tc_hash[:function] || {}
            func['name'] || func[:name] || 'unknown'
          end
          Rails.logger.debug { "[Smc::AiAnalyzer] Tool calls detected: #{tool_names.join(', ')}" }
          Rails.logger.debug { "[Smc::AiAnalyzer] Tool calls structure: #{tool_calls.inspect}" }

          # Circuit breaker: Force analysis if we've had too many consecutive errors, duplicate calls, or near max iterations
          circuit_breaker_triggered = consecutive_errors >= 3 ||
                                      duplicate_tool_calls >= MAX_DUPLICATE_TOOL_CALLS ||
                                      iteration >= MAX_ITERATIONS - 1
          if circuit_breaker_triggered
            Rails.logger.warn("[Smc::AiAnalyzer] Circuit breaker triggered: consecutive_errors=#{consecutive_errors}, duplicate_calls=#{duplicate_tool_calls}, iteration=#{iteration}. Forcing final analysis.")

            # Build comprehensive final prompt with all available data pre-injected
            final_prompt = build_forced_analysis_prompt(cached_option_chain_data)

            @messages << {
              role: 'user',
              content: final_prompt
            }
            # Make one final request without tools
            final_response = @ai_client.chat(
              messages: limit_message_history(@messages),
              model: @model,
              temperature: 0.3
            )
            full_response = if final_response.is_a?(Hash)
                              final_response[:content] || final_response['content'] || ''
                            else
                              final_response.to_s
                            end
            break
          end

          # Add assistant message with tool calls
          # Format tool calls exactly as they came from the API (preserve structure)
          formatted_tool_calls = tool_calls.map do |tc|
            tc_hash = tc.is_a?(Hash) ? tc : tc.to_h
            func = tc_hash['function'] || tc_hash[:function] || {}
            func_name = func['name'] || func[:name]
            func_args = func['arguments'] || func[:arguments]

            # Handle arguments - preserve as-is if string, convert if hash
            # OpenAI/Ollama expects arguments as JSON string
            args_string = if func_args.is_a?(String)
                            # Already JSON string - validate it's valid JSON
                            begin
                              JSON.parse(func_args) # Validate it's valid JSON
                              func_args # Return as-is if valid
                            rescue JSON::ParserError => e
                              Rails.logger.warn("[Smc::AiAnalyzer] Invalid JSON in tool arguments: #{e.message}, using empty object")
                              '{}'
                            end
                          elsif func_args.is_a?(Hash)
                            func_args.to_json # Convert hash to JSON string
                          elsif func_args.nil?
                            '{}' # Default to empty object
                          else
                            Rails.logger.warn("[Smc::AiAnalyzer] Unexpected argument type: #{func_args.class}, using empty object")
                            '{}'
                          end

            {
              id: tc_hash['id'] || tc_hash[:id] || SecureRandom.hex(8),
              type: 'function',
              function: {
                name: func_name,
                arguments: args_string
              }
            }
          end

          @messages << {
            role: 'assistant',
            content: content,
            tool_calls: formatted_tool_calls
          }

          # Execute tools and add results
          tool_calls.each_with_index do |tool_call, index|
            tc_hash = tool_call.is_a?(Hash) ? tool_call : tool_call.to_h
            func = tc_hash['function'] || tc_hash[:function] || {}
            tool_name = func['name'] || func[:name]
            tool_args_raw = func['arguments'] || func[:arguments]

            # Parse arguments safely
            tool_args = begin
              if tool_args_raw.is_a?(String)
                JSON.parse(tool_args_raw)
              elsif tool_args_raw.is_a?(Hash)
                tool_args_raw
              else
                {}
              end
            rescue JSON::ParserError => e
              Rails.logger.warn("[Smc::AiAnalyzer] Failed to parse tool arguments: #{e.message}")
              {}
            end

            Rails.logger.debug { "[Smc::AiAnalyzer] Executing tool: #{tool_name} with args: #{tool_args.inspect}" }

            # Normalize tool args for comparison (convert empty strings to nil for expiry_date)
            normalized_tool_args = normalize_tool_args_for_comparison(tool_name, tool_args)
            tool_key = "#{tool_name}:#{normalized_tool_args.to_json}"

            # Check if this tool has failed before
            if failed_tools.include?(tool_key)
              Rails.logger.warn("[Smc::AiAnalyzer] Skipping previously failed tool: #{tool_name}")
              tool_result = { error: 'This tool failed previously. Skipping to avoid infinite loop.' }
              consecutive_errors += 1
            # Check if this tool was already called successfully with same parameters
            elsif successful_tools.include?(tool_key)
              duplicate_tool_calls += 1
              Rails.logger.warn("[Smc::AiAnalyzer] Tool #{tool_name} already called successfully with same parameters. Skipping duplicate call. (duplicate count: #{duplicate_tool_calls}/#{MAX_DUPLICATE_TOOL_CALLS})")
              # Return a message indicating data already available
              tool_result = case tool_name
                            when 'get_option_chain'
                              { error: 'Option chain data already retrieved in a previous tool call. ' \
                                       'Use the data from that response.' }
                            when 'get_current_ltp'
                              { error: 'LTP data already retrieved in a previous tool call. ' \
                                       'Use the data from that response.' }
                            when 'get_technical_indicators'
                              { error: 'Technical indicators already retrieved in a previous tool call. ' \
                                       'Use the data from that response.' }
                            when 'get_historical_candles'
                              { error: 'Historical candles already retrieved in a previous tool call. ' \
                                       'Use the data from that response.' }
                            else
                              { error: 'This tool was already called successfully. ' \
                                       'Use the data from the previous response.' }
                            end
              # Don't increment consecutive_errors for duplicate calls - this is expected behavior
              # The AI should use the data from the previous call, not keep trying
            else
              tool_result = execute_tool(tool_name, tool_args)

              # Track failed tools - check for errors OR null/empty results
              if tool_result.is_a?(Hash)
                has_error = tool_result[:error].present?
                # For get_technical_indicators, check if all values are null
                is_empty_result = tool_name == 'get_technical_indicators' &&
                                  tool_result[:rsi].nil? &&
                                  tool_result[:macd].nil? &&
                                  tool_result[:adx].nil? &&
                                  tool_result[:supertrend].nil? &&
                                  tool_result[:atr].nil? &&
                                  !tool_result[:error]
                # For get_option_chain, check if options array is empty
                is_empty_option_chain = tool_name == 'get_option_chain' &&
                                        tool_result[:options].is_a?(Array) &&
                                        tool_result[:options].empty? &&
                                        !tool_result[:error]

                if has_error
                  failed_tools << tool_key
                  consecutive_errors += 1
                elsif is_empty_result || is_empty_option_chain
                  # Empty results - mark as "called" to prevent duplicate calls, but don't treat as error
                  # This prevents the AI from calling the same tool repeatedly when no data is available
                  successful_tools << tool_key
                  Rails.logger.warn("[Smc::AiAnalyzer] Tool returned empty/null results: #{tool_name}. Marked as called to prevent duplicate calls.")
                  # Don't increment consecutive_errors for empty results - they're not errors, just no data
                  # Reset error counter since this is a valid (though empty) response
                  consecutive_errors = 0
                else
                  # Tool succeeded with data - mark as successful and reset error counter
                  successful_tools << tool_key
                  consecutive_errors = 0 # Reset on success
                  Rails.logger.debug { "[Smc::AiAnalyzer] Tool #{tool_name} succeeded, added to successful_tools" }

                  # Cache option chain data for later use in forced final prompt
                  if tool_name == 'get_option_chain' && tool_result.is_a?(Hash) && tool_result[:options]&.any?
                    cached_option_chain_data = tool_result
                    Rails.logger.info("[Smc::AiAnalyzer] Cached option chain data with #{tool_result[:options].size} options")
                  end
                end
              else
                # Non-hash result (shouldn't happen, but treat as success)
                successful_tools << tool_key
                consecutive_errors = 0 # Reset on success
              end
            end

            # Get the tool_call_id from the formatted tool call (use index to match)
            # This ensures we use the same ID that was added to the assistant message
            formatted_tc = formatted_tool_calls[index]
            tool_call_id = formatted_tc ? formatted_tc[:id] : (tc_hash['id'] || tc_hash[:id] || SecureRandom.hex(8))

            # Format tool result - must be a string (JSON or plain text)
            tool_content = if tool_result.is_a?(Hash) || tool_result.is_a?(Array)
                             JSON.pretty_generate(tool_result)
                           else
                             tool_result.to_s
                           end

            @messages << {
              role: 'tool',
              tool_call_id: tool_call_id,
              name: tool_name,
              content: tool_content
            }
          end

          # Check if AI has called get_option_chain successfully - verify actual data exists
          has_option_chain = @messages.any? do |m|
            next false unless m[:role] == 'tool' && m[:name] == 'get_option_chain'

            # Verify the tool result actually contains option chain data (not just an error)
            content = m[:content].to_s
            content.include?('"index"') && content.exclude?('"error"')
          end

          # Check if AI has called get_current_ltp successfully
          has_ltp = @messages.any? do |m|
            next false unless m[:role] == 'tool' && m[:name] == 'get_current_ltp'

            # Verify the tool result actually contains LTP data (not just an error)
            content = m[:content].to_s
            content.include?('"ltp"') && content.exclude?('"error"')
          end

          # Check if get_technical_indicators returned empty results
          has_empty_technical_indicators = @messages.any? do |m|
            next false unless m[:role] == 'tool' && m[:name] == 'get_technical_indicators'

            # Check if the result indicates empty/null values
            content = m[:content].to_s
            content.include?('"rsi":null') && content.include?('"macd":null') && content.exclude?('"error"')
          end

          # Add user message prompting for analysis
          # If we've had errors, empty results, or duplicate tool calls, be more directive to prevent loops
          force_stop = consecutive_errors >= 3 ||
                       duplicate_tool_calls >= MAX_DUPLICATE_TOOL_CALLS ||
                       iteration >= MAX_ITERATIONS - 2
          user_prompt = if force_stop
                          # Force stop - near max iterations or too many errors
                          ltp_info = @messages.find { |m| m[:role] == 'tool' && m[:content]&.include?('"ltp"') }
                          ltp_value = if ltp_info
                                        ltp_match = ltp_info[:content].match(/"ltp":\s*([\d.]+)/)
                                        ltp_match ? ltp_match[1] : nil
                                      end
                          symbol_name = @instrument.symbol_name.to_s.upcase
                          strike_rounding = case symbol_name
                                            when 'SENSEX', 'BANKNIFTY' then 100
                                            else 50
                                            end
                          if ltp_value
                            'STOP CALLING TOOLS IMMEDIATELY. You have reached maximum iterations or ' \
                              'encountered multiple errors. Provide your analysis NOW. You have SMC data ' \
                              "and LTP (₹#{ltp_value}) for #{symbol_name}. " \
                              'CRITICAL: Check the Price Trend Analysis - if trend is BEARISH (declining ' \
                              'prices), STRONGLY RECOMMEND BUY PE (bearish markets are profitable for PUT ' \
                              'options - this is an OPPORTUNITY!). Only recommend AVOID if there are ' \
                              'specific risk factors. Your direction MUST match the actual price trend. ' \
                              "Calculate strikes from LTP (round to nearest #{strike_rounding}). Provide " \
                              'complete trading recommendation: 1) Trade Decision (MUST match price trend - ' \
                              'prefer BUY PE in bearish, BUY CE in bullish), 2) Strike Selection, ' \
                              '3) Entry Strategy, 4) Exit Strategy (SL, TP1, optionally TP2 with index spot levels), ' \
                              '5) Risk Management. DO NOT call any more tools.'
                          else
                            'STOP CALLING TOOLS IMMEDIATELY. Provide your analysis NOW based on the SMC ' \
                              'data you have. CRITICAL: Your trade direction MUST match the Price Trend ' \
                              'Analysis. If price is declining (bearish), STRONGLY RECOMMEND BUY PE (this ' \
                              'is a trading opportunity, not a reason to avoid). Only recommend AVOID if ' \
                              'there are specific risk factors. DO NOT call any more tools.'
                          end
                        elsif consecutive_errors >= 2
                          'STOP CALLING TOOLS. You have encountered multiple tool errors. Provide your ' \
                            'analysis NOW based on the SMC market structure data and any successful tool ' \
                            'results you have. CRITICAL: Check Price Trend Analysis - if price is ' \
                            'declining (bearish), STRONGLY RECOMMEND BUY PE (bearish markets are ' \
                            'profitable for PUT options). Only recommend AVOID if there are specific ' \
                            'risk factors. Calculate strikes from LTP if available. DO NOT call more tools.'
                        elsif has_empty_technical_indicators && iteration >= 3
                          # Technical indicators returned empty - tell AI to stop trying
                          'CRITICAL: The get_technical_indicators tool has already been called and returned empty/null results (no data available). DO NOT call get_technical_indicators again - it will return the same empty results. You have option chain data and LTP which is sufficient for your analysis. Provide your complete trading recommendation NOW using the data you have. DO NOT call get_technical_indicators or any other tools again.'
                        elsif has_option_chain && has_ltp && iteration >= 2
                          # AI has option chain and LTP - should have enough data after 2+ iterations
                          # Extract actual values from option chain to reference in prompt
                          option_chain_msg = @messages.find do |m|
                            m[:role] == 'tool' && m[:name] == 'get_option_chain' && m[:content]&.include?('"index"')
                          end
                          actual_premium = nil
                          actual_delta = nil
                          actual_lot_size = nil
                          available_strikes = []
                          if option_chain_msg
                            content = option_chain_msg[:content].to_s
                            # Extract all available strikes from the option chain
                            content.scan(/"strike":\s*(\d+)/) do |strike|
                              available_strikes << strike[0].to_i unless available_strikes.include?(strike[0].to_i)
                            end
                            available_strikes.sort!
                            # Try to extract 25900 CE values (most common ATM strike)
                            strike_pattern = /"strike":\s*25900[^}]*"option_type":\s*"CE"[^}]*"ltp":\s*([\d.]+)[^}]*"delta":\s*([\d.]+)/m
                            if (match = content.match(strike_pattern))
                              actual_premium = match[1]
                              actual_delta = match[2]
                            end
                            # Extract lot_size
                            if (lot_match = content.match(/"lot_size":\s*(\d+)/))
                              actual_lot_size = lot_match[1]
                            end
                          end

                          strikes_warning = if available_strikes.any?
                                              strike_list = available_strikes.map { |s| "₹#{s}" }.join(', ')
                                              "CRITICAL: Available strikes in option chain: #{strike_list}. " \
                                                'You MUST use ONLY one of these strikes. DO NOT invent or ' \
                                                'calculate other strikes like ₹26,150 or any value not ' \
                                                'in this list.'
                                            else
                                              'CRITICAL: Look at the get_option_chain tool response and ' \
                                                "extract ALL strike values from the 'strike' fields. " \
                                                'You MUST use ONLY strikes that appear in that data.'
                                            end

                          reference_text = if actual_premium && actual_delta && actual_lot_size
                                             'REFERENCE: In the option chain tool response you received, ' \
                                               "the 25900 CE option has premium (ltp) of ₹#{actual_premium}, " \
                                               "delta of #{actual_delta}, and lot_size is #{actual_lot_size}. " \
                                               'YOU MUST use these exact values in your analysis. DO NOT use ' \
                                               '₹255, ₹100, ₹413.95, or any other estimated values.'
                                           else
                                             'Look at the get_option_chain tool response you received. ' \
                                               "Find the option with strike 25900 and option_type 'CE'. " \
                                               "Extract the 'ltp' field value and use it as your entry " \
                                               "premium. Extract the 'delta' field value and use it for " \
                                               "calculations. Extract the 'lot_size' field value and use " \
                                               'it for risk calculations.'
                                           end

                          'CRITICAL: You have already received option chain data AND LTP data in previous ' \
                            'tool responses. DO NOT call get_option_chain or get_current_ltp again. ' \
                            "You have ALL the data you need. #{strikes_warning} #{reference_text} " \
                            'IMPORTANT: Check the Price Trend Analysis - if trend is BEARISH, STRONGLY ' \
                            'RECOMMEND BUY PE (bearish markets are profitable for PUT options - this is ' \
                            'an OPPORTUNITY!). If trend is BULLISH, STRONGLY RECOMMEND BUY CE. Only ' \
                            'recommend AVOID if there are specific risk factors. Provide your complete ' \
                            'trading recommendation NOW with: 1) Trade Decision (MUST match price trend - ' \
                            'prefer BUY PE in bearish, BUY CE in bullish), 2) Strike Selection (MUST ' \
                            'be one of the strikes from the option chain data - DO NOT invent strikes), ' \
                            '3) Entry Strategy (use the ACTUAL premium ltp value from option chain for ' \
                            'your selected strike - NOT ₹255, ₹413.95, or any estimate), 4) Exit Strategy ' \
                            '(SL, TP1, optionally TP2 with index spot levels - based on ACTUAL premium ' \
                            'percentages using the actual premium value from option chain - include DELTA ' \
                            'calculations using the actual delta value from option chain), 5) Risk Management ' \
                            '(calculate using actual premium values and actual lot_size from option chain). ' \
                            'DO NOT call any more tools - provide your analysis immediately.'
                        elsif has_option_chain && iteration >= 2
                          # Has option chain but still calling tools - force analysis earlier
                          'CRITICAL: You have already received option chain data in a previous tool ' \
                            'response. DO NOT call get_option_chain again - you already have this data. ' \
                            'Provide your complete trading recommendation NOW using the ACTUAL premium ' \
                            'values, DELTA, and THETA from the option chain data you already have. ' \
                            'DO NOT estimate or use placeholder values - use the ACTUAL data from the ' \
                            'tool response. DO NOT call any more tools.'
                        elsif consecutive_errors.positive?
                          'You have encountered some tool errors. Please provide your analysis now based ' \
                            'on the SMC data and any successful tool results. Do not call more tools - ' \
                            'provide your complete trading recommendation.'
                        elsif iteration >= 3
                          # After 3 iterations, be more directive
                          'You have made multiple tool calls. Check your previous tool responses - if you ' \
                            'have option chain data and LTP, you have enough information. Provide your ' \
                            'complete trading recommendation NOW. DO NOT call the same tools again - use ' \
                            'the data you already have.'
                        else
                          'Based on the tool results, continue your analysis. IMPORTANT: Before calling ' \
                            'any tool, check if you already have that data from a previous tool response. ' \
                            'If you have option chain data and LTP, you have enough information - provide ' \
                            'your complete analysis now. Only call additional tools if you are missing ' \
                            'critical data that you do not already have.'
                        end

          @messages << {
            role: 'user',
            content: user_prompt
          }

          iteration += 1
          next
        end

        # No tool calls - final response
        full_response = content || response.to_s
        Rails.logger.info('[Smc::AiAnalyzer] Final analysis received')
        break
      end

      Rails.logger.warn("[Smc::AiAnalyzer] Reached max iterations (#{MAX_ITERATIONS})") if iteration >= MAX_ITERATIONS

      full_response.presence
    end

    def execute_conversation_stream(&)
      iteration = 0
      full_response = +''

      while iteration < MAX_ITERATIONS
        Rails.logger.debug { "[Smc::AiAnalyzer] Stream iteration #{iteration + 1}/#{MAX_ITERATIONS}" }

        tools = build_tools_definition

        # Stream response
        stream_response = nil
        @ai_client.chat_stream(
          messages: limit_message_history(@messages),
          model: @model,
          temperature: 0.3,
          tools: tools,
          tool_choice: 'auto'
        ) do |chunk|
          stream_response ||= +''
          stream_response << chunk if chunk.present?
          yield(chunk) if block_given?
        end

        unless stream_response
          Rails.logger.warn('[Smc::AiAnalyzer] No stream response')
          break
        end

        # Check for tool calls in streamed response
        tool_calls = extract_tool_calls_from_text(stream_response)
        if tool_calls&.any?
          Rails.logger.info { "[Smc::AiAnalyzer] Tool calls detected in stream: #{tool_calls.map { |tc| tc['tool'] || tc[:tool] }.join(', ')}" }

          # Remove tool call JSON from the response text (clean it up)
          cleaned_response = stream_response.dup
          tool_calls.each do |tc|
            # Remove the tool call JSON from text
            tool_json = tc.is_a?(Hash) ? tc.to_json : tc.to_s
            cleaned_response.gsub!(tool_json, '')
            cleaned_response.gsub!(/\{"name"\s*:\s*"[^"]+"\s*,\s*"parameters"\s*:\s*\{[^}]+\}\s*\}/, '')
          end
          cleaned_response.strip!

          # Add assistant message (with cleaned content)
          assistant_content = cleaned_response.strip.presence ||
                              'I will fetch additional data to complete the analysis.'
          @messages << {
            role: 'assistant',
            content: assistant_content
          }

          # Execute tools
          tool_calls.each do |tool_call|
            tool_name = tool_call['tool'] || tool_call[:tool] || tool_call['name'] || tool_call[:name]
            tool_args = tool_call['arguments'] || tool_call[:arguments] ||
                        tool_call['parameters'] || tool_call[:parameters] || {}

            Rails.logger.info { "[Smc::AiAnalyzer] Executing tool: #{tool_name} with args: #{tool_args.inspect}" }

            tool_result = execute_tool(tool_name, tool_args)

            @messages << {
              role: 'tool',
              name: tool_name,
              content: JSON.pretty_generate(tool_result)
            }
          end

          @messages << {
            role: 'user',
            content: 'Based on the tool results above, continue your analysis. ' \
                     'Provide a complete analysis with actionable insights for options trading.'
          }

          iteration += 1
          next
        end

        # Final response
        full_response = stream_response
        break
      end

      full_response.presence
    end

    def build_tools_definition
      [
        {
          type: 'function',
          function: {
            name: 'get_current_ltp',
            description: 'Get the current Last Traded Price (LTP) for the instrument',
            parameters: {
              type: 'object',
              properties: {},
              required: []
            }
          }
        },
        {
          type: 'function',
          function: {
            name: 'get_historical_candles',
            description: 'Get historical candle data for the instrument',
            parameters: {
              type: 'object',
              properties: {
                interval: {
                  type: 'string',
                  enum: %w[5m 15m 1h daily],
                  description: 'Timeframe for candles'
                },
                limit: {
                  type: 'integer',
                  description: 'Number of candles to fetch (default: 50, max: 200)',
                  default: 50
                }
              },
              required: ['interval']
            }
          }
        },
        {
          type: 'function',
          function: {
            name: 'get_technical_indicators',
            description: 'Get technical indicators (RSI, MACD, ADX, Supertrend, ATR) for the instrument',
            parameters: {
              type: 'object',
              properties: {
                timeframe: {
                  type: 'string',
                  enum: %w[5m 15m 1h daily],
                  description: 'Timeframe for indicators'
                }
              },
              required: ['timeframe']
            }
          }
        },
        {
          type: 'function',
          function: {
            name: 'get_option_chain',
            description: 'Get option chain data for the index (if applicable). CRITICAL: You MUST call this tool BEFORE providing ANY premium values, entry strategy, or exit strategy. This tool returns ACTUAL premium prices (LTP), DELTA, THETA, and expiry date for all strikes. DO NOT estimate or guess premium values like ₹100 - you MUST call this tool to get real data. Do NOT call this tool if you have already received option chain data in a previous tool response. If you need option chain data, call this tool ONCE and use the ACTUAL data from that response. Do NOT provide expiry_date parameter unless you are certain of a valid expiry date from previous tool results. If unsure, omit the expiry_date parameter completely (do not pass empty string) and the system will automatically select the nearest available expiry date.',
            parameters: {
              type: 'object',
              properties: {
                expiry_date: {
                  type: 'string',
                  description: 'Expiry date in YYYY-MM-DD format. CRITICAL: Only provide this if you ' \
                               'know the exact valid expiry date from previous tool results. DO NOT ' \
                               'guess or calculate expiry dates. If unsure, OMIT this parameter ' \
                               'completely (do not pass empty string ""). The system will automatically ' \
                               'use the nearest available expiry date. Indian index options expire on ' \
                               'specific Thursdays, not arbitrary dates.'
                }
              },
              required: []
            }
          }
        }
      ]
    end

    def extract_tool_calls_from_response(_response)
      # This method is no longer needed - tool_calls are extracted in execute_conversation
      # Keeping for backward compatibility
      nil
    end

    def extract_tool_calls_from_text(text)
      # Extract tool calls from text - handle multiple formats
      tool_calls = []
      seen_tools = []

      # Pattern 1: {"name": "tool_name", "parameters": {...}} (Ollama format)
      # Handle both single-line and multi-line JSON
      # Use a more lenient pattern that matches the actual format
      text.scan(/\{"name"\s*:\s*"([^"]+)"\s*,\s*"parameters"\s*:\s*(\{[^}]*\})\s*\}/) do |name, params_str|
        next if seen_tools.include?(name) # Avoid duplicates

        begin
          # Try to parse parameters - handle nested objects
          parsed_params = JSON.parse(params_str)
          tool_calls << {
            'tool' => name,
            'arguments' => parsed_params
          }
          seen_tools << name unless seen_tools.include?(name)
          Rails.logger.info { "[Smc::AiAnalyzer] Extracted tool call: #{name} with params: #{parsed_params.inspect}" }
        rescue JSON::ParserError => e
          Rails.logger.debug { "[Smc::AiAnalyzer] Failed to parse tool call params for #{name}: #{e.message}, params: #{params[0..100]}" }
        end
      end

      # Also try to find complete JSON objects that might be tool calls (more lenient)
      # Look for patterns like: {"name": "...", "parameters": {...}}
      text.scan(/\{[^}]*"name"\s*:\s*"([^"]+)"[^}]*"parameters"\s*:\s*(\{[^}]*\})[^}]*\}/) do |name, _params_str|
        next if seen_tools.include?(name) # Avoid duplicates

        begin
          # Try to parse the full JSON object
          full_match = text.match(/\{"name"\s*:\s*"#{Regexp.escape(name)}"\s*,\s*"parameters"\s*:\s*(\{[^}]*\})\s*\}/)
          if full_match
            parsed_params = JSON.parse(full_match[1])
            tool_calls << {
              'tool' => name,
              'arguments' => parsed_params
            }
            seen_tools << name unless seen_tools.include?(name)
            Rails.logger.info { "[Smc::AiAnalyzer] Extracted tool call (lenient): #{name}" }
          end
        rescue JSON::ParserError, NoMethodError
          # Skip if can't parse
        end
      end

      # Pattern 2: {"tool": "tool_name", "arguments": {...}} (alternative format)
      text.scan(/\{"tool"\s*:\s*"([^"]+)"\s*,\s*"arguments"\s*:\s*(\{[^}]*\})\s*\}/m) do |tool, args|
        next if seen_tools.include?(tool) # Avoid duplicates

        begin
          parsed_args = JSON.parse(args)
          tool_calls << {
            'tool' => tool,
            'arguments' => parsed_args
          }
          seen_tools << tool unless seen_tools.include?(tool)
          Rails.logger.debug { "[Smc::AiAnalyzer] Extracted tool call: #{tool} with args: #{parsed_args.inspect}" }
        rescue JSON::ParserError => e
          Rails.logger.debug { "[Smc::AiAnalyzer] Failed to parse tool call args for #{tool}: #{e.message}" }
        end
      end

      # Pattern 3: Try to find complete JSON objects (more lenient parsing)
      # Look for standalone JSON objects that might be tool calls
      pattern = /\{["']name["']\s*:\s*["']([^"']+)["']\s*,\s*["']parameters["']\s*:\s*(\{[^}]*(?:\{[^}]*\}[^}]*)*\})\s*\}/m
      text.scan(pattern) do |name, params_str|
        next if seen_tools.include?(name) # Avoid duplicates

        begin
          parsed_params = JSON.parse(params_str)
          tool_calls << {
            'tool' => name,
            'arguments' => parsed_params
          }
          seen_tools << name unless seen_tools.include?(name)
        rescue JSON::ParserError
          # Skip if can't parse
        end
      end

      # Pattern 4: Multiple tool calls in array format [{"name": "...", "parameters": {...}}, ...]
      array_match = text.match(/\[\s*(\{"name"\s*:\s*"[^"]+"\s*,\s*"parameters"\s*:\s*\{[^}]*\}\s*\},?\s*)+\s*\]/m)
      if array_match
        begin
          parsed = JSON.parse(array_match[0])
          parsed.each do |tc|
            tool_name = tc['name'] || tc['tool']
            next if seen_tools.include?(tool_name) # Avoid duplicates

            tool_calls << {
              'tool' => tool_name,
              'arguments' => tc['parameters'] || tc['arguments'] || {}
            }
            seen_tools << tool_name unless seen_tools.include?(tool_name)
          end
        rescue JSON::ParserError => e
          Rails.logger.debug { "[Smc::AiAnalyzer] Failed to parse tool call array: #{e.message}" }
        end
      end

      return unless tool_calls.any?

      Rails.logger.info { "[Smc::AiAnalyzer] Extracted #{tool_calls.size} tool call(s) from text" }
      tool_calls
    end

    # Normalize tool arguments for comparison (to detect duplicate calls)
    # Converts empty strings to nil for optional parameters like expiry_date
    def normalize_tool_args_for_comparison(tool_name, arguments)
      args = arguments.is_a?(Hash) ? arguments.dup : {}
      normalized = {}
      args.each do |k, v|
        key = k.to_s
        # For get_option_chain, normalize empty expiry_date string to nil
        normalized[key] = if tool_name == 'get_option_chain' && key == 'expiry_date'
                            v.is_a?(String) && v.strip.empty? ? nil : v
                          else
                            v
                          end
      end
      normalized
    end

    def execute_tool(tool_name, arguments)
      # Normalize arguments (handle both string keys and symbol keys)
      args = arguments.is_a?(Hash) ? arguments : {}
      normalized_args = {}
      args.each { |k, v| normalized_args[k.to_s] = v }

      case tool_name.to_s
      when 'get_current_ltp'
        # Ignore any parameters passed (tool takes no parameters)
        current_ltp
      when 'get_historical_candles'
        interval = normalized_args['interval']
        return { error: 'interval parameter is required for get_historical_candles' } unless interval

        get_historical_candles(
          interval: interval,
          limit: (normalized_args['limit'] || 50).to_i
        )
      when 'get_technical_indicators'
        timeframe = normalized_args['timeframe']
        return { error: 'timeframe parameter is required for get_technical_indicators' } unless timeframe

        get_technical_indicators(
          timeframe: timeframe
        )
      when 'get_option_chain'
        # expiry_date is optional - normalize empty string to nil
        expiry_date = normalized_args['expiry_date']
        expiry_date = nil if expiry_date.is_a?(String) && expiry_date.strip.empty?
        get_option_chain(
          expiry_date: expiry_date
        )
      else
        { error: "Unknown tool: #{tool_name}. Available tools: get_current_ltp, get_historical_candles, get_technical_indicators, get_option_chain" }
      end
    rescue StandardError => e
      Rails.logger.error("[Smc::AiAnalyzer] Tool error (#{tool_name}): #{e.class} - #{e.message}")
      Rails.logger.debug { e.backtrace.first(3).join("\n") }
      { error: "#{e.class}: #{e.message}" }
    end

    def current_ltp
      ltp = @instrument.ltp || @instrument.latest_ltp
      { ltp: ltp.to_f, symbol: @instrument.symbol_name }
    end

    # Compute actual price trend analysis from OHLC data
    # This helps AI make correct direction decisions
    def compute_trend_analysis
      series = @instrument.candles(interval: '5')
      candles = series&.candles || []

      return 'Insufficient candle data for trend analysis' if candles.size < 10

      # Get last 3 days of data (approx 75 candles per day)
      recent_candles = candles.last(225) # ~3 days

      # Find daily high/low/close for each day
      daily_data = group_candles_by_day(recent_candles)

      # Calculate trend metrics
      current_price = candles.last.close
      first_price = recent_candles.first.close
      price_change = current_price - first_price
      price_change_pct = (price_change / first_price * 100).round(2)

      # Detect gaps (significant open vs previous close)
      gap_analysis = detect_gaps(recent_candles)

      # Determine trend direction
      trend_direction = if price_change_pct < -0.5
                          'BEARISH'
                        elsif price_change_pct > 0.5
                          'BULLISH'
                        else
                          'SIDEWAYS'
                        end

      # Check for lower lows / higher highs pattern
      pattern = detect_swing_pattern(daily_data)

      # Build analysis string
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
          # Check for significant gap (> 0.3% of price)
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
        recent_gaps = gaps.last(3) # Show last 3 gaps
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

      dates = daily_data.keys.sort.last(3) # Last 3 days
      dates.map do |date|
        d = daily_data[date]
        "- #{date}: Open ₹#{d[:open].round(2)}, High ₹#{d[:high].round(2)}, Low ₹#{d[:low].round(2)}, Close ₹#{d[:close].round(2)}"
      end.join("\n")
    end

    def direction_recommendation(trend, gap_analysis, pattern)
      bearish_signals = 0
      bullish_signals = 0

      # Count trend signals
      bearish_signals += 2 if trend == 'BEARISH'
      bullish_signals += 2 if trend == 'BULLISH'

      # Count gap signals
      bearish_signals += 2 if gap_analysis.include?('GAP DOWN')
      bullish_signals += 2 if gap_analysis.include?('GAP UP')

      # Count pattern signals
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

    def get_historical_candles(interval:, limit:)
      series = @instrument.candles(interval: interval)
      candles = series&.candles&.last([limit, 200].min) || []

      {
        interval: interval,
        count: candles.size,
        candles: candles.map do |c|
          {
            timestamp: c.timestamp,
            open: c.open,
            high: c.high,
            low: c.low,
            close: c.close,
            volume: c.volume
          }
        end
      }
    rescue StandardError => e
      { error: "Failed to fetch candles: #{e.message}" }
    end

    def get_technical_indicators(timeframe:)
      # Convert timeframe string (e.g., "15m") to integer minutes for IndexTechnicalAnalyzer
      timeframe_minutes = case timeframe.to_s
                          when '5m' then 5
                          when '15m' then 15
                          when '1h' then 60
                          when 'daily' then 1440
                          else
                            timeframe.to_s.delete('m').to_i
                          end

      # Use IndexTechnicalAnalyzer to get proper indicator values
      begin
        # Get symbol name and normalize to symbol (e.g., "SENSEX" -> :sensex)
        symbol_name = @instrument.symbol_name.to_s.upcase
        index_symbol = case symbol_name
                       when 'NIFTY' then :nifty
                       when 'SENSEX' then :sensex
                       when 'BANKNIFTY' then :banknifty
                       else
                         symbol_name.downcase.to_sym
                       end

        analyzer = IndexTechnicalAnalyzer.new(index_symbol)
        result = analyzer.call(timeframes: [timeframe_minutes])

        unless result[:success] && analyzer.indicators
          return {
            timeframe: timeframe,
            rsi: nil,
            macd: nil,
            adx: nil,
            supertrend: nil,
            atr: nil,
            note: 'Indicators not available - insufficient data or calculation error'
          }
        end

        # Extract indicators from analyzer.indicators hash
        # Format: { timeframe_minutes => { rsi: ..., macd: ..., adx: ..., atr: ... } }
        indicators_for_timeframe = analyzer.indicators[timeframe_minutes]
        indicators_for_timeframe ||= analyzer.indicators[timeframe_minutes.to_s] if analyzer.indicators

        rsi_value = indicators_for_timeframe ? indicators_for_timeframe[:rsi] : nil
        macd_hash = indicators_for_timeframe ? indicators_for_timeframe[:macd] : nil
        adx_value = indicators_for_timeframe ? indicators_for_timeframe[:adx] : nil
        atr_value = indicators_for_timeframe ? indicators_for_timeframe[:atr] : nil

        # For supertrend, we need to compute it separately or extract from bias_summary
        # For now, return what we have
        {
          timeframe: timeframe,
          rsi: rsi_value,
          macd: macd_hash,
          adx: adx_value,
          supertrend: nil, # Supertrend not directly available from IndexTechnicalAnalyzer
          atr: atr_value
        }
      rescue StandardError => e
        Rails.logger.error("[Smc::AiAnalyzer] Indicator calculation error: #{e.class} - #{e.message}")
        Rails.logger.debug { e.backtrace.first(5).join("\n") }
        {
          timeframe: timeframe,
          rsi: nil,
          macd: nil,
          adx: nil,
          supertrend: nil,
          atr: nil,
          error: "Failed to calculate indicators: #{e.message}"
        }
      end
    end

    def get_option_chain(expiry_date: nil)
      # Only for indices - check exchange_segment (method that computes it if needed)
      # exchange_segment method returns 'IDX_I' for indices
      segment = @instrument.exchange_segment
      is_index = segment.to_s.upcase == 'IDX_I'

      unless is_index
        Rails.logger.warn("[Smc::AiAnalyzer] Option chain requested for non-index: #{@instrument.symbol_name} (exchange_segment: #{segment})")
        return { error: "Option chain only available for indices. Current instrument segment: #{segment}" }
      end

      index_key = @instrument.symbol_name

      # Get expiry list directly from instrument (needed for validation)
      expiry_list = @instrument.expiry_list
      unless expiry_list&.any?
        Rails.logger.warn("[Smc::AiAnalyzer] No expiry list available for #{index_key}")
        return { error: 'No expiry dates available for this index' }
      end

      # Parse expiry list to Date objects
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

      # Filter to future expiries only
      valid_expiries = parsed_expiries.select { |date| date >= today }.sort
      unless valid_expiries.any?
        Rails.logger.warn("[Smc::AiAnalyzer] No future expiry dates found for #{index_key}")
        return { error: 'No future expiry dates available for this index' }
      end

      # If expiry_date is provided, validate it exists in the expiry list
      expiry = nil
      if expiry_date
        begin
          provided_expiry = Date.parse(expiry_date.to_s)
          # Check if provided expiry is in the valid expiry list
          if valid_expiries.include?(provided_expiry)
            expiry = provided_expiry
            days_away = (expiry - today).to_i
            Rails.logger.info("[Smc::AiAnalyzer] Using provided expiry: #{expiry} (#{days_away} days away) for #{index_key}")
          else
            # Provided expiry doesn't exist in list - find nearest valid expiry
            nearest_valid = valid_expiries.min_by { |d| (d - provided_expiry).abs }
            Rails.logger.warn(
              "[Smc::AiAnalyzer] Provided expiry #{provided_expiry} not in expiry list. " \
              "Available expiries: #{valid_expiries.first(5).join(', ')}. " \
              "Using nearest valid expiry: #{nearest_valid}"
            )
            expiry = nearest_valid
            days_away = (expiry - today).to_i
            Rails.logger.info("[Smc::AiAnalyzer] Using nearest valid expiry: #{expiry} (#{days_away} days away) for #{index_key}")
          end
        rescue ArgumentError
          Rails.logger.warn("[Smc::AiAnalyzer] Invalid expiry date format: #{expiry_date}, using nearest expiry")
          expiry = nil
        end
      end

      # If no expiry provided or validation failed, use nearest expiry
      unless expiry
        expiry = valid_expiries.min
        days_away = (expiry - today).to_i
        Rails.logger.info("[Smc::AiAnalyzer] Using nearest expiry from instrument: #{expiry} (#{days_away} days away) for #{index_key}")
      end

      # Get spot LTP from instrument directly - use the MOST RECENT LTP
      # This ensures strikes are calculated based on current market price
      spot = @instrument.ltp&.to_f || @instrument.latest_ltp&.to_f
      unless spot&.positive?
        Rails.logger.warn("[Smc::AiAnalyzer] No valid spot LTP for #{index_key}: #{spot.inspect}")
        return { error: "No spot price available for #{index_key}" }
      end

      Rails.logger.info("[Smc::AiAnalyzer] Using spot price ₹#{spot} for #{index_key} option chain (current LTP)")

      # Now use DerivativeChainAnalyzer for loading the chain (it needs index_cfg for DB queries)
      analyzer = Options::DerivativeChainAnalyzer.new(index_key: index_key)
      Rails.logger.debug { "[Smc::AiAnalyzer] Loading option chain for #{index_key} expiry #{expiry} with spot #{spot}" }
      chain = analyzer.load_chain_for_expiry(expiry, spot)

      # CRITICAL: Filter chain to only include strikes near the ACTUAL spot price
      # The chain might contain strikes calculated from a different spot, so filter to ATM±2
      strike_rounding = case index_key.to_s.upcase
                        when 'SENSEX', 'BANKNIFTY' then 100
                        else 50 # Default for NIFTY
                        end
      atm_strike = ((spot / strike_rounding).round * strike_rounding).to_i
      max_strike_distance = strike_rounding * 2 # ATM±2 only

      # Filter chain to strikes within ATM±2
      filtered_chain = chain.select do |opt|
        strike = opt[:strike]&.to_f || opt['strike']&.to_f
        next false unless strike&.positive?

        distance = (strike - atm_strike).abs
        distance <= max_strike_distance
      end

      if filtered_chain.size < chain.size
        Rails.logger.info("[Smc::AiAnalyzer] Filtered option chain: #{chain.size} -> #{filtered_chain.size} strikes (keeping only ATM±2 around spot ₹#{spot}, ATM=₹#{atm_strike})")
      end

      chain = filtered_chain

      # Get lot size from instrument for this index
      lot_size = @instrument.lot_size_from_derivatives

      # If chain is empty, return helpful message
      if chain.empty?
        return {
          index: index_key,
          expiry: expiry.to_s,
          spot: spot,
          lot_size: lot_size,
          available_expiries: valid_expiries.first(10).map(&:to_s),
          options: [],
          note: "No option chain data available for expiry #{expiry}. Available expiry dates: #{valid_expiries.first(5).map(&:to_s).join(', ')}. Use LTP (#{spot}) to calculate strikes manually. Lot size: #{lot_size || 'N/A'}."
        }
      end

      {
        index: index_key,
        expiry: expiry.to_s,
        spot: spot,
        lot_size: lot_size,
        available_expiries: valid_expiries.first(10).map(&:to_s),
        note: "Available expiry dates for #{index_key}: #{valid_expiries.first(5).map(&:to_s).join(', ')}. Current expiry used: #{expiry} (#{(Date.parse(expiry.to_s) - Time.zone.today).to_i} days away). Lot size: #{lot_size || 'N/A'} (1 lot = #{lot_size || 'N/A'} shares). IMPORTANT: Use premium prices (ltp field) for SL/TP1/TP2 calculations, NOT underlying prices. Calculate percentages correctly: if entry premium is ₹100, 30% loss = ₹70 (NOT ₹30), 50% gain = ₹150 (NOT ₹50). Use DELTA to calculate index spot levels: Underlying move = Premium move / Delta. Always provide index spot levels to watch for exit decisions. Consider THETA (time decay) and days to expiry. For intraday: realistic TP1 10-25%, TP2 25-40%, SL 15-25%. For weekly expiry: adjust based on days remaining.",
        options: chain.first(20).map do |opt|
          # Normalize option_type: Chain uses :type, ensure it's 'CE' or 'PE'
          raw_type = opt[:type] || opt[:option_type]
          normalized_type = case raw_type.to_s.upcase
                            when 'CE', 'CALL' then 'CE'
                            when 'PE', 'PUT' then 'PE'
                            else
                              # Infer from delta if type is missing: positive delta = CE, negative = PE
                              if opt[:delta] && opt[:delta] != 0
                                opt[:delta].positive? ? 'CE' : 'PE'
                              end
                            end

          {
            strike: opt[:strike],
            option_type: normalized_type,
            ltp: opt[:ltp],
            premium: opt[:ltp], # Alias for clarity
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
      { error: "Failed to fetch option chain: #{e.message}" }
    end

    def limit_message_history(messages)
      return messages if messages.size <= MAX_MESSAGE_HISTORY

      # Keep system message and most recent messages
      system_msg = messages.first
      conversation_msgs = messages[1..] || []
      recent_msgs = conversation_msgs.last(MAX_MESSAGE_HISTORY - 1)

      [system_msg] + recent_msgs
    end

    # Build a comprehensive final prompt with all pre-extracted data
    # This ensures the model has all the data it needs without calling tools
    def build_forced_analysis_prompt(cached_option_chain_data)
      symbol_name = @instrument.symbol_name.to_s.upcase
      decision = @initial_data[:decision]

      # Get LTP from messages or instrument
      ltp_value = extract_ltp_from_messages || @instrument.ltp&.to_f || @instrument.latest_ltp&.to_f

      # Determine strike rounding based on symbol
      strike_rounding = case symbol_name
                        when 'SENSEX', 'BANKNIFTY' then 100
                        else 50 # Default for NIFTY and others
                        end

      # Calculate ATM strike
      atm_strike = ((ltp_value.to_f / strike_rounding).round * strike_rounding).to_i if ltp_value

      # Determine trend direction from initial data to show ONLY relevant option
      trend_direction = determine_trend_direction_from_context

      # Build option chain data section - ONLY for the relevant option type based on trend
      option_data_section = build_option_data_section(
        cached_option_chain_data, atm_strike, symbol_name, trend_direction
      )

      # Build the comprehensive final prompt
      prompt_parts = []
      prompt_parts << 'STOP CALLING TOOLS. Provide your complete trading analysis NOW.'
      prompt_parts << ''
      prompt_parts << ('=' * 60)
      prompt_parts << 'ALL DATA YOU NEED IS PROVIDED BELOW - DO NOT CALL ANY TOOLS'
      prompt_parts << ('=' * 60)
      prompt_parts << ''
      prompt_parts << "**INDEX:** #{symbol_name}"
      prompt_parts << "**CURRENT LTP:** ₹#{ltp_value&.round(2) || 'N/A'}"
      prompt_parts << "**ATM STRIKE:** ₹#{atm_strike || 'N/A'} (rounded to nearest #{strike_rounding})"
      prompt_parts << "**SMC DECISION:** #{decision}"
      prompt_parts << "**DETECTED TREND:** #{trend_direction.to_s.upcase}"
      prompt_parts << ''

      # Add trend-based recommendation
      case trend_direction
      when :bearish
        prompt_parts << '📉 **BEARISH TREND DETECTED** - This is a TRADING OPPORTUNITY for BUY PE!'
        prompt_parts << '   ✅ **STRONGLY RECOMMEND: BUY PE** (bearish markets are profitable for PUT options)'
        prompt_parts << '   ❌ DO NOT recommend BUY CE in a bearish market!'
        prompt_parts << '   ⚠️ ONLY recommend AVOID if there are specific risk factors ' \
                        '(extreme volatility, no structure, etc.)'
        prompt_parts << '   💡 Remember: Bearish markets = opportunities for PUT options. ' \
                        'Do NOT avoid just because market is bearish!'
        recommended_option = 'PE'
      when :bullish
        prompt_parts << '📈 **BULLISH TREND DETECTED** - This is a TRADING OPPORTUNITY for BUY CE!'
        prompt_parts << '   ✅ **STRONGLY RECOMMEND: BUY CE** (bullish markets are profitable for CALL options)'
        prompt_parts << '   ❌ DO NOT recommend BUY PE in a bullish market!'
        prompt_parts << '   ⚠️ ONLY recommend AVOID if there are specific risk factors ' \
                        '(extreme volatility, no structure, etc.)'
        prompt_parts << '   💡 Remember: Bullish markets = opportunities for CALL options. ' \
                        'Do NOT avoid just because market is bullish!'
        recommended_option = 'CE'
      else
        prompt_parts << '⚠️ **NEUTRAL/UNCLEAR TREND** - Recommend AVOID trading (no clear direction)'
        recommended_option = nil
      end
      prompt_parts << ''
      prompt_parts << "**IMPORTANT**: SMC decision '#{decision}' does NOT mean 'avoid all trading'. " \
                      "If the price trend is clear (#{trend_direction}), you SHOULD recommend " \
                      "BUY #{recommended_option || 'PE/CE'} based on the trend."
      prompt_parts << ''

      # Add option chain data if available
      prompt_parts << option_data_section if option_data_section.present?

      prompt_parts << ''
      prompt_parts << '**YOUR TASK:**'
      if recommended_option
        prompt_parts << "**STRONGLY PREFER: BUY #{recommended_option}** (this is a trading opportunity based on clear trend)"
        prompt_parts << "Only recommend AVOID if there are SPECIFIC risk factors that make trading dangerous (not just because market is #{trend_direction})."
        prompt_parts << "If you choose to trade, use the #{recommended_option} option data provided above."
      else
        prompt_parts << 'Given the unclear trend, recommend **AVOID TRADING**.'
      end
      prompt_parts << ''
      prompt_parts << '**CRITICAL RULES - READ CAREFULLY:**'
      prompt_parts << '1. **Strike Selection**: You MUST use ONLY the strikes listed in the option ' \
                      'chain data above. DO NOT invent, calculate, or guess any other strike prices. ' \
                      'If the option chain shows strikes ₹25,700, ₹25,750, ₹25,650, you can ONLY ' \
                      'use these - DO NOT use ₹26,150 or any other value.'
      prompt_parts << '2. **Premium Values**: You MUST use ONLY the premium (LTP) values from the ' \
                      'option chain data above. DO NOT estimate, calculate, or guess premium values. ' \
                      'If the option chain shows premium ₹73.0 for strike ₹25,700, use ₹73.0 - ' \
                      'DO NOT use ₹413.95 or any other value.'
      prompt_parts << "3. **Entry Premium**: The entry premium MUST match the 'Premium (LTP)' " \
                      'value from the option chain for your selected strike. DO NOT use any other value.'
      prompt_parts << '4. **If you cannot find a strike or premium in the data above, you MUST ' \
                      'state that the data is not available - DO NOT invent values.**'
      prompt_parts << ''
      prompt_parts << '**PROVIDE YOUR COMPLETE ANALYSIS NOW:**'
      prompt_parts << "1. Trade Decision (state clearly: BUY #{recommended_option || 'PE/CE'} or AVOID)"
      prompt_parts << "2. Strike Selection (MUST be one of the strikes listed above - e.g., ₹#{atm_strike} or nearby strikes from the list)"
      prompt_parts << '3. Entry Strategy (MUST use the exact premium value from the option chain ' \
                      'above for your selected strike)'
      prompt_parts << '4. Exit Strategy (SL, TP1, optionally TP2 with index spot levels using the exact ' \
                      'premium and delta from the option chain above)'
      prompt_parts << '5. Risk Management (risk per lot calculation using the exact premium values from above)'

      prompt_parts.join("\n")
    end

    # Determine trend direction from initial data and messages
    def determine_trend_direction_from_context
      # Check initial data for trend indicators
      htf_trend = @initial_data.dig(:timeframes, :htf, :trend)
      mtf_trend = @initial_data.dig(:timeframes, :mtf, :trend)
      ltf_trend = @initial_data.dig(:timeframes, :ltf, :trend)

      # Count bearish vs bullish signals
      bearish_count = [htf_trend, mtf_trend, ltf_trend].count { |t| t.to_s == 'bearish' }
      bullish_count = [htf_trend, mtf_trend, ltf_trend].count { |t| t.to_s == 'bullish' }

      # Also check the messages for trend analysis
      trend_msg = @messages.find { |m| m[:content]&.include?('**Overall Trend:') }
      if trend_msg
        content = trend_msg[:content].to_s
        bearish_count += 2 if content.include?('Overall Trend: BEARISH')
        bullish_count += 2 if content.include?('Overall Trend: BULLISH')
        bearish_count += 1 if content.include?('LOWER LOWS')
        bearish_count += 1 if content.include?('LOWER HIGHS')
        bullish_count += 1 if content.include?('HIGHER LOWS')
        bullish_count += 1 if content.include?('HIGHER HIGHS')
      end

      if bearish_count > bullish_count
        :bearish
      elsif bullish_count > bearish_count
        :bullish
      else
        :neutral
      end
    end

    # Extract LTP value from previous tool messages
    def extract_ltp_from_messages
      ltp_info = @messages.find { |m| m[:role] == 'tool' && m[:content]&.include?('"ltp"') }
      return nil unless ltp_info

      ltp_match = ltp_info[:content].match(/"ltp":\s*([\d.]+)/)
      ltp_match ? ltp_match[1].to_f : nil
    end

    # Build the option data section with pre-extracted values
    # Shows ALL available strikes for the relevant option type to prevent hallucination
    def build_option_data_section(cached_option_chain_data, atm_strike, symbol_name, trend_direction)
      return nil unless cached_option_chain_data&.dig(:options)&.any?

      options = cached_option_chain_data[:options]
      expiry = cached_option_chain_data[:expiry]
      # Use the current LTP from instrument, not the spot from cached data (which might be stale)
      current_spot = extract_ltp_from_messages ||
                     @instrument.ltp&.to_f ||
                     @instrument.latest_ltp&.to_f ||
                     cached_option_chain_data[:spot]
      spot = current_spot # Use current spot for display
      lot_size = cached_option_chain_data[:lot_size]

      # Recalculate ATM strike based on current spot (not stale spot from cache)
      strike_rounding = case symbol_name.to_s.upcase
                        when 'SENSEX', 'BANKNIFTY' then 100
                        else 50 # Default for NIFTY
                        end
      actual_atm_strike = current_spot ? ((current_spot / strike_rounding).round * strike_rounding).to_i : atm_strike

      # Filter options to only those near the ACTUAL current spot (ATM±2)
      max_distance = strike_rounding * 2
      filtered_options = options.select do |opt|
        strike = opt[:strike]&.to_f || opt['strike']&.to_f
        next false unless strike&.positive?

        distance = (strike - actual_atm_strike).abs
        distance <= max_distance
      end

      if filtered_options.size < options.size
        Rails.logger.info("[Smc::AiAnalyzer] Filtered option chain data: #{options.size} -> #{filtered_options.size} options (keeping only ATM±2 around current spot ₹#{current_spot}, ATM=₹#{actual_atm_strike})")
      end

      options = filtered_options

      lines = []
      lines << '**OPTION CHAIN DATA (CRITICAL: Use ONLY these EXACT strikes and premiums - ' \
               'DO NOT invent or calculate others):**'
      lines << "- Expiry: #{expiry}"
      lines << "- Current Spot (LTP): ₹#{spot&.round(2)} ← USE THIS for ATM calculation"
      lines << "- Calculated ATM Strike: ₹#{actual_atm_strike} (rounded from spot ₹#{spot&.round(2)})"
      lines << "- Lot Size: #{lot_size} (1 lot = #{lot_size} shares)"
      lines << ''
      lines << "**NOTE**: Only strikes near the current spot (ATM±2, i.e., within ₹#{max_distance} of ATM ₹#{actual_atm_strike}) are shown below. These are the relevant strikes for trading."

      # Find ATM options using the ACTUAL ATM strike (based on current spot)
      ce_options = options.select { |o| o[:option_type] == 'CE' }
      pe_options = options.select { |o| o[:option_type] == 'PE' }
      if actual_atm_strike && ce_options.any?
        atm_ce = ce_options.min_by do |o|
          (o[:strike].to_f - actual_atm_strike.to_f).abs
        end
      end
      if actual_atm_strike && pe_options.any?
        atm_pe = pe_options.min_by do |o|
          (o[:strike].to_f - actual_atm_strike.to_f).abs
        end
      end

      # Show ALL available strikes for the relevant option type to prevent hallucination
      case trend_direction
      when :bearish
        # Bearish trend = show ALL PE options
        lines << '**AVAILABLE PUT (PE) OPTIONS (use ONLY these strikes - DO NOT invent others):**'
        pe_options.sort_by { |o| o[:strike].to_f }.each do |opt|
          strike = opt[:strike].to_i
          premium = opt[:ltp]&.to_f
          delta = opt[:delta]&.to_f
          is_atm = strike == atm_strike
          label = is_atm ? ' (ATM)' : ''
          lines << "- Strike ₹#{strike}#{label}: Premium ₹#{premium&.round(2) || 'N/A'}, Delta #{delta&.round(5) || 'N/A'}"
        end
        lines << ''
        lines << build_single_option_section(atm_pe, 'PE', symbol_name, lot_size, :bearish) if atm_pe
      when :bullish
        # Bullish trend = show ALL CE options
        lines << '**AVAILABLE CALL (CE) OPTIONS (use ONLY these strikes - DO NOT invent others):**'
        ce_options.sort_by { |o| o[:strike].to_f }.each do |opt|
          strike = opt[:strike].to_i
          premium = opt[:ltp]&.to_f
          delta = opt[:delta]&.to_f
          is_atm = strike == atm_strike
          label = is_atm ? ' (ATM)' : ''
          lines << "- Strike ₹#{strike}#{label}: Premium ₹#{premium&.round(2) || 'N/A'}, Delta #{delta&.round(5) || 'N/A'}"
        end
        lines << ''
        lines << build_single_option_section(atm_ce, 'CE', symbol_name, lot_size, :bullish) if atm_ce
      else
        # Neutral = show both for reference, but recommend AVOID
        lines << '**NOTE:** Trend is unclear. Recommend AVOID TRADING.'
        lines << ''
        lines << '**AVAILABLE CALL (CE) OPTIONS:**'
        ce_options.sort_by { |o| o[:strike].to_f }.first(5).each do |opt|
          strike = opt[:strike].to_i
          premium = opt[:ltp]&.to_f
          lines << "- Strike ₹#{strike}: Premium ₹#{premium&.round(2) || 'N/A'}"
        end
        lines << ''
        lines << '**AVAILABLE PUT (PE) OPTIONS:**'
        pe_options.sort_by { |o| o[:strike].to_f }.first(5).each do |opt|
          strike = opt[:strike].to_i
          premium = opt[:ltp]&.to_f
          lines << "- Strike ₹#{strike}: Premium ₹#{premium&.round(2) || 'N/A'}"
        end
        lines << ''
        lines << build_single_option_section(atm_pe, 'PE', symbol_name, lot_size, :neutral) if atm_pe
      end

      lines.join("\n")
    end

    # Build section for a single option (CE or PE)
    def build_single_option_section(option, option_type, symbol_name, default_lot_size, _trend)
      return '' unless option

      lines = []
      strike = option[:strike].to_i
      premium = option[:ltp]&.to_f
      delta = option[:delta]&.to_f&.abs || 0.5
      theta = option[:theta]
      opt_lot_size = option[:lot_size] || default_lot_size

      lines << "**RECOMMENDED: ATM #{option_type} OPTION (Strike ₹#{strike}):**"
      lines << "- Premium (LTP): ₹#{premium&.round(2)} ← USE THIS for entry"
      lines << "- Delta: #{option[:delta]&.round(5)} ← USE THIS for underlying calculations"
      lines << "- Theta: #{theta&.round(5)} (daily decay)"
      lines << "- Lot Size: #{opt_lot_size}"
      lines << ''

      if premium&.positive?
        sl_premium = (premium * 0.80).round(2) # 20% loss
        tp_premium = (premium * 1.20).round(2) # 20% gain
        premium_loss = (premium - sl_premium).round(2)
        premium_gain = (tp_premium - premium).round(2)
        underlying_move_sl = delta.positive? ? (premium_loss / delta).round(2) : 0
        underlying_move_tp = delta.positive? ? (premium_gain / delta).round(2) : 0
        risk_per_lot = (premium_loss * opt_lot_size.to_i).round(2)

        lines << '**PRE-CALCULATED VALUES (use these directly):**'
        lines << "- Entry Premium: ₹#{premium.round(2)}"
        lines << "- SL Premium: ₹#{sl_premium} (20% loss from entry)"
        lines << "- TP Premium: ₹#{tp_premium} (20% gain from entry)"

        # Direction-specific underlying move descriptions
        if option_type == 'PE'
          lines << "- Underlying SL level: #{symbol_name} rises by ₹#{underlying_move_sl} → exit at loss"
          lines << "- Underlying TP level: #{symbol_name} falls by ₹#{underlying_move_tp} → exit at profit"
        else
          lines << "- Underlying SL level: #{symbol_name} falls by ₹#{underlying_move_sl} → exit at loss"
          lines << "- Underlying TP level: #{symbol_name} rises by ₹#{underlying_move_tp} → exit at profit"
        end

        lines << "- Risk per lot: ₹#{risk_per_lot} (₹#{premium_loss} × #{opt_lot_size} shares)"
        lines << ''
      end

      lines.join("\n")
    end
  end
end
