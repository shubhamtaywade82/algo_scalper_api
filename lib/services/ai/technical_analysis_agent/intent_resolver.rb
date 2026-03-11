# frozen_string_literal: true

module Services
  module Ai
    class TechnicalAnalysisAgent
      # Intent Resolver: Single-purpose LLM call to extract intent from query
      # NO data fetching, NO instrument resolution, NO indicators
      module IntentResolver
        def resolve_intent(query)
          query_text = query.to_s

          # Small prompt - ONLY intent extraction
          prompt = <<~PROMPT
            Extract trading intent from this query. Respond with JSON only (no markdown, no explanations):

            Query: #{query_text}

            Extract:
            - underlying_symbol: The instrument symbol (e.g., "NIFTY", "RELIANCE", "TCS") or null if not found
            - intent: One of "swing_trading", "options_buying", "intraday", or "general"
            - derivatives_needed: true if query mentions options/derivatives, false otherwise
            - timeframe_hint: Suggested timeframe - "5m", "15m", "1h", or "daily"
            - confidence: Your confidence in the extraction (0.0 to 1.0)

            Respond with ONLY this JSON format:
            {
              "underlying_symbol": "NIFTY" | "RELIANCE" | null,
              "intent": "swing_trading" | "options_buying" | "intraday" | "general",
              "derivatives_needed": true | false,
              "timeframe_hint": "5m" | "15m" | "1h" | "daily",
              "confidence": 0.0-1.0
            }
          PROMPT

          # Single LLM call - NO tool calls
          model = if @client.provider == :ollama
                    if @client.respond_to?(:preferred_text_model)
                      @client.preferred_text_model(default: 'llama3.1:8b')
                    else
                      ENV['OLLAMA_MODEL'] || @client.selected_model || 'llama3.1:8b'
                    end
                  else
                    'gpt-4o'
                  end

          begin
            response = @client.chat(
              messages: [
                { role: 'system',
                  content: 'You are an intent extractor. Return JSON only, no markdown, no explanations.' },
                { role: 'user', content: prompt }
              ],
              model: model,
              temperature: 0.1 # Low temperature for consistency
            )

            # Parse JSON response
            parsed = JSON.parse(response.to_s)
            symbol = parsed['underlying_symbol']

            # Validate symbol: if null/empty OR doesn't appear as whole word in query, use fallback
            # Check for whole word match (not substring like "NIFTY" in "INDEX")
            symbol_valid = if symbol.blank?
                             false
                           else
                             symbol_up = symbol.to_s.upcase
                             query_up = query_text.upcase
                             # Check for whole word match (word boundaries)
                             query_up.match?(/\b#{Regexp.escape(symbol_up)}\b/)
                           end

            symbol = extract_symbol_fallback(query_text) unless symbol_valid

            inferred_intent = infer_intent_fallback(query_text)
            parsed_intent = parsed['intent']&.to_sym
            # If model returns generic intent for indicator-heavy query, prefer deterministic fallback.
            intent = if parsed_intent == :general && inferred_intent != :general
                       inferred_intent
                     else
                       parsed_intent || inferred_intent || :general
                     end

            {
              underlying_symbol: symbol,
              intent: intent,
              derivatives_needed: parsed['derivatives_needed'] || false,
              timeframe_hint: parsed['timeframe_hint'] || '15m',
              confidence: parsed['confidence']&.to_f || 0.5
            }
          rescue JSON::ParserError => e
            Rails.logger.warn("[IntentResolver] Failed to parse intent JSON: #{e.class} - #{e.message}")
            # Fallback: extract symbol only, default intent
            {
              underlying_symbol: extract_symbol_fallback(query_text),
              intent: infer_intent_fallback(query_text),
              derivatives_needed: false,
              timeframe_hint: '15m',
              confidence: 0.3
            }
          rescue StandardError => e
            Rails.logger.warn("[IntentResolver] Failed to resolve intent: #{e.class} - #{e.message}")
            # Fallback: extract symbol only, default intent
            {
              underlying_symbol: extract_symbol_fallback(query_text),
              intent: infer_intent_fallback(query_text),
              derivatives_needed: false,
              timeframe_hint: '15m',
              confidence: 0.3
            }
          end
        end

        private

        def extract_symbol_fallback(query)
          # Simple fallback to extract symbol from query
          query_upper = query.upcase

          # Check for common index names first
          if query_upper.include?('SENSEX')
            'SENSEX'
          elsif query_upper.include?('BANKNIFTY')
            'BANKNIFTY'
          elsif query_upper.include?('NIFTY')
            'NIFTY'
          else
            # Try to find any uppercase word (likely symbol)
            # Look for patterns like "INDEX like SENSEX" or "like SENSEX"
            like_match = query.match(/like\s+([A-Z]{2,10})/i)
            return like_match[1].upcase if like_match

            # Look for "in INDEX like X" pattern
            index_like_match = query.match(/INDEX\s+like\s+([A-Z]{2,10})/i)
            return index_like_match[1].upcase if index_like_match

            # Try to find any uppercase word (likely symbol)
            match = query.match(/\b([A-Z]{2,10})\b/)
            match ? match[1] : nil
          end
        end

        def infer_intent_fallback(query)
          query_upper = query.to_s.upcase
          return :options_buying if query_upper.match?(/\b(OPTION|CALL|PUT|STRIKE|PREMIUM|CE|PE)\b/)
          return :intraday if query_upper.match?(/\b(RSI|MACD|ADX|SUPERTREND|ATR|BOLLINGER|INDICATOR|TREND)\b/)

          :general
        end
      end
    end
  end
end
