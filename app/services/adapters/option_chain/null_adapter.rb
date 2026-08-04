# frozen_string_literal: true

module Adapters
  module OptionChain
    # Null adapter for paper mode / tests.
    # Returns safe empty values and never calls broker APIs.
    class NullAdapter
      # @return [nil]
      def fetch_chain(**)
        nil
      end

      # @return [Array]
      def fetch_expiry_list(**)
        []
      end
    end
  end
end
