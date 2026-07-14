# frozen_string_literal: true

module Ledger
  module OrderResponse
    module_function

    def extract_order_id(response)
      return response[:order_id] || response['order_id'] if response.is_a?(Hash)
      return response.order_id if response.respond_to?(:order_id)

      nil
    end

    def paper?(response)
      return response[:paper] == true || response['paper'] == true if response.is_a?(Hash)
      return response.paper == true if response.respond_to?(:paper)

      false
    end
  end
end
