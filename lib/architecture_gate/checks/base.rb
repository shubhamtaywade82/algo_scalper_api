# frozen_string_literal: true

module ArchitectureGate
  module Checks
    class Base
      attr_reader :config, :report

      def initialize(config, report)
        @config = config
        @report = report
      end

      def run(paths)
        raise NotImplementedError, "Subclasses must implement #run(paths)"
      end
    end
  end
end
