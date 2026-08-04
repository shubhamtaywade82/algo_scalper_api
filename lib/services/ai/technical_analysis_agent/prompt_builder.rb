# frozen_string_literal: true

module Services
  module Ai
    class TechnicalAnalysisAgent
      # Handles building and formatting prompts for the AI agent
      module PromptBuilder
        def build_system_prompt
          <<~PROMPT
            You are a technical analysis agent for Indian markets (indices: NIFTY, BANKNIFTY, SENSEX; stocks: RELIANCE, TCS, etc.).

            SEGMENT RULES: Indices use "index", stocks use "equity". Tools auto-detect, but you can specify.

            EFFICIENCY: Use 'get_comprehensive_analysis' to get ALL data in ONE call (LTP, history, indicators). Only use individual tools for specific missing data.

            TOOLS:
            #{format_tools_for_prompt_concise}

            INDICATORS (use multiple, not just RSI):
            - RSI: <30 oversold, 30-50 neutral/bearish, 50-70 neutral/bullish, >70 overbought. 40-60 = NEUTRAL (not oversold/overbought).
            - MACD: Positive+positive histogram = bullish; negative+negative = bearish. Above signal = bullish crossover.
            - ADX: <20 weak trend, 20-40 moderate, >40 strong trend. Measures STRENGTH only, not direction.
            - Supertrend: "long_entry" = bullish, "short_entry" = bearish (not bounce opportunity).
            - ATR: Measures volatility, not direction. Higher = more volatility.
            - Bollinger Bands: Near upper = potentially overbought, near lower = potentially oversold.

            ANALYSIS RULES:
            1. Use MULTIPLE indicators together - look for CONFLUENCE (agreement = stronger signal)
            2. ADX = trend strength (not direction). Combine with Supertrend/MACD for direction.
            3. RSI 40-60 = NEUTRAL. Supertrend "short_entry" = BEARISH.
            4. When indicators conflict, explain which is stronger based on trend context.
            5. Use "indicator_interpretations" from tool results to guide analysis.

            TOOL CALL FORMAT (JSON only, no explanations):
            {"tool": "tool_name", "arguments": {"param": "value"}}

            CRITICAL:
            1. MUST call tools - don't just describe. Respond with ONLY JSON for tool calls.
            2. After tool results, provide analysis in natural language.
            3. Get all needed data in 1-2 tool calls, then provide complete analysis.
            4. Use CURRENT dates (today: #{Time.zone.today.strftime('%Y-%m-%d')}), not old dates like 2023.
          PROMPT
        end

        def format_tools_for_prompt
          @tools.map do |tool_name, tool_def|
            params = tool_def[:parameters].map { |p| "  - #{p[:name]} (#{p[:type]}): #{p[:description]}" }.join("\n")
            <<~TOOL
              **#{tool_name}**
              #{tool_def[:description]}
              Parameters:
              #{params}
            TOOL
          end.join("\n\n")
        end

        # Concise version for smaller prompts
        def format_tools_for_prompt_concise
          @tools.map do |tool_name, tool_def|
            # Shorten descriptions and parameters
            short_desc = tool_def[:description].split('.').first # First sentence only
            params = tool_def[:parameters].map { |p| "#{p[:name]}(#{p[:type]})" }.join(', ')
            "#{tool_name}: #{short_desc}. Params: #{params}"
          end.join("\n")
        end
      end
    end
  end
end
