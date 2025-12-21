# frozen_string_literal: true

module Services
  module Ai
    class TechnicalAnalysisAgent
      # Handles tool call extraction and execution
      module ToolExecutor
        def extract_tool_call(response)
          # Try multiple patterns to extract tool call JSON
          # Pattern 1: Direct JSON object
          json_match = response.match(/\{"tool"\s*:\s*"([^"]+)"\s*,\s*"arguments"\s*:\s*(\{.*?\})\s*\}/m)

          # Pattern 2: JSON in code blocks (```json ... ```)
          json_match ||= response.match(/```(?:json)?\s*\{[\s\n]*"tool"[\s\n]*:[\s\n]*"([^"]+)"[\s\n]*,[\s\n]*"arguments"[\s\n]*:[\s\n]*(\{.*?\})[\s\n]*\}[\s\n]*```/m)

          # Pattern 3: JSON after "tool": or similar markers
          json_match ||= response.match(/"tool"\s*:\s*"([^"]+)"\s*,\s*"arguments"\s*:\s*(\{.*?\})/m)

          return nil unless json_match

          begin
            {
              'tool' => json_match[1],
              'arguments' => JSON.parse(json_match[2])
            }
          rescue JSON::ParserError => e
            Rails.logger.debug { "[TechnicalAnalysisAgent] JSON parse error: #{e.message}" }
            Rails.logger.debug { "[TechnicalAnalysisAgent] Attempted to parse: #{json_match[2][0..200]}" }
            nil
          end
        end

        def execute_tool(tool_call)
          tool_name = tool_call['tool']
          arguments = tool_call['arguments'] || {}

          tool_def = @tools[tool_name]
          return { error: "Unknown tool: #{tool_name}" } unless tool_def

          # Check cache for identical tool calls (within same conversation)
          cache_key = "#{tool_name}:#{arguments.sort.to_json}"
          return @tool_cache[cache_key] if @tool_cache[cache_key]

          begin
            result = tool_def[:handler].call(arguments)
            # Cache successful results (not errors) for reuse
            @tool_cache[cache_key] = result unless result.is_a?(Hash) && result[:error]
            result
          rescue StandardError => e
            Rails.logger.error("[TechnicalAnalysisAgent] Tool error (#{tool_name}): #{e.class} - #{e.message}")
            error_result = { error: "#{e.class}: #{e.message}" }

            # Record error for learning (if we have query context)
            if @current_query_keywords
              record_error(
                tool_name: tool_name,
                error_message: e.message,
                query_keywords: @current_query_keywords
              )
            end

            error_result
          end
        end
      end
    end
  end
end
