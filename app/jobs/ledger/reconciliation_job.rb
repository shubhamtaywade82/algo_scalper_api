# frozen_string_literal: true

module Ledger
  class ReconciliationJob < ApplicationJob
    queue_as :background

    def perform
      return unless Config.enabled? || Config.shadow_mode?

      result = BalanceChecker.compare_paper_wallet
      if result[:cash_drift].to_d.abs > 1.0 || result[:equity_drift].to_d.abs > 1.0
        Rails.logger.warn("[Ledger::ReconciliationJob] drift detected: #{result}")
      else
        Rails.logger.info("[Ledger::ReconciliationJob] balances aligned: cash_drift=#{result[:cash_drift]}")
      end
    end
  end
end
