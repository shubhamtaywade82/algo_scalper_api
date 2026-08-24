# frozen_string_literal: true

# rubocop:disable Rails/Output
module Ai
  module TradingBot
    # Post-trade self-learning loop.
    # Queries LLM for lessons from closed trades and stores them.
    class SelfLearning
      def initialize(config)
        @config = config
        @client = Services::Ai::OllamaClient.instance
      end

      # Analyzes closed trades and extracts lessons.
      def process_closed_trades
        return unless @config.paper? || @config.live?

        closed = fetch_recent_closed_trades
        return if closed.empty?

        lessons = extract_lessons(closed)
        store_lessons(lessons) if lessons.any?
      end

      private

      def fetch_recent_closed_trades(limit: 20)
        scope = @config.paper? ? PositionTracker.paper : PositionTracker.live
        scope.exited.order(exited_at: :desc).limit(limit).map do |tracker|
          {
            symbol: tracker.symbol,
            direction: tracker.direction,
            entry_price: tracker.entry_price&.to_f,
            exit_price: tracker.exit_price&.to_f,
            pnl: tracker.last_pnl_rupees&.to_f,
            exit_reason: tracker.exit_reason
          }
        end
      end

      def extract_lessons(trades)
        return [] if trades.empty?

        prompt = build_learning_prompt(trades)

        messages = [
          { role: 'system', content: learning_system_prompt },
          { role: 'user', content: prompt }
        ]

        response = @client.chat(
          messages: messages,
          model: @config.model,
          temperature: 0.3
        )

        parse_lessons(response)
      rescue StandardError => e
        puts "  SelfLearning error: #{e.message}"
        []
      end

      def learning_system_prompt
        <<~PROMPT
          You are a trading performance analyst.
          Analyze the provided closed trades and extract actionable lessons.
          Focus on:
          - What worked well (patterns to repeat)
          - What went wrong (mistakes to avoid)
          - Entry timing quality
          - Exit execution quality
          - Risk management effectiveness

          Output format:
          Lesson: <concise lesson>
          Category: <entry_timing|exit_execution|risk_management|pattern_recognition>
          Confidence: <0.0 to 1.0>
        PROMPT
      end

      def build_learning_prompt(trades)
        lines = trades.map do |t|
          "#{t[:symbol]} #{t[:direction]} entry=#{t[:entry_price]} exit=#{t[:exit_price]} " \
            "pnl=#{t[:pnl]} reason=#{t[:exit_reason]}"
        end

        "Recent closed trades:\n#{lines.join("\n")}"
      end

      def parse_lessons(response)
        return [] unless response.is_a?(String)

        response.split("\n\n").filter_map do |block|
          lesson_match = block.match(/Lesson:\s*(.+)/i)
          category_match = block.match(/Category:\s*(.+)/i)
          confidence_match = block.match(/Confidence:\s*([\d.]+)/i)

          next unless lesson_match

          {
            lesson: lesson_match[1].strip,
            category: category_match ? category_match[1].strip : 'general',
            confidence: confidence_match ? confidence_match[1].to_f : 0.5,
            timestamp: Time.current
          }
        end
      end

      def store_lessons(lessons)
        # Store in database for future reference
        # This could be a simple table or Redis
        lessons.each do |lesson|
          Rails.logger.info("[SelfLearning] Lesson: #{lesson[:lesson]} (#{lesson[:category]})")
        end
      end
    end
  end
end
# rubocop:enable Rails/Output
