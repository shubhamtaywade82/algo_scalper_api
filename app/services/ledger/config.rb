# frozen_string_literal: true

module Ledger
  module Config
    module_function

    def fetch
      AlgoConfig.fetch[:ledger] || {}
    rescue StandardError
      {}
    end

    def enabled?
      fetch[:enabled] == true
    end

    def paper_enabled?
      enabled? && fetch.fetch(:paper_enabled, true) != false
    end

    def shadow_mode?
      fetch.fetch(:shadow_mode, true) == true
    end

    def block_negative_cash?
      fetch.fetch(:block_negative_cash, true) != false
    end

    def posting_enabled_for_paper?
      enabled? || shadow_mode?
    end
  end
end
