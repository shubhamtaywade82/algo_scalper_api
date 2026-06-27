# frozen_string_literal: true

module Ai
  module Autonomous
    class OptimizationJob < ApplicationJob
      queue_as :background

      def perform(days: 30, dry_run: false)
        symbols = IndiaIndexRegistry.all_by_key.keys
        symbols.each do |symbol|
          Rails.logger.info("[OptimizationJob] Starting self-learning optimization for #{symbol}")
          Ai::Autonomous::Orchestrator.call(symbol: symbol, days: days, dry_run: dry_run)
        rescue StandardError => e
          Rails.logger.error("[OptimizationJob] Failed for #{symbol}: #{e.message}")
        end
      end
    end
  end
end
