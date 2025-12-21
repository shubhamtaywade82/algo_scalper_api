# frozen_string_literal: true

module Services
  module Ai
    class TechnicalAnalysisAgent
      # Helper methods for symbol detection and token estimation
      module Helpers
        # Helper method to auto-detect exchange for known indices
        def detect_exchange_for_index(symbol_name, provided_exchange)
          # If exchange is explicitly provided, use it
          return provided_exchange.to_s.upcase if provided_exchange.present?

          # Auto-detect based on index name
          symbol_upper = symbol_name.to_s.upcase
          case symbol_upper
          when 'SENSEX'
            'BSE' # SENSEX is on BSE
          when 'NIFTY', 'BANKNIFTY', 'NIFTY50', 'NIFTY 50', 'BANKNIFTY50', 'BANK NIFTY'
            'NSE' # NIFTY and BANKNIFTY are on NSE
          else
            'NSE' # Default to NSE for unknown symbols (stocks are typically on NSE)
          end
        end

        # Helper method to auto-detect segment (index vs equity)
        def detect_segment_for_symbol(symbol_name, provided_segment)
          # If segment is explicitly provided, use it
          return provided_segment.to_s.downcase if provided_segment.present?

          # Auto-detect based on symbol name
          symbol_upper = symbol_name.to_s.upcase
          case symbol_upper
          when 'NIFTY', 'BANKNIFTY', 'SENSEX', 'NIFTY50', 'NIFTY 50', 'BANKNIFTY50', 'BANK NIFTY'
            'index' # Known indices
          else
            'equity' # Default to equity for stocks (RELIANCE, TCS, INFY, etc.)
          end
        end

        # Estimate token count for a prompt (rough approximation)
        def estimate_prompt_tokens(text)
          return 0 unless text.present?

          # Rough approximation: 1 token ≈ 4 characters
          (text.length / 4.0).ceil
        end

        # Extract meaningful keywords from query
        def extract_keywords(query)
          query.downcase
               .gsub(/[^\w\s]/, ' ')
               .split(/\s+/)
               .reject { |w| w.length < 3 || %w[the is are was were what how when where].include?(w) }
               .uniq
               .first(10)
        end
      end
    end
  end
end
