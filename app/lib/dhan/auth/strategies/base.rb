# frozen_string_literal: true

module Dhan
  module Auth
    module Strategies
      # Abstract base class for all Dhan authentication strategies.
      # Each subclass implements #call and returns a normalized token hash.
      class Base
        # @return [Hash] { access_token: String, expiry_time: Time }
        def call
          raise NotImplementedError, "#{self.class}#call is not implemented"
        end

        private

        def normalize_response(token:, expiry:)
          {
            access_token: token,
            expiry_time: expiry
          }
        end
      end
    end
  end
end
