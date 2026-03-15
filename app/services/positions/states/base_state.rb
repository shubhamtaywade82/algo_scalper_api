# frozen_string_literal: true

module Positions
  module States
    # Abstract base for all PositionTracker states.
    # Subclasses declare which transitions are permitted and can override
    # lifecycle hooks (on_enter / on_exit) for side-effects such as logging.
    class BaseState
      attr_reader :tracker

      def initialize(tracker)
        @tracker = tracker
      end

      # ── Capability guards ──────────────────────────────────────────────────
      # Each returns false by default; concrete states override as needed.

      def can_activate?       = false
      def can_trail?          = false
      def can_request_exit?   = false
      def can_close?          = false
      def terminal?           = false

      # ── Lifecycle hooks ────────────────────────────────────────────────────
      def on_enter; end
      def on_exit;  end

      # ── Identity ───────────────────────────────────────────────────────────
      def name
        self.class.name.demodulize.underscore.delete_suffix('_state')
      end

      def to_s
        "#<#{self.class.name} order_no=#{tracker&.order_no}>"
      end

      private

      def log(msg)
        Rails.logger.debug("[#{self.class.name}] #{tracker&.order_no}: #{msg}")
      end
    end
  end
end
