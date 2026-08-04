# frozen_string_literal: true

module Services
  module Ai
    class TechnicalAnalysisAgent
      # Handles conversation execution (both streaming and non-streaming)
      module ConversationExecutor
        # Maximum message history to keep (reduces token usage)
        MAX_MESSAGE_HISTORY = ENV.fetch('AI_MAX_MESSAGE_HISTORY', '8').to_i # Keep last 8 messages (system + 7)

        # Truncate message content (no-op - returns content as-is)
        def truncate_message(content, _max_length = nil)
          content
        end

        # Truncate tool result JSON (no-op - returns full result)
        def truncate_tool_result(tool_result, _max_length = nil)
          JSON.pretty_generate(tool_result)
        end

        # Limit message history to prevent token bloat
        def limit_message_history(messages)
          # Always keep system message (first)
          system_msg = messages.first
          conversation_msgs = messages[1..] || []

          # Keep only the most recent messages
          max_conversation = MAX_MESSAGE_HISTORY - 1 # -1 for system message
          conversation_msgs = conversation_msgs.last(max_conversation) if conversation_msgs.size > max_conversation

          [system_msg] + conversation_msgs
        end

        def execute_conversation(messages:, model:)
          # Iterate until we get a final analysis, with configurable safety limits
          # Default: 15 iterations (allows for multiple tool calls and comprehensive analysis)
          # Can be overridden via AI_AGENT_MAX_ITERATIONS environment variable
          safety_limit = ENV.fetch('AI_AGENT_MAX_ITERATIONS', '15').to_i
          safety_limit = [safety_limit, 3].max # Minimum 3 iterations
          safety_limit = [safety_limit, 100].min # Maximum 100 iterations (safety cap)

          iteration = 0
          full_response = ''
          consecutive_tool_calls = 0
          max_consecutive_tools = ENV.fetch('AI_AGENT_MAX_CONSECUTIVE_TOOLS', '8').to_i
          max_consecutive_tools = [max_consecutive_tools, 3].max # Minimum 3
          max_consecutive_tools = [max_consecutive_tools, 15].min # Maximum 15

          Rails.logger.debug { "[TechnicalAnalysisAgent] Starting conversation (safety_limit: #{safety_limit} iterations, max_consecutive_tools: #{max_consecutive_tools})" }

          while iteration < safety_limit
            Rails.logger.debug { "[TechnicalAnalysisAgent] Iteration #{iteration + 1}/#{safety_limit}" }

            # Estimate tokens before sending and warn if too large
            total_chars = messages.sum { |m| (m[:content] || m['content'] || '').length }
            estimated_tokens = (total_chars / 4.0).ceil
            max_tokens_per_request = ENV.fetch('AI_MAX_TOKENS_PER_REQUEST', '4000').to_i

            if estimated_tokens > max_tokens_per_request
              Rails.logger.warn("[TechnicalAnalysisAgent] Large message payload: ~#{estimated_tokens} tokens (max: #{max_tokens_per_request}). Truncating...")
              # Further limit message history if needed
              messages = limit_message_history(messages)
              # Re-estimate after truncation
              total_chars = messages.sum { |m| (m[:content] || m['content'] || '').length }
              estimated_tokens = (total_chars / 4.0).ceil
            end

            response = @client.chat(
              messages: messages,
              model: model,
              temperature: 0.3
            )

            unless response
              Rails.logger.warn('[TechnicalAnalysisAgent] No response from AI client, retrying iteration')
              iteration += 1
              next
            end

            Rails.logger.debug { "[TechnicalAnalysisAgent] Received response (#{response.length} chars)" }

            # Check if we got any response
            if response.blank? || response.strip.empty?
              Rails.logger.warn('[TechnicalAnalysisAgent] No response received, retrying iteration')
              iteration += 1
              next
            end

            # Check if response contains tool call
            tool_call = extract_tool_call(response)
            if tool_call
              consecutive_tool_calls += 1

              # Safety check: if we've called tools 10 times in a row without analysis, force a break
              if consecutive_tool_calls >= max_consecutive_tools
                Rails.logger.warn("[TechnicalAnalysisAgent] Too many consecutive tool calls (#{consecutive_tool_calls}), forcing analysis request")
                messages << { role: 'assistant', content: response }
                messages << {
                  role: 'user',
                  content: 'You have called many tools. Please provide your analysis now based on all the data you have gathered. ' \
                           'Do not call any more tools - provide a complete analysis with your findings and actionable insights.'
                }
                consecutive_tool_calls = 0 # Reset counter
                messages = limit_message_history(messages)
                iteration += 1
                next
              end

              Rails.logger.debug { "[TechnicalAnalysisAgent] Tool call: #{tool_call['tool']} (consecutive: #{consecutive_tool_calls})" }

              # Execute tool
              tool_result = execute_tool(tool_call)

              # Record errors for learning
              if tool_result.is_a?(Hash) && tool_result[:error]
                record_error(
                  tool_name: tool_call['tool'],
                  error_message: tool_result[:error],
                  query_keywords: @current_query_keywords || []
                )
              end

              # Add assistant message and tool result to conversation
              messages << { role: 'assistant', content: response }

              # Include full tool result
              tool_result_str = truncate_tool_result(tool_result)
              messages << {
                role: 'tool',
                content: "Tool: #{tool_call['tool']}\nResult: #{tool_result_str}"
              }
              # Explicitly prompt for analysis after tool result
              messages << {
                role: 'user',
                content: 'Based on the tool result above, provide your analysis. ' \
                         'If you have enough data, provide a complete analysis now. ' \
                         'If you need more data, call another tool.'
              }

              # Limit message history to prevent token bloat
              messages = limit_message_history(messages)

              iteration += 1
              next
            end

            # No tool call - check if response is meaningful
            # Reset consecutive tool calls counter when we get a non-tool response
            consecutive_tool_calls = 0

            if response.strip.length > 20 && !response.match?(/\{"tool"/i)
              # Final response received (has content and no tool call)
              Rails.logger.info('[TechnicalAnalysisAgent] Analysis complete - final response received')
              full_response = response
              break
            else
              # Empty or very short response - prompt for analysis
              Rails.logger.warn("[TechnicalAnalysisAgent] Received very short response (#{response.length} chars), prompting for analysis...")
              messages << { role: 'assistant', content: response }
              messages << {
                role: 'user',
                content: 'Please provide a complete analysis based on the data you have gathered. ' \
                         'Summarize your findings and provide actionable insights. ' \
                         'Do not call more tools - provide your analysis now.'
              }

              # Limit message history
              messages = limit_message_history(messages)

              iteration += 1
              next
            end
          end

          if iteration >= safety_limit
            Rails.logger.warn("[TechnicalAnalysisAgent] Reached safety limit (#{safety_limit} iterations)")
          end

          Rails.logger.info("[TechnicalAnalysisAgent] Completed in #{iteration} iteration(s)")

          # Save learned patterns at end of conversation
          save_learned_patterns if @error_history.any?

          {
            analysis: full_response,
            generated_at: Time.current,
            provider: @client.provider,
            iterations: iteration,
            errors_encountered: @error_history.size,
            learned_patterns_applied: @learned_patterns.count do |p|
              keywords = p[:keywords] || []
              keywords.any? do |kw|
                @current_query_keywords&.include?(kw)
              end
            end
          }
        rescue StandardError => e
          Rails.logger.error("[TechnicalAnalysisAgent] Error: #{e.class} - #{e.message}")
          Rails.logger.error("[TechnicalAnalysisAgent] Backtrace: #{e.backtrace.first(5).join("\n")}")
          nil
        end

        def execute_conversation_stream(messages:, model:, &_block)
          # Iterate until we get a final analysis, with configurable safety limits
          # Default: 15 iterations (allows for multiple tool calls and comprehensive analysis)
          # Can be overridden via AI_AGENT_MAX_ITERATIONS environment variable
          safety_limit = ENV.fetch('AI_AGENT_MAX_ITERATIONS', '15').to_i
          safety_limit = [safety_limit, 3].max # Minimum 3 iterations
          safety_limit = [safety_limit, 100].min # Maximum 100 iterations (safety cap)

          iteration = 0
          full_response = +''
          consecutive_tool_calls = 0
          max_consecutive_tools = ENV.fetch('AI_AGENT_MAX_CONSECUTIVE_TOOLS', '8').to_i
          max_consecutive_tools = [max_consecutive_tools, 3].max # Minimum 3
          max_consecutive_tools = [max_consecutive_tools, 15].min # Maximum 15

          # Stream: Start message
          yield("🔍 [Agent] Starting analysis (safety_limit: #{safety_limit} iterations, max_consecutive_tools: #{max_consecutive_tools})\n\n") if block_given?
          Rails.logger.info("[TechnicalAnalysisAgent] Starting analysis (streaming, safety_limit: #{safety_limit} iterations, max_consecutive_tools: #{max_consecutive_tools})")

          while iteration < safety_limit
            # Stream: Iteration start
            yield("📊 [Agent] Iteration #{iteration + 1}/#{safety_limit}\n") if block_given?
            Rails.logger.info("[TechnicalAnalysisAgent] Iteration #{iteration + 1}/#{safety_limit}")

            # Estimate tokens before sending and warn if too large
            total_chars = messages.sum { |m| (m[:content] || m['content'] || '').length }
            estimated_tokens = (total_chars / 4.0).ceil
            max_tokens_per_request = ENV.fetch('AI_MAX_TOKENS_PER_REQUEST', '4000').to_i

            if estimated_tokens > max_tokens_per_request
              yield("⚠️  [Agent] Large payload detected (~#{estimated_tokens} tokens), optimizing...\n") if block_given?
              Rails.logger.warn("[TechnicalAnalysisAgent] Large message payload: ~#{estimated_tokens} tokens (max: #{max_tokens_per_request}). Truncating...")
              # Further limit message history if needed
              messages = limit_message_history(messages)
              # Re-estimate after truncation
              total_chars = messages.sum { |m| (m[:content] || m['content'] || '').length }
              estimated_tokens = (total_chars / 4.0).ceil
            end

            response_chunks = +''
            chunk_count = 0

            # Stream: AI thinking indicator
            yield("🤔 [AI] Thinking...\n") if block_given?
            $stdout.flush if block_given?

            begin
              # Use streaming (logs only at completion, not during chunks)
              stream_start = Time.current
              @client.chat_stream(
                messages: messages,
                model: model,
                temperature: 0.3
              ) do |chunk|
                if chunk
                  response_chunks << chunk
                  chunk_count += 1
                  yield(chunk) if block_given?
                  $stdout.flush if block_given? # Ensure immediate output
                end
              end

              elapsed = Time.current - stream_start
              Rails.logger.debug { "[TechnicalAnalysisAgent] Stream completed in #{elapsed.round(2)}s (#{chunk_count} chunks, #{response_chunks.length} chars)" }
            rescue Timeout::Error, Faraday::TimeoutError, Net::ReadTimeout => e
              elapsed = Time.current - stream_start
              Rails.logger.warn("[TechnicalAnalysisAgent] Stream timeout after #{elapsed.round(2)}s: #{e.class} - #{e.message}")
              yield("\n⚠️  [Agent] Stream timeout after #{elapsed.round(2)}s: #{e.message}\n") if block_given?
            rescue StandardError => e
              elapsed = begin
                Time.current - stream_start
              rescue StandardError
                0
              end
              Rails.logger.error("[TechnicalAnalysisAgent] Stream error after #{elapsed.round(2)}s: #{e.class} - #{e.message}")
              Rails.logger.error("[TechnicalAnalysisAgent] Backtrace: #{e.backtrace.first(3).join("\n")}")
              yield("\n❌ [Agent] Stream error: #{e.message}\n") if block_given?
            end

            response = response_chunks
            full_response << response

            # Check if we got any response
            if response.blank? || response.strip.empty?
              yield("\n⚠️  [Agent] No response received from AI, retrying...\n") if block_given?
              Rails.logger.warn('[TechnicalAnalysisAgent] No response received, retrying iteration')
              iteration += 1
              next
            end

            # Stream: Response received
            yield("\n\n✅ [Agent] Response received (#{response.length} chars, #{chunk_count} chunks)\n") if block_given?

            # Check if response contains tool call
            tool_call = extract_tool_call(response)
            if tool_call
              consecutive_tool_calls += 1

              # Safety check: if we've called tools 10 times in a row without analysis, force a break
              if consecutive_tool_calls >= max_consecutive_tools
                yield("⚠️  [Agent] Too many consecutive tool calls (#{consecutive_tool_calls}), forcing analysis request...\n") if block_given?
                Rails.logger.warn("[TechnicalAnalysisAgent] Too many consecutive tool calls (#{consecutive_tool_calls}), forcing analysis request")
                messages << { role: 'assistant', content: response }
                messages << {
                  role: 'user',
                  content: 'You have called many tools. Please provide your analysis now based on all the data you have gathered. ' \
                           'Do not call any more tools - provide a complete analysis with your findings and actionable insights.'
                }
                consecutive_tool_calls = 0 # Reset counter
                messages = limit_message_history(messages)
                iteration += 1
                next
              end

              # Stream: Tool call detected
              yield("🔧 [Agent] Tool call detected: #{tool_call['tool']} (consecutive: #{consecutive_tool_calls})\n") if block_given?
              Rails.logger.info("[TechnicalAnalysisAgent] Executing tool: #{tool_call['tool']} (consecutive: #{consecutive_tool_calls})")

              # Stream: Tool execution start
              yield("⚙️  [Tool] Executing: #{tool_call['tool']}...\n") if block_given?

              # Execute tool
              tool_result = execute_tool(tool_call)

              # Record errors for learning
              if tool_result.is_a?(Hash) && tool_result[:error]
                record_error(
                  tool_name: tool_call['tool'],
                  error_message: tool_result[:error],
                  query_keywords: @current_query_keywords || []
                )
              end

              # Stream: Tool result
              yield("✅ [Tool] Completed: #{tool_call['tool']}\n") if block_given?
              yield("📋 [Tool] Result:\n#{JSON.pretty_generate(tool_result)}\n\n") if block_given?

              Rails.logger.info("[TechnicalAnalysisAgent] Tool completed: #{tool_call['tool']}")

              # Add assistant message and tool result to conversation
              messages << { role: 'assistant', content: response }
              messages << {
                role: 'user',
                content: "Tool result received. Now provide your analysis based on the data you've gathered. " \
                         'If you have all the information you need, provide a complete analysis. ' \
                         'If you need more data, call another tool.'
              }

              # Include full tool result
              tool_result_str = truncate_tool_result(tool_result)
              messages << {
                role: 'tool',
                content: "Tool: #{tool_call['tool']}\nResult: #{tool_result_str}"
              }

              # Stream: Prompting for analysis
              yield("💭 [Agent] Prompting AI for analysis based on tool results...\n\n") if block_given?

              # Limit message history to prevent token bloat
              messages = limit_message_history(messages)

              iteration += 1
              next
            end

            # No tool call - check if response is meaningful
            # Reset consecutive tool calls counter when we get a non-tool response
            consecutive_tool_calls = 0

            if response.strip.length > 20 && !response.match?(/\{"tool"/i)
              # Final response received (has content and no tool call)
              yield("\n✅ [Agent] Analysis complete - final response received!\n") if block_given?
              Rails.logger.info('[TechnicalAnalysisAgent] Analysis complete - final response received')
              break
            else
              # Empty or very short response - prompt for analysis
              yield("⚠️  [Agent] Short response received (#{response.length} chars), prompting for analysis...\n") if block_given?
              Rails.logger.warn("[TechnicalAnalysisAgent] Received very short response (#{response.length} chars), prompting for analysis...")
              messages << { role: 'assistant', content: response }
              messages << {
                role: 'user',
                content: 'Please provide a complete analysis based on the data you have gathered. ' \
                         'Summarize your findings and provide actionable insights. ' \
                         'Do not call more tools - provide your analysis now.'
              }

              # Limit message history
              messages = limit_message_history(messages)

              iteration += 1
              next
            end
          end

          if iteration >= safety_limit
            yield("\n⚠️  [Agent] Reached safety limit (#{safety_limit} iterations)\n") if block_given?
            Rails.logger.warn("[TechnicalAnalysisAgent] Reached safety limit (#{safety_limit} iterations)")
          end

          yield("\n🏁 [Agent] Completed in #{iteration} iteration(s)\n") if block_given?
          Rails.logger.info("[TechnicalAnalysisAgent] Completed in #{iteration} iteration(s)")

          # Save learned patterns at end of conversation
          save_learned_patterns if @error_history.any?

          {
            analysis: full_response,
            generated_at: Time.current,
            provider: @client.provider,
            iterations: iteration,
            errors_encountered: @error_history.size,
            learned_patterns_applied: @learned_patterns.count do |p|
              keywords = p[:keywords] || []
              keywords.any? do |kw|
                @current_query_keywords&.include?(kw)
              end
            end
          }
        rescue StandardError => e
          error_msg = "[Agent] Error: #{e.class} - #{e.message}\n"
          yield(error_msg) if block_given?
          Rails.logger.error("[TechnicalAnalysisAgent] Stream error: #{e.class} - #{e.message}")
          Rails.logger.error("[TechnicalAnalysisAgent] Backtrace: #{e.backtrace.first(5).join("\n")}")
          nil
        end
      end
    end
  end
end
