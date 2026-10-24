# frozen_string_literal: true

module Entries
  class DecisionRejection
    attr_reader :code, :category, :message, :details

    def initialize(code:, category: :risk, message: nil, details: {})
      @code = code.to_sym
      @category = category.to_sym
      @message = message || code.to_s.tr('_', ' ').capitalize
      @details = details || {}
    end

    def approved?
      false
    end

    def rejected?
      true
    end

    def to_h
      {
        approved: false,
        code: code,
        category: category,
        message: message,
        details: details
      }
    end
  end
end
