# frozen_string_literal: true

# Quick Start Script for Service Testing (dev/test only)
# Usage (Rails console):
#   Testing::QuickStart.load!
if Rails.env.local?
  module Testing
    module QuickStart
      module_function

      def load!
        require_relative 'service_test_runner'
        true
      end
    end
  end
end
