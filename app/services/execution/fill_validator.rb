# frozen_string_literal: true

module Execution
  class FillValidator
    def self.valid?(order_response)
      return false if order_response.nil?
      return false unless order_response[:status] == "success"
      return false if order_response[:filled_quantity].to_i <= 0

      true
    end
  end
end
