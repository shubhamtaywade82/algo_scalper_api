# frozen_string_literal: true

module Services
  module Ai
    class TechnicalAnalysisAgent
      # Handles learning and adaptation from errors
      module Learning
        def load_learned_patterns
          # Load learned patterns from Redis
          # Format: [{ keywords: ['nifty', 'rsi'], error_type: 'validation', error_count: 2, solution: '...' }, ...]
          patterns = []

          begin
            redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379/0'))
            stored = redis.get('ai_agent:learned_patterns')
            patterns = JSON.parse(stored) if stored.present?
            redis.close
          rescue StandardError => e
            Rails.logger.warn("[TechnicalAnalysisAgent] Failed to load learned patterns: #{e.message}")
          end

          patterns
        end

        def save_learned_patterns
          # Save learned patterns to Redis
          return if @learned_patterns.empty?

          begin
            redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379/0'))
            redis.set('ai_agent:learned_patterns', @learned_patterns.to_json)
            redis.expire('ai_agent:learned_patterns', 30.days.to_i) # Keep for 30 days
            redis.close
          rescue StandardError => e
            Rails.logger.warn("[TechnicalAnalysisAgent] Failed to save learned patterns: #{e.message}")
          end
        end

        def record_error(tool_name:, error_message:, query_keywords:)
          # Record error for learning
          error_type = classify_error(error_message)
          @error_history << {
            tool: tool_name,
            error: error_message,
            error_type: error_type,
            timestamp: Time.current
          }

          # Update learned patterns
          pattern = @learned_patterns.find { |p| p[:keywords] == query_keywords && p[:error_type] == error_type }
          if pattern
            pattern[:error_count] = (pattern[:error_count] || 0) + 1
            pattern[:last_seen] = Time.current
            pattern[:solution] = extract_solution(error_message) if pattern[:solution].blank?
          else
            @learned_patterns << {
              keywords: query_keywords,
              error_type: error_type,
              error_count: 1,
              last_seen: Time.current,
              solution: extract_solution(error_message)
            }
          end

          # Save patterns periodically (every 5 errors)
          save_learned_patterns if (@error_history.size % 5).zero?
        end

        def classify_error(error_message)
          # Classify error type for learning
          case error_message.to_s
          when /validation|invalid|must be one of/i
            'validation'
          when /not found|missing|unavailable/i
            'not_found'
          when /timeout|connection|network/i
            'network'
          when /permission|access|unauthorized/i
            'permission'
          else
            'unknown'
          end
        end

        def extract_solution(error_message)
          # Extract solution hint from error message
          case error_message.to_s
          when /must be one of: (.*?)(?:\]|$)/i
            "Use one of: #{::Regexp.last_match(1)}"
          when /Missing (.*?)(?:\s|$)/i
            "Provide: #{::Regexp.last_match(1)}"
          when /Invalid (.*?)(?:\s|$)/i
            "Fix: #{::Regexp.last_match(1)}"
          end
        end

        def build_learned_context
          # Build context from learned patterns to help AI avoid common mistakes
          return '' if @learned_patterns.empty?

          recent_patterns = @learned_patterns
                            .select { |p| p[:error_count].to_i >= 2 }
                            .sort_by { |p| p[:error_count] }
                            .last(5).reverse

          return '' if recent_patterns.empty?

          context = "\nLEARNED PATTERNS (common mistakes to avoid):\n"
          recent_patterns.each_with_index do |pattern, idx|
            context += "#{idx + 1}. When query involves: #{pattern[:keywords].join(', ')}\n"
            context += "   Common error: #{pattern[:error_type]}\n"
            context += "   Solution: #{pattern[:solution]}\n" if pattern[:solution].present?
            context += "   (Seen #{pattern[:error_count]} times)\n\n"
          end

          context
        end

        def calculate_max_iterations(query)
          base_iterations = 3
          complexity_score = 0

          # Analyze query complexity
          complexity_score += 1 if query.match?(/\b(and|or|compare|analyze|multiple)\b/i)
          complexity_score += 1 if query.match?(/\b(historical|backtest|optimize)\b/i)
          complexity_score += 1 if query.scan(/\b(NIFTY|BANKNIFTY|SENSEX)\b/i).length > 1

          # Check learned patterns for this query type
          query_keywords = extract_keywords(query)
          learned_complexity = @learned_patterns.select do |pattern|
            pattern[:keywords].any? { |kw| query_keywords.include?(kw) }
          end

          if learned_complexity.any?
            # Increase iterations if we've seen errors with similar queries
            avg_errors = learned_complexity.sum { |p| p[:error_count] || 0 }.to_f / learned_complexity.size
            complexity_score += [avg_errors.to_i, 2].min # Cap at +2
          end

          # Dynamic max_iterations: base + complexity (min 3, max 8)
          [base_iterations + complexity_score, 8].min
        end
      end
    end
  end
end
